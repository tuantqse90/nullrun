use base64::Engine;
use chrono::{Duration, Utc};
use rand::RngCore;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{config::REFRESH_TOKEN_TTL_DAYS, error::AppError};

fn hash_token(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Issues a new opaque refresh token for the user and stores only its hash.
pub async fn issue(db: &PgPool, user_id: Uuid) -> Result<String, AppError> {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    let token = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes);

    sqlx::query("INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)")
        .bind(user_id)
        .bind(hash_token(&token))
        .bind(Utc::now() + Duration::days(REFRESH_TOKEN_TTL_DAYS))
        .execute(db)
        .await?;

    Ok(token)
}

/// Rotates a refresh token: revokes the presented one and issues a replacement.
/// Returns the owning user id and the new token.
pub async fn rotate(db: &PgPool, token: &str) -> Result<(Uuid, String), AppError> {
    let user_id = revoke(db, token).await?.ok_or(AppError::Unauthorized)?;
    let new_token = issue(db, user_id).await?;
    Ok((user_id, new_token))
}

/// Revokes the token if it is live. Returns the owning user id, or None if the
/// token is unknown, expired, or already revoked.
pub async fn revoke(db: &PgPool, token: &str) -> Result<Option<Uuid>, AppError> {
    let row: Option<(Uuid,)> = sqlx::query_as(
        "UPDATE refresh_tokens SET revoked_at = now()
         WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
         RETURNING user_id",
    )
    .bind(hash_token(token))
    .fetch_optional(db)
    .await?;
    Ok(row.map(|(user_id,)| user_id))
}
