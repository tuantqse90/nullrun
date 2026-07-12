mod activities;
mod admin;
mod ai;
mod auth;
mod config;
mod devices;
mod duels;
mod error;
mod gamification;
mod guilds;
mod mobility;
mod races;
mod rewards;
mod routes;
mod state;
mod users;

use crate::{config::Config, state::AppState};

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=debug".into()),
        )
        .init();

    let config = Config::from_env();
    let state = AppState::init(&config)
        .await
        .expect("failed to connect to Postgres/Redis — is `docker compose up -d` running?");

    sqlx::migrate!("./migrations")
        .run(&state.db)
        .await
        .expect("migrations failed");
    tracing::info!("migrations up to date");

    tokio::spawn(activities::ingest::run_gps_writer(state.clone()));

    let app = routes::router(state);
    let listener = tokio::net::TcpListener::bind(&config.bind_addr)
        .await
        .expect("failed to bind");
    tracing::info!("nullshift-backend listening on {}", config.bind_addr);
    axum::serve(listener, app).await.expect("server error");
}
