//! Daily quests — server-defined, server-verified, minted once per VN day.
//! Every quest is checkable from data we already trust (clean sessions and
//! the ledger); nothing is client-reported.

use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{error::AppError, gamification::rules};

/// Quest definitions live in the quest_defs table; only the progress
/// metric behind each key is code. Keys: session_1 (clean sessions today),
/// points_30 (activity points today), distance_2k (clean meters today).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct QuestDef {
    pub key: String,
    pub title: String,
    pub target: f64,
    pub reward_points: i64,
}

async fn load_defs(conn: &mut sqlx::PgConnection) -> Result<Vec<QuestDef>, AppError> {
    Ok(sqlx::query_as(
        "SELECT key, title, target, reward_points FROM quest_defs WHERE active ORDER BY sort",
    )
    .fetch_all(conn)
    .await?)
}

#[derive(Debug, Serialize)]
pub struct QuestStatus {
    pub key: String,
    pub title: String,
    pub target: f64,
    pub progress: f64,
    pub completed: bool,
    pub reward_points: i64,
}

struct TodayStats {
    sessions: i64,
    activity_points: i64,
    distance_m: f64,
}

async fn today_stats(conn: &mut sqlx::PgConnection, user_id: Uuid) -> Result<TodayStats, AppError> {
    let day_start = rules::vn_day_start_utc();
    let (sessions, distance_m): (i64, f64) = sqlx::query_as(
        "SELECT count(*), COALESCE(SUM(distance_m), 0)::float8 FROM activity_sessions
         WHERE user_id = $1 AND status = 'completed' AND verdict = 'clean' AND created_at >= $2",
    )
    .bind(user_id)
    .bind(day_start)
    .fetch_one(&mut *conn)
    .await?;
    let activity_points: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND kind = 'activity_earn' AND created_at >= $2",
    )
    .bind(user_id)
    .bind(day_start)
    .fetch_one(&mut *conn)
    .await?;
    Ok(TodayStats {
        sessions,
        activity_points,
        distance_m,
    })
}

fn progress_for(def: &QuestDef, stats: &TodayStats) -> f64 {
    match def.key.as_str() {
        "session_1" => stats.sessions as f64,
        "points_30" => stats.activity_points as f64,
        "distance_2k" => stats.distance_m,
        _ => 0.0,
    }
}

/// Mints rewards for quests satisfied today that haven't been paid yet.
/// Runs inside the caller's transaction; idempotent via the daily source id.
/// Returns the total newly minted.
pub async fn settle(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    user_id: Uuid,
) -> Result<i64, AppError> {
    let defs = load_defs(tx).await?;
    let stats = today_stats(tx, user_id).await?;
    let season = rules::current_season();
    let mut minted = 0i64;

    for def in defs {
        if progress_for(&def, &stats) < def.target {
            continue;
        }
        let source = rules::daily_source_id(user_id, &format!("quest:{}", def.key));
        let inserted = sqlx::query(
            "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
             VALUES ($1, $2, 'quest_reward', $3, $4, $5) ON CONFLICT DO NOTHING",
        )
        .bind(user_id)
        .bind(def.reward_points)
        .bind(source)
        .bind(rules::RULES_VERSION)
        .bind(&season)
        .execute(&mut **tx)
        .await?;
        if inserted.rows_affected() > 0 {
            minted += def.reward_points;
        }
    }
    if minted > 0 {
        sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
            .bind(user_id)
            .bind(minted)
            .execute(&mut **tx)
            .await?;
    }
    Ok(minted)
}

/// Today's quest board for the app.
pub async fn board(db: &PgPool, user_id: Uuid) -> Result<Vec<QuestStatus>, AppError> {
    let mut conn = db.acquire().await?;
    let defs = load_defs(&mut conn).await?;
    let stats = today_stats(&mut conn, user_id).await?;
    drop(conn);
    let mut out = Vec::with_capacity(defs.len());
    for def in defs {
        let source = rules::daily_source_id(user_id, &format!("quest:{}", def.key));
        let paid: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM points_ledger
             WHERE user_id = $1 AND kind = 'quest_reward' AND source_id = $2)",
        )
        .bind(user_id)
        .bind(source)
        .fetch_one(db)
        .await?;
        let progress = progress_for(&def, &stats);
        out.push(QuestStatus {
            completed: paid || progress >= def.target,
            progress,
            key: def.key,
            title: def.title,
            target: def.target,
            reward_points: def.reward_points,
        });
    }
    Ok(out)
}
