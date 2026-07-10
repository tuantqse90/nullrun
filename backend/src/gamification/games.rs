//! Wellness games (seeded from the founder's games sheet). Definitions are
//! DB rows; this module only knows how to VERIFY each class:
//! auto_* from trusted server data, sensor_steps from the device pedometer
//! (attested devices only), and self-report — honor system with a small
//! reward and a hard daily cap so it can't become a farm.

use axum::{
    extract::{Path, State},
    Json,
};
use fred::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{auth::jwt::AuthUser, error::AppError, gamification::rules, state::AppState};

/// Max self-reported claims per VN day across all self games.
const SELF_CLAIMS_PER_DAY: i64 = 3;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct GameRow {
    pub code: String,
    pub title: String,
    pub description: String,
    pub category: String,
    pub tier: String,
    pub verification: String,
    pub target_value: f64,
    pub unit: String,
    pub reward_points: i64,
    pub cadence: String,
}

#[derive(Debug, Serialize)]
pub struct GameStatus {
    #[serde(flatten)]
    pub game: GameRow,
    pub progress: Option<f64>,
    pub completed: bool,
    pub claimable: bool,
}

struct AutoStats {
    distance_m: f64,
    longest_duration_s: f64,
    streak: i64,
}

async fn auto_stats(state: &AppState, user_id: Uuid) -> Result<AutoStats, AppError> {
    let (distance_m, longest): (f64, f64) = sqlx::query_as(
        "SELECT COALESCE(SUM(distance_m), 0)::float8, COALESCE(MAX(duration_s), 0)::float8
         FROM activity_sessions
         WHERE user_id = $1 AND status = 'completed' AND verdict = 'clean' AND created_at >= $2",
    )
    .bind(user_id)
    .bind(rules::vn_day_start_utc())
    .fetch_one(&state.db)
    .await?;
    let streak: i32 = sqlx::query_scalar("SELECT streak_current FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&state.db)
        .await?;
    Ok(AutoStats {
        distance_m,
        longest_duration_s: longest,
        streak: streak as i64,
    })
}

fn source_for(game: &GameRow, user_id: Uuid) -> Uuid {
    if game.cadence == "once" {
        Uuid::new_v5(
            &Uuid::NAMESPACE_OID,
            format!("game-once:{}:{user_id}", game.code).as_bytes(),
        )
    } else {
        rules::daily_source_id(user_id, &format!("game:{}", game.code))
    }
}

pub async fn list(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<GameStatus>>, AppError> {
    let games: Vec<GameRow> = sqlx::query_as(
        "SELECT code, title, description, category, tier, verification, target_value, unit,
                reward_points, cadence
         FROM games WHERE active ORDER BY sort",
    )
    .fetch_all(&state.db)
    .await?;
    let stats = auto_stats(&state, user.user_id).await?;

    let mut out = Vec::with_capacity(games.len());
    for game in games {
        let source = source_for(&game, user.user_id);
        let completed: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM points_ledger
             WHERE user_id = $1 AND kind = 'game_reward' AND source_id = $2)",
        )
        .bind(user.user_id)
        .bind(source)
        .fetch_one(&state.db)
        .await?;
        let progress = match game.verification.as_str() {
            "auto_distance" => Some(stats.distance_m),
            "auto_duration" => Some(stats.longest_duration_s),
            "auto_streak" => Some(stats.streak as f64),
            _ => None,
        };
        let claimable = !completed && progress.map(|p| p >= game.target_value).unwrap_or(true);
        out.push(GameStatus {
            game,
            progress,
            completed,
            claimable,
        });
    }
    Ok(Json(out))
}

#[derive(Deserialize, Default)]
pub struct ClaimBody {
    /// Sensor value for sensor_steps games (today's pedometer count).
    pub value: Option<f64>,
}

pub async fn claim(
    user: AuthUser,
    State(state): State<AppState>,
    Path(code): Path<String>,
    body: Option<Json<ClaimBody>>,
) -> Result<Json<Value>, AppError> {
    let body = body.map(|Json(b)| b).unwrap_or_default();
    let game: GameRow = sqlx::query_as(
        "SELECT code, title, description, category, tier, verification, target_value, unit,
                reward_points, cadence
         FROM games WHERE code = $1 AND active",
    )
    .bind(&code)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    // Verify per class.
    match game.verification.as_str() {
        "auto_distance" | "auto_duration" | "auto_streak" => {
            let stats = auto_stats(&state, user.user_id).await?;
            let progress = match game.verification.as_str() {
                "auto_distance" => stats.distance_m,
                "auto_duration" => stats.longest_duration_s,
                _ => stats.streak as f64,
            };
            if progress < game.target_value {
                return Err(AppError::BadRequest(format!(
                    "chưa đạt: {progress:.0}/{:.0} {}",
                    game.target_value, game.unit
                )));
            }
        }
        "sensor_steps" => {
            let attested: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM devices WHERE user_id = $1 AND attested_at IS NOT NULL)",
            )
            .bind(user.user_id)
            .fetch_one(&state.db)
            .await?;
            if !attested {
                return Err(AppError::BadRequest("cần thiết bị đã xác minh".into()));
            }
            let steps = body.value.unwrap_or(0.0);
            if steps < game.target_value {
                return Err(AppError::BadRequest(format!(
                    "chưa đạt: {steps:.0}/{:.0} bước",
                    game.target_value
                )));
            }
        }
        _ => {}
    }

    // self-report: hard daily cap across all self games, reserved ATOMICALLY
    // before the mint (INCR then check) so concurrent claims on distinct self
    // games can't both slip past a stale GET. The slot is released below if
    // the mint turns out to be a duplicate — only successful distinct claims
    // ultimately consume the cap.
    let cap_key = format!("game:selfcap:{}:{}", user.user_id, rules::vn_today());
    let mut reserved_slot = false;
    if game.verification == "self" {
        let count: i64 = state.redis.incr(&cap_key).await?;
        if count == 1 {
            let _: bool = state.redis.expire(&cap_key, 86_400, None).await?;
        }
        if count > SELF_CLAIMS_PER_DAY {
            let _: i64 = state.redis.decr(&cap_key).await?;
            return Err(AppError::TooManyRequests);
        }
        reserved_slot = true;
    }

    let source = source_for(&game, user.user_id);
    let mut tx = state.db.begin().await?;
    let inserted = sqlx::query(
        "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
         VALUES ($1, $2, 'game_reward', $3, $4, $5) ON CONFLICT DO NOTHING",
    )
    .bind(user.user_id)
    .bind(game.reward_points)
    .bind(source)
    .bind(rules::RULES_VERSION)
    .bind(rules::current_season())
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        tx.rollback().await?;
        if reserved_slot {
            let _: i64 = state.redis.decr(&cap_key).await?; // release: duplicate, not a new claim
        }
        return Err(AppError::BadRequest(match game.cadence.as_str() {
            "once" => "đã nhận thưởng cột mốc này rồi".into(),
            _ => "hôm nay đã hoàn thành game này rồi".into(),
        }));
    }
    sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
        .bind(user.user_id)
        .bind(game.reward_points)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(Json(
        json!({ "claimed": true, "points": game.reward_points, "title": game.title }),
    ))
}
