//! PvP duels: two runners, first to cover target_m (default 500 m) wins.
//! Distances come from the same trusted GPS pipeline as everything else;
//! the winner is whoever's filtered track crossed the target EARLIEST by
//! GPS timestamp — not whoever's phone polled first.

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    activities::compute, auth::jwt::AuthUser, error::AppError, gamification::rules, state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/join", post(join))
        .route("/current", get(current))
        .route("/{id}", get(detail))
        .route("/{id}/cancel", post(cancel))
}

#[derive(Debug, sqlx::FromRow)]
struct Duel {
    id: Uuid,
    code: String,
    creator_id: Uuid,
    opponent_id: Option<Uuid>,
    target_m: f64,
    reward_points: i64,
    status: String,
    winner_id: Option<Uuid>,
}

const DUEL_COLS: &str =
    "id, code, creator_id, opponent_id, target_m, reward_points, status, winner_id";

#[derive(Deserialize)]
struct CreateDuel {
    target_m: Option<f64>,
}

async fn create(
    user: AuthUser,
    State(state): State<AppState>,
    body: Option<Json<CreateDuel>>,
) -> Result<Json<Value>, AppError> {
    let target = body
        .map(|Json(b)| b.target_m.unwrap_or(500.0))
        .unwrap_or(500.0);
    if !(100.0..=10_000.0).contains(&target) {
        return Err(AppError::BadRequest(
            "target_m phải từ 100 đến 10.000".into(),
        ));
    }

    let code = join_code();
    let duel: Duel = sqlx::query_as(&format!(
        "INSERT INTO duels (code, creator_id, target_m) VALUES ($1, $2, $3)
         RETURNING {DUEL_COLS}"
    ))
    .bind(&code)
    .bind(user.user_id)
    .bind(target)
    .fetch_one(&state.db)
    .await?;

    render(&state, duel, user.user_id).await.map(Json)
}

fn join_code() -> String {
    const CHARS: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::rng();
    (0..6)
        .map(|_| CHARS[rng.random_range(0..CHARS.len())] as char)
        .collect()
}

#[derive(Deserialize)]
struct JoinDuel {
    code: String,
}

async fn join(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<JoinDuel>,
) -> Result<Json<Value>, AppError> {
    let duel: Option<Duel> = sqlx::query_as(&format!(
        "UPDATE duels SET opponent_id = $2, status = 'active'
         WHERE code = $1 AND status = 'open' AND creator_id != $2 AND opponent_id IS NULL
         RETURNING {DUEL_COLS}"
    ))
    .bind(body.code.trim().to_uppercase())
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?;

    match duel {
        Some(d) => render(&state, d, user.user_id).await.map(Json),
        None => Err(AppError::BadRequest(
            "mã không đúng, trận đã bắt đầu, hoặc đây là trận của chính bạn".into(),
        )),
    }
}

/// The caller's most recent unfinished duel (open or active).
async fn current(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let duel: Option<Duel> = sqlx::query_as(&format!(
        "SELECT {DUEL_COLS} FROM duels
         WHERE (creator_id = $1 OR opponent_id = $1) AND status IN ('open', 'active')
         ORDER BY created_at DESC LIMIT 1"
    ))
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?;

    match duel {
        Some(d) => render(&state, d, user.user_id).await.map(Json),
        None => Ok(Json(json!({ "exists": false }))),
    }
}

async fn detail(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    let duel: Duel = sqlx::query_as(&format!("SELECT {DUEL_COLS} FROM duels WHERE id = $1"))
        .bind(id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    if duel.creator_id != user.user_id && duel.opponent_id != Some(user.user_id) {
        return Err(AppError::NotFound);
    }
    render(&state, duel, user.user_id).await.map(Json)
}

async fn cancel(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    let cancelled = sqlx::query(
        "UPDATE duels SET status = 'cancelled' WHERE id = $1 AND creator_id = $2 AND status = 'open'",
    )
    .bind(id)
    .bind(user.user_id)
    .execute(&state.db)
    .await?;
    if cancelled.rows_affected() == 0 {
        return Err(AppError::BadRequest(
            "chỉ huỷ được trận đang chờ do bạn tạo".into(),
        ));
    }
    Ok(Json(json!({ "cancelled": true })))
}

#[derive(Serialize)]
struct PlayerState {
    user_id: Uuid,
    display_name: String,
    is_me: bool,
    distance_m: f64,
    crossed_at: Option<DateTime<Utc>>,
    has_session: bool,
}

/// Builds the live duel snapshot; while active, computes both players'
/// filtered distances and settles the winner when someone has crossed.
async fn render(state: &AppState, duel: Duel, me: Uuid) -> Result<Value, AppError> {
    let mut players = Vec::new();
    let mut duel = duel;

    for pid in [Some(duel.creator_id), duel.opponent_id]
        .into_iter()
        .flatten()
    {
        let (display_name, phone): (Option<String>, String) =
            sqlx::query_as("SELECT display_name, phone FROM users WHERE id = $1")
                .bind(pid)
                .fetch_one(&state.db)
                .await?;
        let name = display_name
            .unwrap_or_else(|| format!("Runner •••{}", &phone[phone.len().saturating_sub(3)..]));

        let session: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM activity_sessions WHERE duel_id = $1 AND user_id = $2")
                .bind(duel.id)
                .bind(pid)
                .fetch_optional(&state.db)
                .await?;

        let (distance, crossed_at) = if let Some((session_id,)) = session {
            let points: Vec<compute::Point> = sqlx::query_as(
                "SELECT recorded_at, lat, lon, horizontal_accuracy_m
                 FROM gps_points WHERE session_id = $1 ORDER BY recorded_at",
            )
            .bind(session_id)
            .fetch_all(&state.db)
            .await?;
            let stats = compute::session_stats(&points);
            (
                stats.distance_m,
                compute::crossing_time(&points, duel.target_m),
            )
        } else {
            (0.0, None)
        };

        players.push(PlayerState {
            user_id: pid,
            display_name: name,
            is_me: pid == me,
            distance_m: distance,
            crossed_at,
            has_session: session.is_some(),
        });
    }

    // Settle: earliest GPS crossing wins.
    if duel.status == "active" {
        let winner = players
            .iter()
            .filter_map(|p| p.crossed_at.map(|t| (p.user_id, t)))
            .min_by_key(|(_, t)| *t);
        if let Some((winner_id, _)) = winner {
            let settled = sqlx::query(
                "UPDATE duels SET status = 'finished', winner_id = $2, finished_at = now()
                 WHERE id = $1 AND status = 'active'",
            )
            .bind(duel.id)
            .bind(winner_id)
            .execute(&state.db)
            .await?;
            if settled.rows_affected() > 0 {
                mint_win(state, winner_id, &duel).await?;
            }
            duel.status = "finished".into();
            duel.winner_id = Some(winner_id);
        }
    }

    Ok(json!({
        "exists": true,
        "id": duel.id,
        "code": duel.code,
        "target_m": duel.target_m,
        "reward_points": duel.reward_points,
        "status": duel.status,
        "winner_id": duel.winner_id,
        "players": players,
    }))
}

async fn mint_win(state: &AppState, winner_id: Uuid, duel: &Duel) -> Result<(), AppError> {
    let mut tx = state.db.begin().await?;
    let inserted = sqlx::query(
        "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
         VALUES ($1, $2, 'duel_win', $3, $4, $5) ON CONFLICT DO NOTHING",
    )
    .bind(winner_id)
    .bind(duel.reward_points)
    .bind(duel.id)
    .bind(rules::RULES_VERSION)
    .bind(rules::current_season())
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() > 0 {
        sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
            .bind(winner_id)
            .bind(duel.reward_points)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}
