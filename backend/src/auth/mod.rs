pub mod jwt;
mod otp;
pub mod phone;
mod refresh;

use axum::{extract::State, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{config::SmsMode, error::AppError, state::AppState, users::User};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/otp/request", post(request_otp))
        .route("/otp/verify", post(verify_otp))
        .route("/refresh", post(refresh))
        .route("/logout", post(logout))
}

#[derive(Deserialize)]
struct PhonePayload {
    phone: String,
}

/// Sends (dev: logs) a one-time code to the given VN phone number.
async fn request_otp(
    State(state): State<AppState>,
    Json(body): Json<PhonePayload>,
) -> Result<Json<Value>, AppError> {
    let phone = phone::normalize_vn_phone(&body.phone).map_err(|e| {
        tracing::warn!(raw = %body.phone, reason = e, "OTP phone rejected");
        AppError::BadRequest(e.into())
    })?;

    // Log mode has no SMS provider — a fixed code beats reading server logs
    // when testing on a physical device. Real providers get random codes.
    let code = match state.config.sms_mode {
        SmsMode::Log => "123456".to_string(),
    };
    otp::store_code(&state.redis, &phone, &code).await?;

    match state.config.sms_mode {
        SmsMode::Log => {
            tracing::info!(%phone, %code, "OTP issued (sms_mode=log — dev only)");
            // Echoed only in log mode so the dev loop and smoke tests work
            // without an SMS provider. A real provider removes this field.
            Ok(Json(json!({ "sent": true, "debug_code": code })))
        }
    }
}

#[derive(Deserialize)]
struct VerifyPayload {
    phone: String,
    code: String,
}

#[derive(Serialize)]
struct TokenPair {
    access_token: String,
    refresh_token: String,
    user: User,
}

/// Verifies the OTP; creates the user on first login. Returns a JWT pair.
async fn verify_otp(
    State(state): State<AppState>,
    Json(body): Json<VerifyPayload>,
) -> Result<Json<TokenPair>, AppError> {
    let phone =
        phone::normalize_vn_phone(&body.phone).map_err(|e| AppError::BadRequest(e.into()))?;
    otp::verify_code(&state.redis, &phone, &body.code).await?;

    let user: User = sqlx::query_as(
        "INSERT INTO users (phone) VALUES ($1)
         ON CONFLICT (phone) DO UPDATE SET updated_at = now()
         RETURNING id, phone, display_name, created_at",
    )
    .bind(&phone)
    .fetch_one(&state.db)
    .await?;

    issue_pair(&state, user).await
}

#[derive(Deserialize)]
struct RefreshPayload {
    refresh_token: String,
}

/// Rotates the refresh token and returns a fresh JWT pair.
async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshPayload>,
) -> Result<Json<TokenPair>, AppError> {
    let (user_id, new_refresh) = refresh::rotate(&state.db, &body.refresh_token).await?;
    let user = fetch_user(&state, user_id).await?;
    Ok(Json(TokenPair {
        access_token: jwt::issue_access_token(&state.config.jwt_secret, user.id)?,
        refresh_token: new_refresh,
        user,
    }))
}

/// Revokes the presented refresh token. Idempotent.
async fn logout(
    State(state): State<AppState>,
    Json(body): Json<RefreshPayload>,
) -> Result<Json<Value>, AppError> {
    refresh::revoke(&state.db, &body.refresh_token).await?;
    Ok(Json(json!({ "logged_out": true })))
}

async fn issue_pair(state: &AppState, user: User) -> Result<Json<TokenPair>, AppError> {
    Ok(Json(TokenPair {
        access_token: jwt::issue_access_token(&state.config.jwt_secret, user.id)?,
        refresh_token: refresh::issue(&state.db, user.id).await?,
        user,
    }))
}

async fn fetch_user(state: &AppState, user_id: Uuid) -> Result<User, AppError> {
    sqlx::query_as("SELECT id, phone, display_name, created_at FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::Unauthorized)
}
