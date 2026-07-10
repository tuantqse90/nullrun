use axum::{
    extract::State,
    routing::{get, patch},
    Json, Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{auth::jwt::AuthUser, error::AppError, state::AppState};

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub phone: String,
    pub display_name: Option<String>,
    pub created_at: DateTime<Utc>,
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me", get(get_me))
        .route("/me", patch(patch_me))
}

async fn get_me(user: AuthUser, State(state): State<AppState>) -> Result<Json<User>, AppError> {
    fetch(&state, user.user_id).await.map(Json)
}

#[derive(Deserialize, Validate)]
struct UpdateMe {
    #[validate(length(min = 1, max = 50))]
    display_name: Option<String>,
    #[validate(range(min = 5.0, max = 200.0))]
    weekly_goal_km: Option<f64>,
}

async fn patch_me(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<UpdateMe>,
) -> Result<Json<User>, AppError> {
    body.validate()?;

    let updated: User = sqlx::query_as(
        "UPDATE users SET display_name = COALESCE($2, display_name),
                          weekly_goal_km = COALESCE($3, weekly_goal_km),
                          updated_at = now()
         WHERE id = $1
         RETURNING id, phone, display_name, created_at",
    )
    .bind(user.user_id)
    .bind(&body.display_name)
    .bind(body.weekly_goal_km)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    Ok(Json(updated))
}

async fn fetch(state: &AppState, user_id: Uuid) -> Result<User, AppError> {
    sqlx::query_as("SELECT id, phone, display_name, created_at FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)
}
