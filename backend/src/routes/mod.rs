use axum::{extract::State, routing::get, Json, Router};
use fred::interfaces::ClientLike;
use serde_json::{json, Value};
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::{
    activities, admin, auth, devices, duels, error::AppError, gamification, guilds, mobility,
    races, rewards, state::AppState, users,
};

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .nest("/v1/auth", auth::router())
        .nest(
            "/v1",
            users::router()
                .merge(gamification::router())
                .merge(rewards::router())
                .merge(admin::router())
                .merge(mobility::router()),
        )
        .nest("/v1/devices", devices::router())
        .nest("/v1/activities", activities::router())
        .nest("/v1/duels", duels::router())
        .nest("/v1/guilds", guilds::router())
        .nest("/v1/races", races::router())
        .fallback(async || AppError::NotFound)
        // Permissive CORS for the local dashboard; tighten to the real
        // dashboard origin at deploy time (M7).
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> Json<Value> {
    let db = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.db)
        .await
        .is_ok();
    let redis = state.redis.ping::<String>(None).await.is_ok();

    Json(json!({
        "status": if db && redis { "ok" } else { "degraded" },
        "service": "nullshift-backend",
        "db": db,
        "redis": redis,
    }))
}
