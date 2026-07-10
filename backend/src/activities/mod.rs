pub mod compute;
pub mod fraud;
pub mod ingest;

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use fred::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    auth::jwt::AuthUser,
    config::{MAX_SESSIONS_PER_DAY, SESSION_CREATE_COOLDOWN_SECS},
    error::AppError,
    state::AppState,
};

const MAX_POINTS_PER_BATCH: usize = 500;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", post(create).get(list))
        .route("/{id}", get(detail))
        .route("/{id}/points", post(push_points))
        .route("/{id}/pause", post(pause))
        .route("/{id}/resume", post(resume))
        .route("/{id}/finish", post(finish))
        .route("/{id}/discard", post(discard))
}

#[derive(Debug, Serialize, sqlx::FromRow)]
struct Session {
    id: Uuid,
    activity_type: String,
    status: String,
    started_at: DateTime<Utc>,
    ended_at: Option<DateTime<Utc>>,
    distance_m: f64,
    duration_s: f64,
    avg_pace_s_per_km: Option<f64>,
    fraud_score: Option<f64>,
    fraud_flags: Vec<String>,
    verdict: String,
}

const SESSION_COLS: &str = "id, activity_type, status, started_at, ended_at, distance_m, \
                            duration_s, avg_pace_s_per_km, fraud_score, fraud_flags, verdict";

#[derive(Deserialize)]
struct CreateSession {
    activity_type: String,
    device_id: Option<Uuid>,
    duel_id: Option<Uuid>,
}

async fn create(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<CreateSession>,
) -> Result<Json<Session>, AppError> {
    if !matches!(body.activity_type.as_str(), "walk" | "run") {
        return Err(AppError::BadRequest(
            "activity_type must be walk or run".into(),
        ));
    }

    if let Some(device_id) = body.device_id {
        let owned: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM devices WHERE id = $1 AND user_id = $2)",
        )
        .bind(device_id)
        .bind(user.user_id)
        .fetch_one(&state.db)
        .await?;
        if !owned {
            return Err(AppError::BadRequest("unknown device_id".into()));
        }
    }

    if let Some(duel_id) = body.duel_id {
        let valid: bool = sqlx::query_scalar(
            "SELECT EXISTS(
                SELECT 1 FROM duels d
                WHERE d.id = $1 AND d.status = 'active'
                  AND (d.creator_id = $2 OR d.opponent_id = $2)
                  AND NOT EXISTS(SELECT 1 FROM activity_sessions s
                                 WHERE s.duel_id = d.id AND s.user_id = $2))",
        )
        .bind(duel_id)
        .bind(user.user_id)
        .fetch_one(&state.db)
        .await?;
        if !valid {
            return Err(AppError::BadRequest(
                "trận đấu không hợp lệ hoặc bạn đã chạy trận này".into(),
            ));
        }
    }

    // Caps are checked here but recorded only after a successful insert —
    // a create that fails (validation, stranded open session) must not
    // burn the cooldown, or the client's discard-and-retry heal gets 429.
    check_create_caps(&state, user.user_id).await?;

    let result: Result<Session, sqlx::Error> = sqlx::query_as(&format!(
        "INSERT INTO activity_sessions (user_id, device_id, activity_type, duel_id)
         VALUES ($1, $2, $3, $4) RETURNING {SESSION_COLS}"
    ))
    .bind(user.user_id)
    .bind(body.device_id)
    .bind(&body.activity_type)
    .bind(body.duel_id)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok(session) => {
            // Best-effort: the session exists — a Redis hiccup must not
            // fail the request (the caps just go uncounted this once).
            if let Err(e) = record_create(&state, user.user_id).await {
                tracing::error!(error = %e, user_id = %user.user_id, "create caps not recorded");
            }
            Ok(Json(session))
        }
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => Err(AppError::BadRequest(
            "an open session already exists — finish or discard it first".into(),
        )),
        Err(e) => Err(e.into()),
    }
}

/// Per-user cooldown + daily cap on session creation (guardrail #1: rate
/// caps make session farming unprofitable before points even exist).
/// Read-only — only successful creates are counted (see record_create).
async fn check_create_caps(state: &AppState, user_id: Uuid) -> Result<(), AppError> {
    let on_cooldown: i64 = state
        .redis
        .exists(format!("rate:session:cd:{user_id}"))
        .await?;
    if on_cooldown > 0 {
        return Err(AppError::TooManyRequests);
    }
    let day_key = format!("rate:session:day:{user_id}:{}", Utc::now().format("%Y%m%d"));
    let count: Option<i64> = state.redis.get(&day_key).await?;
    if count.unwrap_or(0) >= MAX_SESSIONS_PER_DAY {
        return Err(AppError::TooManyRequests);
    }
    Ok(())
}

/// Stamps the cooldown + daily count for a create that actually happened.
async fn record_create(state: &AppState, user_id: Uuid) -> Result<(), AppError> {
    let _: () = state
        .redis
        .set(
            format!("rate:session:cd:{user_id}"),
            "1",
            Some(Expiration::EX(SESSION_CREATE_COOLDOWN_SECS)),
            None,
            false,
        )
        .await?;
    let day_key = format!("rate:session:day:{user_id}:{}", Utc::now().format("%Y%m%d"));
    let count: i64 = state.redis.incr(&day_key).await?;
    if count == 1 {
        let _: bool = state.redis.expire(&day_key, 86_400, None).await?;
    }
    Ok(())
}

#[derive(Deserialize)]
struct ListParams {
    limit: Option<i64>,
}

async fn list(
    user: AuthUser,
    State(state): State<AppState>,
    Query(params): Query<ListParams>,
) -> Result<Json<Vec<Session>>, AppError> {
    let limit = params.limit.unwrap_or(20).clamp(1, 100);
    let sessions: Vec<Session> = sqlx::query_as(&format!(
        "SELECT {SESSION_COLS} FROM activity_sessions
         WHERE user_id = $1 AND status != 'discarded'
         ORDER BY started_at DESC LIMIT $2"
    ))
    .bind(user.user_id)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(sessions))
}

async fn detail(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Session>, AppError> {
    fetch_owned(&state, user.user_id, id).await.map(Json)
}

#[derive(Deserialize)]
struct PointsPayload {
    points: Vec<ingest::IngestPoint>,
}

/// Accepts a batch of GPS samples for an open session. Samples go through
/// the Redis stream, not straight to Postgres — this is the hot path.
async fn push_points(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<PointsPayload>,
) -> Result<Json<Value>, AppError> {
    if body.points.is_empty() {
        return Err(AppError::BadRequest("points must not be empty".into()));
    }
    if body.points.len() > MAX_POINTS_PER_BATCH {
        return Err(AppError::BadRequest(format!(
            "at most {MAX_POINTS_PER_BATCH} points per batch"
        )));
    }
    for p in &body.points {
        if !(-90.0..=90.0).contains(&p.lat) || !(-180.0..=180.0).contains(&p.lon) {
            return Err(AppError::BadRequest("lat/lon out of range".into()));
        }
    }

    let session = fetch_owned(&state, user.user_id, id).await?;
    if !matches!(session.status.as_str(), "active" | "paused") {
        return Err(AppError::BadRequest("session is not open".into()));
    }

    let accepted = body.points.len();
    ingest::publish(
        &state.redis,
        &ingest::PointsBatch {
            session_id: id,
            points: body.points,
        },
    )
    .await?;

    Ok(Json(json!({ "accepted": accepted })))
}

async fn pause(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Session>, AppError> {
    transition(&state, user.user_id, id, "active", "paused").await
}

async fn resume(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Session>, AppError> {
    transition(&state, user.user_id, id, "paused", "active").await
}

/// Closes the session: computes server-authoritative stats from the ingested
/// points (after waiting for the stream to flush), then runs the fraud
/// evaluation. The verdict decides whether this session may ever mint points.
async fn finish(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    let session = fetch_owned(&state, user.user_id, id).await?;
    if !matches!(session.status.as_str(), "active" | "paused") {
        return Err(AppError::BadRequest("session is not open".into()));
    }

    ingest::wait_for_flush(&state.redis, id).await?;

    let samples: Vec<fraud::Sample> = sqlx::query_as(
        "SELECT recorded_at, lat, lon, horizontal_accuracy_m, step_cadence
         FROM gps_points WHERE session_id = $1 ORDER BY recorded_at",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;
    let points: Vec<compute::Point> = samples.iter().map(|s| s.as_point()).collect();
    let stats = compute::session_stats(&points);

    let attested: bool = sqlx::query_scalar(
        "SELECT EXISTS(
            SELECT 1 FROM activity_sessions s JOIN devices d ON d.id = s.device_id
            WHERE s.id = $1 AND d.attested_at IS NOT NULL)",
    )
    .bind(id)
    .fetch_one(&state.db)
    .await?;

    let eval = fraud::evaluate(
        &session.activity_type,
        attested,
        stats.distance_m,
        stats.duration_s,
        &samples,
    );
    if eval.verdict != "clean" {
        tracing::warn!(session_id = %id, score = eval.score, flags = ?eval.flags,
                       verdict = eval.verdict, "session flagged by fraud engine");
    }

    let flags: Vec<String> = eval.flags.iter().map(|f| f.to_string()).collect();
    let updated: Option<Session> = sqlx::query_as(&format!(
        "UPDATE activity_sessions
         SET status = 'completed', ended_at = now(), distance_m = $3, duration_s = $4,
             avg_pace_s_per_km = $5, fraud_score = $6, fraud_flags = $7, verdict = $8,
             updated_at = now()
         WHERE id = $1 AND user_id = $2 AND status IN ('active', 'paused')
         RETURNING {SESSION_COLS}"
    ))
    .bind(id)
    .bind(user.user_id)
    .bind(stats.distance_m)
    .bind(stats.duration_s)
    .bind(stats.avg_pace_s_per_km)
    .bind(eval.score)
    .bind(&flags)
    .bind(eval.verdict)
    .fetch_optional(&state.db)
    .await?;

    // Make finish() safely retryable: if a prior finish already completed the
    // session but the mint then failed (or the client retries after a
    // timeout), re-fetch the completed session and re-run the idempotent
    // mint below instead of 404-ing and stranding the points unminted.
    let session: Session = match updated {
        Some(s) => s,
        None => sqlx::query_as(&format!(
            "SELECT {SESSION_COLS} FROM activity_sessions
             WHERE id = $1 AND user_id = $2 AND status = 'completed'"
        ))
        .bind(id)
        .bind(user.user_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?,
    };

    // Genuine-only earning: ONLY clean sessions reach the mint (idempotent).
    let (points_earned, challenge_bonus) = if session.verdict == "clean" {
        crate::gamification::on_clean_session(
            &state,
            user.user_id,
            id,
            &session.activity_type,
            session.distance_m,
        )
        .await?
    } else {
        (0, 0)
    };

    let mut resp = serde_json::to_value(&session)
        .map_err(|e| AppError::Internal(format!("serialize session: {e}")))?;
    resp["points_earned"] = points_earned.into();
    resp["challenge_bonus"] = challenge_bonus.into();
    Ok(Json(resp))
}

async fn discard(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Session>, AppError> {
    let session: Session = sqlx::query_as(&format!(
        "UPDATE activity_sessions
         SET status = 'discarded', ended_at = now(), updated_at = now()
         WHERE id = $1 AND user_id = $2 AND status IN ('active', 'paused')
         RETURNING {SESSION_COLS}"
    ))
    .bind(id)
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;
    Ok(Json(session))
}

async fn transition(
    state: &AppState,
    user_id: Uuid,
    id: Uuid,
    from: &str,
    to: &str,
) -> Result<Json<Session>, AppError> {
    let session: Option<Session> = sqlx::query_as(&format!(
        "UPDATE activity_sessions SET status = $4, updated_at = now()
         WHERE id = $1 AND user_id = $2 AND status = $3
         RETURNING {SESSION_COLS}"
    ))
    .bind(id)
    .bind(user_id)
    .bind(from)
    .bind(to)
    .fetch_optional(&state.db)
    .await?;

    match session {
        Some(s) => Ok(Json(s)),
        // Distinguish "wrong state" from "not yours/missing" for the client.
        None => match fetch_owned(state, user_id, id).await {
            Ok(s) => Err(AppError::BadRequest(format!(
                "cannot transition from '{}' (expected '{from}')",
                s.status
            ))),
            Err(e) => Err(e),
        },
    }
}

async fn fetch_owned(state: &AppState, user_id: Uuid, id: Uuid) -> Result<Session, AppError> {
    sqlx::query_as(&format!(
        "SELECT {SESSION_COLS} FROM activity_sessions WHERE id = $1 AND user_id = $2"
    ))
    .bind(id)
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)
}
