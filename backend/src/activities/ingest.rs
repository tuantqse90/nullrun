//! GPS ingestion pipeline: handlers XADD point batches to a Redis stream;
//! a single background worker drains it into TimescaleDB.
//!
//! Delivery is at-least-once: the cursor (last processed stream id) is
//! persisted AFTER the batch insert, and gps_points' primary key dedups
//! replays via ON CONFLICT DO NOTHING. Single-consumer by design — the
//! backend deploys as one instance for now; move to consumer groups when
//! that changes.

use chrono::{DateTime, Utc};
use fred::prelude::*;
use fred::types::streams::{XCapKind, XCapTrim};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{error::AppError, state::AppState};

pub const STREAM_KEY: &str = "ingest:gps";
const CURSOR_KEY: &str = "ingest:gps:cursor";
const READ_BATCH: u64 = 200;
const BLOCK_MS: u64 = 5_000;

#[derive(Debug, Serialize, Deserialize)]
pub struct PointsBatch {
    pub session_id: Uuid,
    pub points: Vec<IngestPoint>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IngestPoint {
    pub recorded_at: DateTime<Utc>,
    pub lat: f64,
    pub lon: f64,
    pub altitude_m: Option<f64>,
    pub horizontal_accuracy_m: Option<f64>,
    pub speed_mps: Option<f64>,
    pub step_cadence: Option<f64>,
}

/// Publishes a batch to the stream. Returns the stream id, which the caller
/// records so `finish` can wait for the flush (see `wait_for_flush`).
pub async fn publish(redis: &Client, batch: &PointsBatch) -> Result<String, AppError> {
    let payload =
        serde_json::to_string(batch).map_err(|e| AppError::Internal(format!("serialize: {e}")))?;
    let id: String = redis
        .xadd(STREAM_KEY, false, None, "*", ("batch", payload))
        .await?;
    // Remember the newest pending id per session so finish can flush-wait.
    let _: () = redis
        .set(
            last_id_key(batch.session_id),
            &id,
            Some(Expiration::EX(86_400)),
            None,
            false,
        )
        .await?;
    Ok(id)
}

fn last_id_key(session_id: Uuid) -> String {
    format!("ingest:gps:last:{session_id}")
}

/// Blocks (bounded) until the worker's cursor has passed the last batch
/// published for this session, so finish computes on complete data.
pub async fn wait_for_flush(redis: &Client, session_id: Uuid) -> Result<(), AppError> {
    let last: Option<String> = redis.get(last_id_key(session_id)).await?;
    let Some(last) = last else { return Ok(()) };
    let target = parse_stream_id(&last);

    for _ in 0..25 {
        let cursor: Option<String> = redis.get(CURSOR_KEY).await?;
        if cursor
            .map(|c| parse_stream_id(&c) >= target)
            .unwrap_or(false)
        {
            return Ok(());
        }
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    }
    tracing::warn!(%session_id, "ingest flush wait timed out — stats may miss trailing points");
    Ok(())
}

fn parse_stream_id(id: &str) -> (u64, u64) {
    let mut parts = id.splitn(2, '-');
    let ms = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
    let seq = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
    (ms, seq)
}

/// Background worker: XREAD → batch insert → advance cursor → trim stream.
/// Uses its own Redis connection — XREAD BLOCK must not stall the shared
/// multiplexed client.
pub async fn run_gps_writer(state: AppState) {
    let redis = state.redis.clone_new();
    if let Err(e) = redis.init().await {
        tracing::error!(error = %e, "gps writer: redis init failed — ingestion down");
        return;
    }
    tracing::info!("gps ingestion worker started");

    loop {
        if let Err(e) = drain_once(&redis, &state.db).await {
            tracing::error!(error = %e, "gps writer iteration failed; backing off");
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    }
}

async fn drain_once(redis: &Client, db: &PgPool) -> Result<(), AppError> {
    let cursor: Option<String> = redis.get(CURSOR_KEY).await?;
    let cursor = cursor.unwrap_or_else(|| "0-0".into());

    type Entries = Vec<(String, Vec<(String, String)>)>;
    let resp: Vec<(String, Entries)> = redis
        .xread(Some(READ_BATCH), Some(BLOCK_MS), STREAM_KEY, cursor)
        .await?;

    let Some((_, entries)) = resp.into_iter().next() else {
        return Ok(()); // timed out with nothing to read
    };
    if entries.is_empty() {
        return Ok(());
    }

    let mut max_id = (0, 0);
    let mut max_id_raw = String::new();
    let mut batches = Vec::new();
    for (id, fields) in entries {
        if parse_stream_id(&id) > max_id {
            max_id = parse_stream_id(&id);
            max_id_raw = id.clone();
        }
        for (name, value) in fields {
            if name == "batch" {
                match serde_json::from_str::<PointsBatch>(&value) {
                    Ok(batch) => batches.push(batch),
                    // Poison entry: log and skip — never wedge the pipeline.
                    Err(e) => tracing::error!(error = %e, %id, "unparseable ingest entry dropped"),
                }
            }
        }
    }

    insert_batches(db, &batches).await?;

    let _: () = redis
        .set(CURSOR_KEY, &max_id_raw, None, None, false)
        .await?;
    // Everything at/below the cursor is durable in Postgres.
    let _: u64 = redis
        .xtrim(
            STREAM_KEY,
            (XCapKind::MinID, XCapTrim::Exact, max_id_raw.as_str()),
        )
        .await?;
    Ok(())
}

async fn insert_batches(db: &PgPool, batches: &[PointsBatch]) -> Result<(), AppError> {
    let n: usize = batches.iter().map(|b| b.points.len()).sum();
    if n == 0 {
        return Ok(());
    }

    let mut session_ids = Vec::with_capacity(n);
    let mut recorded_ats = Vec::with_capacity(n);
    let mut lats = Vec::with_capacity(n);
    let mut lons = Vec::with_capacity(n);
    let mut alts = Vec::with_capacity(n);
    let mut accs = Vec::with_capacity(n);
    let mut speeds = Vec::with_capacity(n);
    let mut cadences = Vec::with_capacity(n);

    for batch in batches {
        for p in &batch.points {
            session_ids.push(batch.session_id);
            recorded_ats.push(p.recorded_at);
            lats.push(p.lat);
            lons.push(p.lon);
            alts.push(p.altitude_m);
            accs.push(p.horizontal_accuracy_m);
            speeds.push(p.speed_mps);
            cadences.push(p.step_cadence);
        }
    }

    sqlx::query(
        "INSERT INTO gps_points
           (session_id, recorded_at, lat, lon, altitude_m, horizontal_accuracy_m, speed_mps, step_cadence)
         SELECT * FROM UNNEST($1::uuid[], $2::timestamptz[], $3::float8[], $4::float8[],
                              $5::float8[], $6::float8[], $7::float8[], $8::float8[])
         ON CONFLICT (session_id, recorded_at) DO NOTHING",
    )
    .bind(&session_ids)
    .bind(&recorded_ats)
    .bind(&lats)
    .bind(&lons)
    .bind(&alts)
    .bind(&accs)
    .bind(&speeds)
    .bind(&cadences)
    .execute(db)
    .await?;

    tracing::debug!(points = n, "gps batch inserted");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stream_id_ordering_is_numeric_not_lexicographic() {
        assert!(parse_stream_id("10-1") > parse_stream_id("9-99"));
        assert!(parse_stream_id("100-2") > parse_stream_id("100-1"));
        assert_eq!(parse_stream_id("0-0"), (0, 0));
    }
}
