use fred::prelude::*;
use sqlx::postgres::{PgPool, PgPoolOptions};

use crate::config::Config as AppConfig;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub redis: Client,
    pub config: AppConfig,
}

impl AppState {
    /// Connects to Postgres and Redis, failing fast if either is unreachable.
    /// Local dev flow: `docker compose up -d` first (see repo root).
    pub async fn init(config: &AppConfig) -> Result<Self, Box<dyn std::error::Error>> {
        let db = PgPoolOptions::new()
            .max_connections(10)
            .connect(&config.database_url)
            .await?;

        let redis_config = Config::from_url(&config.redis_url)?;
        let redis = Builder::from_config(redis_config)
            .set_policy(ReconnectPolicy::new_exponential(0, 100, 30_000, 2))
            .build()?;
        redis.init().await?;

        Ok(Self {
            db,
            redis,
            config: config.clone(),
        })
    }
}
