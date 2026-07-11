pub mod partner;

use axum::{
    extract::{Path, Query, State},
    http::HeaderMap,
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{auth::jwt::AuthUser, error::AppError, gamification::rules, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/rewards", get(catalog))
        .route("/rewards/{id}/redeem", post(redeem))
        .route("/redemptions", get(my_redemptions))
        .route("/guardian/link", post(link_guardian))
        .route("/partner/reconciliation", get(reconciliation))
}

#[derive(Serialize, sqlx::FromRow)]
struct Reward {
    id: Uuid,
    partner: String,
    title: String,
    description: Option<String>,
    cost_points: i64,
    stock: Option<i32>,
}

async fn catalog(
    _user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<Reward>>, AppError> {
    let rewards: Vec<Reward> = sqlx::query_as(
        "SELECT id, partner, title, description, cost_points, stock
         FROM rewards WHERE active ORDER BY cost_points",
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rewards))
}

#[derive(Serialize, sqlx::FromRow)]
struct Redemption {
    id: Uuid,
    reward_id: Uuid,
    title: String,
    partner: String,
    cost_points: i64,
    status: String,
    voucher_code: Option<String>,
    partner_ref: Option<String>,
    created_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
}

const REDEMPTION_COLS: &str = "r.id, r.reward_id, w.title, w.partner, r.cost_points, r.status, \
                               r.voucher_code, r.partner_ref, r.created_at, r.expires_at";

#[derive(Deserialize)]
struct RedeemPayload {
    idempotency_key: String,
}

/// Redeems a reward: reserves points + stock transactionally, then asks the
/// partner adapter for a voucher. Client retries with the same
/// idempotency_key get the same redemption back — never a double spend.
async fn redeem(
    user: AuthUser,
    State(state): State<AppState>,
    Path(reward_id): Path<Uuid>,
    Json(body): Json<RedeemPayload>,
) -> Result<Json<Redemption>, AppError> {
    if !(8..=64).contains(&body.idempotency_key.len()) {
        return Err(AppError::BadRequest(
            "idempotency_key must be 8–64 chars".into(),
        ));
    }

    if let Some(existing) = fetch_by_idem(&state, user.user_id, &body.idempotency_key).await? {
        return Ok(Json(existing));
    }

    // Only GUARDIAN rewards require a linked Hội Cam membership (that link IS
    // the B2B2C story). Tasco/VETC ecosystem rewards redeem straight from the
    // user's activity points. Pre-check read-only so we never decrement stock
    // and then reject.
    let reward_partner: Option<String> =
        sqlx::query_scalar("SELECT partner FROM rewards WHERE id = $1 AND active")
            .bind(reward_id)
            .fetch_optional(&state.db)
            .await?;
    let Some(reward_partner) = reward_partner else {
        return Err(AppError::NotFound);
    };
    if partner::Adapter::requires_guardian_link(&reward_partner) {
        let member_id: Option<String> =
            sqlx::query_scalar("SELECT guardian_member_id FROM users WHERE id = $1")
                .bind(user.user_id)
                .fetch_one(&state.db)
                .await?;
        if member_id.is_none() {
            return Err(AppError::BadRequest(
                "link your Guardian membership before redeeming".into(),
            ));
        }
    }

    let redemption_id = Uuid::new_v4();
    let mut tx = state.db.begin().await?;

    let balance: i64 =
        sqlx::query_scalar("SELECT points_balance FROM users WHERE id = $1 FOR UPDATE")
            .bind(user.user_id)
            .fetch_one(&mut *tx)
            .await?;

    // NULL stock (unlimited) survives the decrement: NULL - 1 = NULL.
    let reward: Option<(String, i64)> = sqlx::query_as(
        "UPDATE rewards SET stock = stock - 1
         WHERE id = $1 AND active AND (stock IS NULL OR stock > 0)
         RETURNING partner, cost_points",
    )
    .bind(reward_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some((partner_code, cost)) = reward else {
        let exists: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM rewards WHERE id = $1 AND active)")
                .bind(reward_id)
                .fetch_one(&mut *tx)
                .await?;
        return Err(if exists {
            AppError::BadRequest("reward is out of stock".into())
        } else {
            AppError::NotFound
        });
    };

    if balance < cost {
        return Err(AppError::BadRequest(format!(
            "insufficient points: have {balance}, need {cost}"
        )));
    }

    let adapter = partner::Adapter::for_code(&partner_code)
        .ok_or_else(|| AppError::Internal(format!("no adapter for partner {partner_code}")))?;

    let inserted = sqlx::query(
        "INSERT INTO redemptions (id, user_id, reward_id, cost_points, idempotency_key)
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING",
    )
    .bind(redemption_id)
    .bind(user.user_id)
    .bind(reward_id)
    .bind(cost)
    .bind(&body.idempotency_key)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        // Lost an idempotency race — the other request owns this key.
        drop(tx);
        let existing = fetch_by_idem(&state, user.user_id, &body.idempotency_key)
            .await?
            .ok_or_else(|| AppError::Internal("idempotency race with no row".into()))?;
        return Ok(Json(existing));
    }

    sqlx::query(
        "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
         VALUES ($1, $2, 'redemption_spend', $3, $4, $5)",
    )
    .bind(user.user_id)
    .bind(-cost)
    .bind(redemption_id)
    .bind(rules::RULES_VERSION)
    .bind(rules::current_season())
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE users SET points_balance = points_balance - $2 WHERE id = $1")
        .bind(user.user_id)
        .bind(cost)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    // Partner call happens OUTSIDE the transaction (it's a network call in
    // real life). Failure refunds the reserved points.
    match adapter.issue_voucher(redemption_id).await {
        Ok(v) => {
            sqlx::query(
                "UPDATE redemptions SET status = 'fulfilled', voucher_code = $2,
                        partner_ref = $3, updated_at = now() WHERE id = $1",
            )
            .bind(redemption_id)
            .bind(&v.voucher_code)
            .bind(&v.partner_ref)
            .execute(&state.db)
            .await?;
        }
        Err(e) => {
            tracing::error!(error = %e, %redemption_id, "voucher issue failed — refunding");
            refund(&state, user.user_id, redemption_id, cost).await?;
        }
    }

    fetch_by_idem(&state, user.user_id, &body.idempotency_key)
        .await?
        .map(Json)
        .ok_or_else(|| AppError::Internal("redemption vanished".into()))
}

async fn refund(
    state: &AppState,
    user_id: Uuid,
    redemption_id: Uuid,
    cost: i64,
) -> Result<(), AppError> {
    let mut tx = state.db.begin().await?;
    sqlx::query("UPDATE redemptions SET status = 'failed', updated_at = now() WHERE id = $1")
        .bind(redemption_id)
        .execute(&mut *tx)
        .await?;
    let refunded = sqlx::query(
        "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
         VALUES ($1, $2, 'redemption_refund', $3, $4, $5) ON CONFLICT DO NOTHING",
    )
    .bind(user_id)
    .bind(cost)
    .bind(redemption_id)
    .bind(rules::RULES_VERSION)
    .bind(rules::current_season())
    .execute(&mut *tx)
    .await?;
    if refunded.rows_affected() > 0 {
        sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
            .bind(user_id)
            .bind(cost)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}

async fn fetch_by_idem(
    state: &AppState,
    user_id: Uuid,
    key: &str,
) -> Result<Option<Redemption>, AppError> {
    Ok(sqlx::query_as(&format!(
        "SELECT {REDEMPTION_COLS} FROM redemptions r JOIN rewards w ON w.id = r.reward_id
         WHERE r.user_id = $1 AND r.idempotency_key = $2"
    ))
    .bind(user_id)
    .bind(key)
    .fetch_optional(&state.db)
    .await?)
}

async fn my_redemptions(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<Redemption>>, AppError> {
    let rows: Vec<Redemption> = sqlx::query_as(&format!(
        "SELECT {REDEMPTION_COLS} FROM redemptions r JOIN rewards w ON w.id = r.reward_id
         WHERE r.user_id = $1 ORDER BY r.created_at DESC LIMIT 100"
    ))
    .bind(user.user_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

#[derive(Deserialize)]
struct LinkPayload {
    member_id: String,
}

async fn link_guardian(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<LinkPayload>,
) -> Result<Json<Value>, AppError> {
    let adapter = partner::Adapter::GuardianMock;
    if !adapter.valid_member_id(&body.member_id) {
        return Err(AppError::BadRequest("invalid Guardian member id".into()));
    }

    let result = sqlx::query(
        "UPDATE users SET guardian_member_id = $2, guardian_linked_at = now()
         WHERE id = $1 AND guardian_member_id IS NULL",
    )
    .bind(user.user_id)
    .bind(&body.member_id)
    .execute(&state.db)
    .await;

    match result {
        Ok(r) if r.rows_affected() == 1 => Ok(Json(json!({
            "linked": true,
            "member_id": body.member_id,
        }))),
        Ok(_) => Err(AppError::BadRequest(
            "account already linked to a Guardian membership".into(),
        )),
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => Err(AppError::BadRequest(
            "this Guardian membership is linked to another account".into(),
        )),
        Err(e) => Err(e.into()),
    }
}

#[derive(Deserialize)]
struct ReconParams {
    days: Option<i32>,
}

#[derive(Serialize, sqlx::FromRow)]
struct ReconRow {
    day: NaiveDate,
    partner: String,
    status: String,
    redemptions: i64,
    points: i64,
}

/// Partner-facing reconciliation report (auditability for the redemption
/// money flow). Static-token gate until the M6 dashboard brings real auth.
async fn reconciliation(
    State(state): State<AppState>,
    Query(params): Query<ReconParams>,
    headers: HeaderMap,
) -> Result<Json<Value>, AppError> {
    let token = headers
        .get("x-partner-token")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();
    if token != state.config.partner_api_token {
        return Err(AppError::Unauthorized);
    }

    let days = params.days.unwrap_or(7).clamp(1, 90);
    // Broken out by partner — the catalog is multi-partner now (Guardian +
    // Tasco/VETC ecosystem), so a single total would misattribute volume.
    let rows: Vec<ReconRow> = sqlx::query_as(
        "SELECT r.created_at::date AS day, w.partner AS partner, r.status,
                count(*)::bigint AS redemptions,
                COALESCE(SUM(r.cost_points), 0)::bigint AS points
         FROM redemptions r JOIN rewards w ON w.id = r.reward_id
         WHERE r.created_at >= now() - make_interval(days => $1)
         GROUP BY 1, 2, 3 ORDER BY 1 DESC, 2, 3",
    )
    .bind(days)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(json!({ "days": days, "rows": rows })))
}
