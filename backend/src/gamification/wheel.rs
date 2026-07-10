//! Lucky wheel — one spin per VN day, unlocked by a clean session today.
//! The prize is decided server-side BEFORE the animation (design: "kết quả
//! chốt trước khi quay"); the app just animates to the returned segment.
//! Wheel points hit the balance ledger but never the weekly leaderboard.

use rand::Rng;
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{error::AppError, gamification::rules};

/// Segments (value + weight) live in the wheel_segments table.
async fn load_segments(db: &PgPool) -> Result<Vec<(i64, i64)>, AppError> {
    let rows: Vec<(i64, i64)> =
        sqlx::query_as("SELECT value, weight::bigint FROM wheel_segments ORDER BY idx")
            .fetch_all(db)
            .await?;
    if rows.is_empty() {
        return Err(AppError::Internal("wheel_segments trống".into()));
    }
    Ok(rows)
}

#[derive(Debug, Serialize)]
pub struct WheelState {
    pub segments: Vec<i64>,
    pub available: bool,
    pub spun_today: bool,
    pub unlocked: bool,
}

pub async fn state(db: &PgPool, user_id: Uuid) -> Result<WheelState, AppError> {
    let segments = load_segments(db).await?;
    let unlocked = has_clean_session_today(db, user_id).await?;
    let spun_today = spun(db, user_id).await?;
    Ok(WheelState {
        segments: segments.iter().map(|(v, _)| *v).collect(),
        available: unlocked && !spun_today,
        spun_today,
        unlocked,
    })
}

#[derive(Debug, Serialize)]
pub struct SpinResult {
    pub prize: i64,
    pub segment_index: usize,
}

pub async fn spin(db: &PgPool, user_id: Uuid) -> Result<SpinResult, AppError> {
    if !has_clean_session_today(db, user_id).await? {
        return Err(AppError::BadRequest(
            "hoàn thành 1 buổi tập hôm nay để mở vòng quay".into(),
        ));
    }

    let segments = load_segments(db).await?;
    let segment_index = pick_segment(&segments);
    let prize = segments[segment_index].0;
    let source = rules::daily_source_id(user_id, "wheel");

    let mut tx = db.begin().await?;
    let inserted = sqlx::query(
        "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
         VALUES ($1, $2, 'wheel_prize', $3, $4, $5) ON CONFLICT DO NOTHING",
    )
    .bind(user_id)
    .bind(prize)
    .bind(source)
    .bind(rules::RULES_VERSION)
    .bind(rules::current_season())
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        tx.rollback().await?;
        return Err(AppError::BadRequest(
            "hôm nay đã quay rồi — mai quay tiếp nhé".into(),
        ));
    }
    sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
        .bind(user_id)
        .bind(prize)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(SpinResult {
        prize,
        segment_index,
    })
}

fn pick_segment(segments: &[(i64, i64)]) -> usize {
    let total: i64 = segments.iter().map(|(_, w)| w).sum();
    let mut roll = rand::rng().random_range(0..total.max(1));
    for (idx, (_, weight)) in segments.iter().enumerate() {
        if roll < *weight {
            return idx;
        }
        roll -= weight;
    }
    0
}

async fn has_clean_session_today(db: &PgPool, user_id: Uuid) -> Result<bool, AppError> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM activity_sessions
         WHERE user_id = $1 AND status = 'completed' AND verdict = 'clean' AND created_at >= $2)",
    )
    .bind(user_id)
    .bind(rules::vn_day_start_utc())
    .fetch_one(db)
    .await?)
}

async fn spun(db: &PgPool, user_id: Uuid) -> Result<bool, AppError> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM points_ledger
         WHERE user_id = $1 AND kind = 'wheel_prize' AND source_id = $2)",
    )
    .bind(user_id)
    .bind(rules::daily_source_id(user_id, "wheel"))
    .fetch_one(db)
    .await?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weighted_pick_stays_in_bounds() {
        let segments: Vec<(i64, i64)> =
            vec![(20, 25), (50, 15), (30, 20), (100, 5), (20, 20), (30, 15)];
        for _ in 0..200 {
            let idx = pick_segment(&segments);
            assert!(idx < segments.len());
        }
    }
}
