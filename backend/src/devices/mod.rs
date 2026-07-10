use axum::{extract::State, routing::post, Json, Router};
use base64::Engine;
use chrono::{DateTime, Utc};
use fred::prelude::*;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{
    auth::jwt::AuthUser,
    config::{AttestMode, ATTEST_CHALLENGE_TTL_SECS},
    error::AppError,
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/attest/challenge", post(attest_challenge))
        .route("/register", post(register))
}

/// One-time nonce the device must embed in its App Attest attestation.
async fn attest_challenge(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, AppError> {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    let challenge = base64::engine::general_purpose::STANDARD.encode(bytes);

    let _: () = state
        .redis
        .set(
            format!("attest:challenge:{}", user.user_id),
            &challenge,
            Some(Expiration::EX(ATTEST_CHALLENGE_TTL_SECS)),
            None,
            false,
        )
        .await?;

    Ok(Json(serde_json::json!({ "challenge": challenge })))
}

#[derive(Deserialize, Validate)]
struct RegisterDevice {
    platform: String,
    #[validate(length(max = 100))]
    model: Option<String>,
    #[validate(length(max = 50))]
    os_version: Option<String>,
    /// App Attest key id + attestation object (base64). Optional at register
    /// time, but an unattested device must never be allowed to earn points.
    attest_key_id: Option<String>,
    attestation: Option<String>,
}

#[derive(Serialize, sqlx::FromRow)]
struct Device {
    id: Uuid,
    platform: String,
    model: Option<String>,
    os_version: Option<String>,
    attested_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
}

async fn register(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<RegisterDevice>,
) -> Result<Json<Device>, AppError> {
    body.validate()?;
    if !matches!(body.platform.as_str(), "ios" | "android") {
        return Err(AppError::BadRequest(
            "platform must be ios or android".into(),
        ));
    }

    let attested = match (&body.attest_key_id, &body.attestation) {
        (Some(key_id), Some(attestation)) => {
            verify_attestation(&state, user.user_id, key_id, attestation).await?;
            true
        }
        (None, None) => false,
        _ => {
            return Err(AppError::BadRequest(
                "attest_key_id and attestation must be provided together".into(),
            ))
        }
    };

    let result: Result<Device, sqlx::Error> = sqlx::query_as(
        "INSERT INTO devices (user_id, platform, model, os_version, attest_key_id, attested_at)
         VALUES ($1, $2, $3, $4, $5, CASE WHEN $6 THEN now() END)
         RETURNING id, platform, model, os_version, attested_at, created_at",
    )
    .bind(user.user_id)
    .bind(&body.platform)
    .bind(&body.model)
    .bind(&body.os_version)
    .bind(&body.attest_key_id)
    .bind(attested)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok(device) => Ok(Json(device)),
        // Attest keys are globally unique per install — a key showing up on a
        // second account is exactly the reuse attack the index exists to stop.
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => Err(AppError::BadRequest(
            "attest_key_id already registered".into(),
        )),
        Err(e) => Err(e.into()),
    }
}

/// Verifies an App Attest attestation object against the stored challenge.
///
/// ATTEST_MODE=dev accepts any attestation after consuming the challenge —
/// there is no iOS build yet to produce real ones, and real objects require a
/// physical device. ATTEST_MODE=apple (full CBOR + cert-chain verification
/// against Apple's App Attest root CA) MUST be implemented before production;
/// guardrail #1 depends on it.
async fn verify_attestation(
    state: &AppState,
    user_id: Uuid,
    _key_id: &str,
    _attestation: &str,
) -> Result<(), AppError> {
    let challenge_key = format!("attest:challenge:{user_id}");
    let challenge: Option<String> = state.redis.get(&challenge_key).await?;
    if challenge.is_none() {
        return Err(AppError::BadRequest(
            "no active attest challenge — request one first".into(),
        ));
    }
    let _: i64 = state.redis.del(&challenge_key).await?;

    match state.config.attest_mode {
        AttestMode::Dev => {
            tracing::warn!(%user_id, "attestation accepted without verification (ATTEST_MODE=dev)");
            Ok(())
        }
        AttestMode::Apple => Err(AppError::Internal(
            "ATTEST_MODE=apple not implemented yet".into(),
        )),
    }
}
