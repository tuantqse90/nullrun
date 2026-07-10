//! Time-windowed daily races ("giải khung giờ"). The arena only counts
//! CLEAN sessions STARTED inside a window's VN-time hours; distance
//! accumulates across sessions within one day's window, and every
//! milestone crossed contributes guild XP (per member, idempotent per
//! user+window+milestone+VN-day). ECONOMY FIREWALL: races pay guild
//! glory only — activity points for the km themselves are minted by the
//! normal session pipeline, nothing extra personal here.

use axum::{extract::State, routing::get, Json, Router};
use chrono::{DateTime, FixedOffset, Utc};
use serde::Serialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{auth::jwt::AuthUser, error::AppError, gamification::rules, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new().route("/", get(list))
}

#[derive(Debug, sqlx::FromRow)]
struct WindowRow {
    code: String,
    title: String,
    icon: String,
    start_hour: i32,
    end_hour: i32,
}

#[derive(Debug, sqlx::FromRow)]
struct MilestoneRow {
    distance_m: f64,
    guild_xp: i64,
}

/// Today's UTC bounds for a window (VN calendar day).
fn bounds_utc(window: &WindowRow) -> (DateTime<Utc>, DateTime<Utc>) {
    let offset = FixedOffset::east_opt(7 * 3600).expect("valid offset");
    let today = rules::vn_today();
    let start = today
        .and_hms_opt(window.start_hour as u32, 0, 0)
        .expect("valid hour")
        .and_local_timezone(offset)
        .single()
        .expect("no DST in VN");
    let end = if window.end_hour == 24 {
        (today + chrono::Duration::days(1))
            .and_hms_opt(0, 0, 0)
            .expect("midnight")
            .and_local_timezone(offset)
            .single()
            .expect("no DST in VN")
    } else {
        today
            .and_hms_opt(window.end_hour as u32, 0, 0)
            .expect("valid hour")
            .and_local_timezone(offset)
            .single()
            .expect("no DST in VN")
    };
    (start.with_timezone(&Utc), end.with_timezone(&Utc))
}

async fn windows(state: &AppState) -> Result<Vec<WindowRow>, AppError> {
    Ok(sqlx::query_as(
        "SELECT code, title, icon, start_hour, end_hour FROM race_windows
         WHERE active ORDER BY sort",
    )
    .fetch_all(&state.db)
    .await?)
}

async fn milestones(state: &AppState) -> Result<Vec<MilestoneRow>, AppError> {
    Ok(
        sqlx::query_as("SELECT distance_m, guild_xp FROM race_milestones ORDER BY sort")
            .fetch_all(&state.db)
            .await?,
    )
}

/// Clean distance the user gathered inside today's window occurrence.
async fn window_distance(
    state: &AppState,
    user_id: Uuid,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> Result<f64, AppError> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(SUM(distance_m), 0)::float8 FROM activity_sessions
         WHERE user_id = $1 AND status = 'completed' AND verdict = 'clean'
           AND started_at >= $2 AND started_at < $3",
    )
    .bind(user_id)
    .bind(start)
    .bind(end)
    .fetch_one(&state.db)
    .await?)
}

// ---------- GET /v1/races ----------

#[derive(Serialize)]
struct MilestoneState {
    distance_m: f64,
    guild_xp: i64,
    reached: bool,
}

#[derive(Serialize)]
struct StandingRow {
    display_name: String,
    distance_m: f64,
    is_me: bool,
}

async fn list(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let defs = milestones(&state).await?;
    let now = Utc::now();
    let mut out = Vec::new();

    for window in windows(&state).await? {
        let (start, end) = bounds_utc(&window);
        let open = now >= start && now < end;
        // Next opening: today's start if still ahead, else tomorrow's.
        let opens_in_s = if now < start {
            (start - now).num_seconds()
        } else {
            (start + chrono::Duration::days(1) - now).num_seconds()
        };

        let mine = window_distance(&state, user.user_id, start, end).await?;
        let milestone_states: Vec<MilestoneState> = defs
            .iter()
            .map(|m| MilestoneState {
                distance_m: m.distance_m,
                guild_xp: m.guild_xp,
                reached: mine >= m.distance_m,
            })
            .collect();

        // Live standings for today's occurrence (clean distance, top 5).
        let top: Vec<(Uuid, Option<String>, String, f64)> = sqlx::query_as(
            "SELECT s.user_id, u.display_name, u.phone, SUM(s.distance_m)::float8 AS d
             FROM activity_sessions s JOIN users u ON u.id = s.user_id
             WHERE s.status = 'completed' AND s.verdict = 'clean'
               AND s.started_at >= $1 AND s.started_at < $2
             GROUP BY s.user_id, u.display_name, u.phone
             ORDER BY d DESC LIMIT 5",
        )
        .bind(start)
        .bind(end)
        .fetch_all(&state.db)
        .await?;
        let standings: Vec<StandingRow> = top
            .into_iter()
            .map(|(uid, name, phone, d)| StandingRow {
                display_name: name.unwrap_or_else(|| {
                    format!("Runner •••{}", &phone[phone.len().saturating_sub(3)..])
                }),
                distance_m: d,
                is_me: uid == user.user_id,
            })
            .collect();

        out.push(json!({
            "code": window.code,
            "title": window.title,
            "icon": window.icon,
            "start_hour": window.start_hour,
            "end_hour": window.end_hour,
            "open": open,
            "opens_in_s": if open { 0 } else { opens_in_s },
            "closes_in_s": if open { (end - now).num_seconds() } else { 0 },
            "my_distance_m": mine,
            "milestones": milestone_states,
            "standings": standings,
        }));
    }

    Ok(Json(json!({ "windows": out })))
}

// ---------- settle hook ----------

/// Called (best-effort) after a clean session: if it started inside a race
/// window and the runner is in a guild, mint guild XP for every milestone
/// the runner's window total has crossed. Idempotent per
/// user+window+milestone+VN-day, so re-finishing never double-pays.
pub async fn on_activity(state: &AppState, user_id: Uuid, session_id: Uuid) {
    let result = async {
        let started_at: Option<DateTime<Utc>> =
            sqlx::query_scalar("SELECT started_at FROM activity_sessions WHERE id = $1")
                .bind(session_id)
                .fetch_optional(&state.db)
                .await?;
        let Some(started_at) = started_at else {
            return Ok::<(), AppError>(());
        };
        let guild: Option<(Uuid,)> =
            sqlx::query_as("SELECT guild_id FROM guild_members WHERE user_id = $1")
                .bind(user_id)
                .fetch_optional(&state.db)
                .await?;
        let Some((guild_id,)) = guild else {
            return Ok(());
        };

        for window in windows(state).await? {
            let (start, end) = bounds_utc(&window);
            if started_at < start || started_at >= end {
                continue;
            }
            let mine = window_distance(state, user_id, start, end).await?;
            let defs = milestones(state).await?;
            let mut minted = 0i64;
            let mut tx = state.db.begin().await?;
            for m in defs.iter().filter(|m| mine >= m.distance_m) {
                let source = Uuid::new_v5(
                    &Uuid::NAMESPACE_OID,
                    format!(
                        "race:{}:{}:{}:{}",
                        window.code,
                        user_id,
                        m.distance_m as i64,
                        rules::vn_today()
                    )
                    .as_bytes(),
                );
                let inserted = sqlx::query(
                    "INSERT INTO guild_xp_ledger (guild_id, amount, kind, source_id)
                     VALUES ($1, $2, 'race', $3) ON CONFLICT DO NOTHING",
                )
                .bind(guild_id)
                .bind(m.guild_xp)
                .bind(source)
                .execute(&mut *tx)
                .await?;
                if inserted.rows_affected() > 0 {
                    minted += m.guild_xp;
                }
            }
            if minted > 0 {
                sqlx::query("UPDATE guilds SET xp = xp + $2 WHERE id = $1")
                    .bind(guild_id)
                    .bind(minted)
                    .execute(&mut *tx)
                    .await?;
            }
            tx.commit().await?;
        }
        Ok(())
    }
    .await;
    if let Err(e) = result {
        tracing::error!(error = %e, %user_id, "race settle failed");
    }
}
