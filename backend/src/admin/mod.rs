//! Internal admin console + partner dashboard APIs (M6).
//!
//! Auth is a static token per audience (x-admin-token / x-partner-token) —
//! good enough while the only operators are the founders. Replace with real
//! role-based auth before anyone else gets access.

use axum::{
    extract::{FromRequestParts, Path, Query, State},
    http::request::Parts,
    routing::{get, patch, post},
    Json, Router,
};
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    auth::phone::normalize_vn_phone, error::AppError, gamification, gamification::rules,
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/admin/stats", get(stats))
        .route("/admin/review-queue", get(review_queue))
        .route("/admin/sessions/{id}/review", post(review_session))
        .route("/admin/users/{phone}", get(user_lookup))
        .route("/admin/users/{phone}/adjust", post(adjust_points))
        .route("/admin/challenges", post(create_challenge))
        .route("/admin/rewards", post(create_reward))
        .route("/admin/rewards/{id}", patch(update_reward))
        .route("/partner/stats", get(partner_stats))
}

pub struct AdminAuth;

impl FromRequestParts<AppState> for AdminAuth {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get("x-admin-token")
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default();
        if token == state.config.admin_api_token {
            Ok(AdminAuth)
        } else {
            Err(AppError::Unauthorized)
        }
    }
}

pub struct PartnerAuth;

impl FromRequestParts<AppState> for PartnerAuth {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get("x-partner-token")
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default();
        if token == state.config.partner_api_token {
            Ok(PartnerAuth)
        } else {
            Err(AppError::Unauthorized)
        }
    }
}

/// Today-at-a-glance (VN day) for the admin console.
async fn stats(_: AdminAuth, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let day_start = rules::vn_day_start_utc();

    let total_users: i64 = sqlx::query_scalar("SELECT count(*) FROM users")
        .fetch_one(&state.db)
        .await?;
    let new_users: i64 = sqlx::query_scalar("SELECT count(*) FROM users WHERE created_at >= $1")
        .bind(day_start)
        .fetch_one(&state.db)
        .await?;
    let active_users: i64 = sqlx::query_scalar(
        "SELECT count(DISTINCT user_id) FROM activity_sessions WHERE created_at >= $1",
    )
    .bind(day_start)
    .fetch_one(&state.db)
    .await?;
    let sessions: Vec<(String, i64)> = sqlx::query_as(
        "SELECT verdict, count(*) FROM activity_sessions WHERE created_at >= $1 GROUP BY verdict",
    )
    .bind(day_start)
    .fetch_all(&state.db)
    .await?;
    let points_minted: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE amount > 0 AND created_at >= $1",
    )
    .bind(day_start)
    .fetch_one(&state.db)
    .await?;
    let points_spent: i64 = sqlx::query_scalar(
        "SELECT COALESCE(-SUM(amount), 0)::bigint FROM points_ledger
         WHERE amount < 0 AND created_at >= $1",
    )
    .bind(day_start)
    .fetch_one(&state.db)
    .await?;
    let redemptions: Vec<(String, i64)> = sqlx::query_as(
        "SELECT status, count(*) FROM redemptions WHERE created_at >= $1 GROUP BY status",
    )
    .bind(day_start)
    .fetch_all(&state.db)
    .await?;
    let review_pending: i64 =
        sqlx::query_scalar("SELECT count(*) FROM activity_sessions WHERE verdict = 'suspicious'")
            .fetch_one(&state.db)
            .await?;

    Ok(Json(json!({
        "total_users": total_users,
        "new_users_today": new_users,
        "active_users_today": active_users,
        "sessions_today": sessions.into_iter().collect::<std::collections::HashMap<_, _>>(),
        "points_minted_today": points_minted,
        "points_spent_today": points_spent,
        "redemptions_today": redemptions.into_iter().collect::<std::collections::HashMap<_, _>>(),
        "review_pending": review_pending,
    })))
}

#[derive(Serialize, sqlx::FromRow)]
struct ReviewItem {
    id: Uuid,
    user_id: Uuid,
    phone: String,
    activity_type: String,
    distance_m: f64,
    duration_s: f64,
    fraud_score: Option<f64>,
    fraud_flags: Vec<String>,
    created_at: DateTime<Utc>,
}

async fn review_queue(
    _: AdminAuth,
    State(state): State<AppState>,
) -> Result<Json<Vec<ReviewItem>>, AppError> {
    let items: Vec<ReviewItem> = sqlx::query_as(
        "SELECT s.id, s.user_id, u.phone, s.activity_type, s.distance_m, s.duration_s,
                s.fraud_score, s.fraud_flags, s.created_at
         FROM activity_sessions s JOIN users u ON u.id = s.user_id
         WHERE s.verdict = 'suspicious'
         ORDER BY s.created_at LIMIT 50",
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(items))
}

#[derive(Deserialize)]
struct ReviewDecision {
    approve: bool,
}

/// Resolves a quarantined session. Approving mints points through the normal
/// pipeline (idempotent); rejecting buries it — the user earned nothing.
async fn review_session(
    _: AdminAuth,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<ReviewDecision>,
) -> Result<Json<Value>, AppError> {
    let verdict = if body.approve { "clean" } else { "rejected" };
    // Approve accepts an already-clean session too: if a prior approve
    // flipped the verdict but the mint then failed, the admin can retry and
    // the idempotent on_clean_session below settles it (no more 404 trap).
    // Reject stays suspicious-only — a cleared session can't be un-cleared.
    let allowed: &[&str] = if body.approve {
        &["suspicious", "clean"]
    } else {
        &["suspicious"]
    };
    let row: Option<(Uuid, String, f64)> = sqlx::query_as(
        "UPDATE activity_sessions SET verdict = $2, updated_at = now()
         WHERE id = $1 AND verdict = ANY($3) AND status = 'completed'
         RETURNING user_id, activity_type, distance_m",
    )
    .bind(id)
    .bind(verdict)
    .bind(allowed)
    .fetch_optional(&state.db)
    .await?;
    let Some((user_id, activity_type, distance_m)) = row else {
        return Err(AppError::NotFound);
    };

    let (points_earned, challenge_bonus) = if body.approve {
        gamification::on_clean_session(&state, user_id, id, &activity_type, distance_m).await?
    } else {
        (0, 0)
    };

    Ok(Json(json!({
        "verdict": verdict,
        "points_earned": points_earned,
        "challenge_bonus": challenge_bonus,
    })))
}

#[derive(sqlx::FromRow)]
struct LookupUser {
    id: Uuid,
    display_name: Option<String>,
    created_at: DateTime<Utc>,
    points_balance: i64,
    streak_current: i32,
    streak_best: i32,
    guardian_member_id: Option<String>,
}

#[derive(sqlx::FromRow)]
struct LookupSession {
    id: Uuid,
    activity_type: String,
    verdict: String,
    distance_m: f64,
    fraud_score: Option<f64>,
    created_at: DateTime<Utc>,
}

async fn user_lookup(
    _: AdminAuth,
    State(state): State<AppState>,
    Path(phone): Path<String>,
) -> Result<Json<Value>, AppError> {
    let phone = normalize_vn_phone(&phone).map_err(|e| AppError::BadRequest(e.into()))?;

    let user: Option<LookupUser> = sqlx::query_as(
        "SELECT id, display_name, created_at, points_balance, streak_current, streak_best,
                    guardian_member_id
             FROM users WHERE phone = $1",
    )
    .bind(&phone)
    .fetch_optional(&state.db)
    .await?;
    let Some(LookupUser {
        id,
        display_name,
        created_at,
        points_balance: balance,
        streak_current: streak,
        streak_best,
        guardian_member_id: guardian,
    }) = user
    else {
        return Err(AppError::NotFound);
    };

    let devices: Vec<(Uuid, String, Option<DateTime<Utc>>)> =
        sqlx::query_as("SELECT id, platform, attested_at FROM devices WHERE user_id = $1")
            .bind(id)
            .fetch_all(&state.db)
            .await?;
    let sessions: Vec<LookupSession> = sqlx::query_as(
        "SELECT id, activity_type, verdict, distance_m, fraud_score, created_at
         FROM activity_sessions WHERE user_id = $1 ORDER BY created_at DESC LIMIT 10",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(json!({
        "id": id,
        "phone": phone,
        "display_name": display_name,
        "created_at": created_at,
        "points_balance": balance,
        "streak_current": streak,
        "streak_best": streak_best,
        "guardian_linked": guardian.is_some(),
        "devices": devices.iter().map(|(id, platform, attested_at)| json!({
            "id": id, "platform": platform, "attested": attested_at.is_some(),
        })).collect::<Vec<_>>(),
        "recent_sessions": sessions.iter().map(|s| json!({
            "id": s.id, "activity_type": s.activity_type, "verdict": s.verdict,
            "distance_m": s.distance_m, "fraud_score": s.fraud_score,
            "created_at": s.created_at,
        })).collect::<Vec<_>>(),
    })))
}

#[derive(Deserialize)]
struct AdjustPoints {
    amount: i64,
    note: Option<String>,
}

/// Support/ops tool: grant or deduct points (compensation, corrections).
/// Every adjustment is an auditable `admin_adjust` ledger row.
async fn adjust_points(
    _: AdminAuth,
    State(state): State<AppState>,
    Path(phone): Path<String>,
    Json(body): Json<AdjustPoints>,
) -> Result<Json<Value>, AppError> {
    if body.amount == 0 || body.amount.abs() > 100_000 {
        return Err(AppError::BadRequest(
            "amount phải khác 0 và ≤ 100.000".into(),
        ));
    }
    let phone = normalize_vn_phone(&phone).map_err(|e| AppError::BadRequest(e.into()))?;
    let user_id: Uuid = sqlx::query_scalar("SELECT id FROM users WHERE phone = $1")
        .bind(&phone)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;

    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
         VALUES ($1, $2, 'admin_adjust', NULL, $3, $4)",
    )
    .bind(user_id)
    .bind(body.amount)
    .bind(rules::RULES_VERSION)
    .bind(rules::current_season())
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
        .bind(user_id)
        .bind(body.amount)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    tracing::info!(%phone, amount = body.amount, note = body.note.as_deref().unwrap_or(""),
                   "admin points adjustment");
    Ok(Json(json!({ "adjusted": body.amount })))
}

#[derive(Deserialize)]
struct NewChallenge {
    title: String,
    description: Option<String>,
    target: f64,
    reward_points: i64,
    days: Option<i64>,
}

async fn create_challenge(
    _: AdminAuth,
    State(state): State<AppState>,
    Json(body): Json<NewChallenge>,
) -> Result<Json<Value>, AppError> {
    if body.title.is_empty() || body.target <= 0.0 || body.reward_points <= 0 {
        return Err(AppError::BadRequest(
            "title, positive target and reward_points required".into(),
        ));
    }
    let days = body.days.unwrap_or(30).clamp(1, 365);
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO challenges (title, description, target, reward_points, starts_at, ends_at)
         VALUES ($1, $2, $3, $4, now(), now() + make_interval(days => $5::int))
         RETURNING id",
    )
    .bind(&body.title)
    .bind(&body.description)
    .bind(body.target)
    .bind(body.reward_points)
    .bind(days as i32)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "id": id })))
}

#[derive(Deserialize)]
struct NewReward {
    partner: Option<String>,
    title: String,
    description: Option<String>,
    cost_points: i64,
    stock: Option<i32>,
}

async fn create_reward(
    _: AdminAuth,
    State(state): State<AppState>,
    Json(body): Json<NewReward>,
) -> Result<Json<Value>, AppError> {
    if body.title.is_empty() || body.cost_points <= 0 {
        return Err(AppError::BadRequest(
            "title and positive cost_points required".into(),
        ));
    }
    let id: Uuid = sqlx::query_scalar(
        "INSERT INTO rewards (partner, title, description, cost_points, stock)
         VALUES (COALESCE($1, 'guardian'), $2, $3, $4, $5) RETURNING id",
    )
    .bind(&body.partner)
    .bind(&body.title)
    .bind(&body.description)
    .bind(body.cost_points)
    .bind(body.stock)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "id": id })))
}

#[derive(Deserialize)]
struct RewardPatch {
    active: Option<bool>,
    stock: Option<i32>,
    cost_points: Option<i64>,
}

async fn update_reward(
    _: AdminAuth,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(body): Json<RewardPatch>,
) -> Result<Json<Value>, AppError> {
    let updated = sqlx::query(
        "UPDATE rewards SET active = COALESCE($2, active), stock = COALESCE($3, stock),
                            cost_points = COALESCE($4, cost_points)
         WHERE id = $1",
    )
    .bind(id)
    .bind(body.active)
    .bind(body.stock)
    .bind(body.cost_points)
    .execute(&state.db)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    Ok(Json(json!({ "updated": true })))
}

#[derive(Deserialize)]
struct StatsParams {
    days: Option<i32>,
}

#[derive(Serialize, sqlx::FromRow)]
struct DayCount {
    day: NaiveDate,
    count: i64,
}

/// Guardian-facing dashboard data: redemption volume, active users,
/// challenge performance.
async fn partner_stats(
    _: PartnerAuth,
    State(state): State<AppState>,
    Query(params): Query<StatsParams>,
) -> Result<Json<Value>, AppError> {
    let days = params.days.unwrap_or(14).clamp(1, 90);

    let redemptions: Vec<(NaiveDate, String, i64, i64)> = sqlx::query_as(
        "SELECT created_at::date, status, count(*)::bigint, COALESCE(SUM(cost_points),0)::bigint
         FROM redemptions WHERE created_at >= now() - make_interval(days => $1)
         GROUP BY 1, 2 ORDER BY 1 DESC",
    )
    .bind(days)
    .fetch_all(&state.db)
    .await?;
    let active_users: Vec<DayCount> = sqlx::query_as(
        "SELECT created_at::date AS day, count(DISTINCT user_id)::bigint AS count
         FROM activity_sessions WHERE created_at >= now() - make_interval(days => $1)
         GROUP BY 1 ORDER BY 1 DESC",
    )
    .bind(days)
    .fetch_all(&state.db)
    .await?;
    let challenges: Vec<(String, i64, i64)> = sqlx::query_as(
        "SELECT c.title, count(uc.user_id)::bigint AS joined,
                count(uc.completed_at)::bigint AS completed
         FROM challenges c LEFT JOIN user_challenges uc ON uc.challenge_id = c.id
         GROUP BY c.id, c.title ORDER BY joined DESC",
    )
    .fetch_all(&state.db)
    .await?;

    Ok(Json(json!({
        "days": days,
        "redemptions": redemptions.iter().map(|(day, status, count, points)| json!({
            "day": day, "status": status, "count": count, "points": points,
        })).collect::<Vec<_>>(),
        "active_users": active_users,
        "challenges": challenges.iter().map(|(title, joined, completed)| json!({
            "title": title, "joined": joined, "completed": completed,
        })).collect::<Vec<_>>(),
    })))
}
