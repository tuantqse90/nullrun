//! Guilds (Hội) — small crews that share daily/weekly quests.
//!
//! Design principles (s20-s22): discovery only surfaces ACTIVE guilds;
//! member contribution is shown as % of that member's own weekly goal,
//! never absolute km; chat lives on Zalo (we store the link, nothing more).
//!
//! ECONOMY FIREWALL: guild quests mint GUILD XP (glory + guild level) only.
//! Nothing here touches points_ledger or users.points_balance — guild play
//! can never feed personal points or Guardian rewards. Anti-sybil-lite:
//! one guild per user, one create per day, only CLEAN sessions recorded
//! after joining count toward quests.

use axum::{
    extract::{Path, State},
    routing::{get, patch, post},
    Json, Router,
};
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{auth::jwt::AuthUser, error::AppError, gamification::rules, state::AppState};

const MAX_MEMBERS: i64 = 30;
const XP_PER_LEVEL: i64 = 200;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/join", post(join_by_code))
        .route("/{id}/join", post(join_by_id))
        .route("/mine", get(mine))
        .route("/mine/settings", patch(update_settings))
        .route("/leave", post(leave))
        .route("/discover", get(discover))
}

#[derive(Debug, sqlx::FromRow)]
struct Guild {
    id: Uuid,
    name: String,
    emblem: String,
    code: String,
    zalo_link: Option<String>,
    xp: i64,
}

const GUILD_COLS: &str = "id, name, emblem, code, zalo_link, xp";

// ---------- create / join / leave ----------

#[derive(Deserialize)]
struct CreateGuild {
    name: String,
    emblem: Option<String>,
    zalo_link: Option<String>,
}

async fn create(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<CreateGuild>,
) -> Result<Json<Value>, AppError> {
    let name = body.name.trim().to_string();
    if !(3..=30).contains(&name.chars().count()) {
        return Err(AppError::BadRequest(
            "tên hội phải từ 3 đến 30 ký tự".into(),
        ));
    }
    let emblem = body.emblem.unwrap_or_else(|| "🦔".into());
    if emblem.chars().count() > 4 {
        return Err(AppError::BadRequest("biểu tượng hội quá dài".into()));
    }
    let zalo_link = validate_zalo(body.zalo_link)?;

    if in_guild(&state, user.user_id).await?.is_some() {
        return Err(AppError::BadRequest("bạn đang ở trong một hội rồi".into()));
    }
    // Anti-sybil-lite: one guild creation per user per VN day.
    let created_today: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM guilds WHERE created_by = $1 AND created_at >= $2",
    )
    .bind(user.user_id)
    .bind(rules::vn_day_start_utc())
    .fetch_one(&state.db)
    .await?;
    if created_today >= 1 {
        return Err(AppError::TooManyRequests);
    }

    let mut tx = state.db.begin().await?;
    let guild: Guild = sqlx::query_as(&format!(
        "INSERT INTO guilds (name, emblem, code, created_by, zalo_link)
         VALUES ($1, $2, $3, $4, $5) RETURNING {GUILD_COLS}"
    ))
    .bind(&name)
    .bind(&emblem)
    .bind(join_code())
    .bind(user.user_id)
    .bind(&zalo_link)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.is_unique_violation() => {
            AppError::BadRequest("tên hội đã có người dùng".into())
        }
        _ => AppError::from(e),
    })?;
    sqlx::query("INSERT INTO guild_members (guild_id, user_id, role) VALUES ($1, $2, 'leader')")
        .bind(guild.id)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    render(&state, guild, user.user_id).await.map(Json)
}

fn validate_zalo(link: Option<String>) -> Result<Option<String>, AppError> {
    match link.map(|l| l.trim().to_string()).filter(|l| !l.is_empty()) {
        None => Ok(None),
        Some(l) if l.starts_with("https://") && l.chars().count() <= 200 => Ok(Some(l)),
        Some(_) => Err(AppError::BadRequest(
            "link Zalo phải bắt đầu bằng https://".into(),
        )),
    }
}

fn join_code() -> String {
    const CHARS: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::rng();
    (0..6)
        .map(|_| CHARS[rng.random_range(0..CHARS.len())] as char)
        .collect()
}

#[derive(Deserialize)]
struct JoinByCode {
    code: String,
}

async fn join_by_code(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<JoinByCode>,
) -> Result<Json<Value>, AppError> {
    let guild: Option<Guild> =
        sqlx::query_as(&format!("SELECT {GUILD_COLS} FROM guilds WHERE code = $1"))
            .bind(body.code.trim().to_uppercase())
            .fetch_optional(&state.db)
            .await?;
    let guild = guild.ok_or(AppError::BadRequest("mã hội không đúng".into()))?;
    join(&state, guild, user.user_id).await.map(Json)
}

async fn join_by_id(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    let guild: Option<Guild> =
        sqlx::query_as(&format!("SELECT {GUILD_COLS} FROM guilds WHERE id = $1"))
            .bind(id)
            .fetch_optional(&state.db)
            .await?;
    let guild = guild.ok_or(AppError::NotFound)?;
    join(&state, guild, user.user_id).await.map(Json)
}

async fn join(state: &AppState, guild: Guild, user_id: Uuid) -> Result<Value, AppError> {
    if in_guild(state, user_id).await?.is_some() {
        return Err(AppError::BadRequest("bạn đang ở trong một hội rồi".into()));
    }
    // Lock the guild row so the count-then-insert is serialized per guild —
    // concurrent joins can't both read 29 members and push past MAX_MEMBERS.
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT id FROM guilds WHERE id = $1 FOR UPDATE")
        .bind(guild.id)
        .fetch_one(&mut *tx)
        .await?;
    let members: i64 = sqlx::query_scalar("SELECT count(*) FROM guild_members WHERE guild_id = $1")
        .bind(guild.id)
        .fetch_one(&mut *tx)
        .await?;
    if members >= MAX_MEMBERS {
        return Err(AppError::BadRequest("hội đã đủ thành viên".into()));
    }
    let inserted = sqlx::query(
        "INSERT INTO guild_members (guild_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    )
    .bind(guild.id)
    .bind(user_id)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        return Err(AppError::BadRequest("bạn đang ở trong một hội rồi".into()));
    }
    tx.commit().await?;
    render(state, guild, user_id).await
}

async fn leave(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let Some((guild_id, role)) = in_guild(&state, user.user_id).await? else {
        return Err(AppError::BadRequest("bạn chưa ở trong hội nào".into()));
    };

    let mut tx = state.db.begin().await?;
    sqlx::query("DELETE FROM guild_members WHERE guild_id = $1 AND user_id = $2")
        .bind(guild_id)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;

    // Leader hands over to the longest-standing member; empty guilds dissolve.
    let heir: Option<Uuid> = sqlx::query_scalar(
        "SELECT user_id FROM guild_members WHERE guild_id = $1 ORDER BY joined_at LIMIT 1",
    )
    .bind(guild_id)
    .fetch_optional(&mut *tx)
    .await?;
    match heir {
        Some(heir_id) if role == "leader" => {
            sqlx::query(
                "UPDATE guild_members SET role = 'leader' WHERE guild_id = $1 AND user_id = $2",
            )
            .bind(guild_id)
            .bind(heir_id)
            .execute(&mut *tx)
            .await?;
        }
        None => {
            sqlx::query("DELETE FROM guilds WHERE id = $1")
                .bind(guild_id)
                .execute(&mut *tx)
                .await?;
        }
        _ => {}
    }
    tx.commit().await?;
    Ok(Json(json!({ "left": true })))
}

#[derive(Deserialize)]
struct UpdateSettings {
    emblem: Option<String>,
    zalo_link: Option<String>,
}

async fn update_settings(
    user: AuthUser,
    State(state): State<AppState>,
    Json(body): Json<UpdateSettings>,
) -> Result<Json<Value>, AppError> {
    let Some((guild_id, role)) = in_guild(&state, user.user_id).await? else {
        return Err(AppError::BadRequest("bạn chưa ở trong hội nào".into()));
    };
    if role != "leader" {
        return Err(AppError::BadRequest("chỉ hội trưởng chỉnh được".into()));
    }
    if let Some(emblem) = &body.emblem {
        if emblem.chars().count() > 4 || emblem.is_empty() {
            return Err(AppError::BadRequest("biểu tượng hội không hợp lệ".into()));
        }
        sqlx::query("UPDATE guilds SET emblem = $2 WHERE id = $1")
            .bind(guild_id)
            .bind(emblem)
            .execute(&state.db)
            .await?;
    }
    if body.zalo_link.is_some() {
        let link = validate_zalo(body.zalo_link)?;
        sqlx::query("UPDATE guilds SET zalo_link = $2 WHERE id = $1")
            .bind(guild_id)
            .bind(link)
            .execute(&state.db)
            .await?;
    }
    let guild: Guild = sqlx::query_as(&format!("SELECT {GUILD_COLS} FROM guilds WHERE id = $1"))
        .bind(guild_id)
        .fetch_one(&state.db)
        .await?;
    render(&state, guild, user.user_id).await.map(Json)
}

async fn in_guild(state: &AppState, user_id: Uuid) -> Result<Option<(Uuid, String)>, AppError> {
    Ok(
        sqlx::query_as("SELECT guild_id, role FROM guild_members WHERE user_id = $1")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?,
    )
}

// ---------- my guild ----------

async fn mine(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let Some((guild_id, _)) = in_guild(&state, user.user_id).await? else {
        return Ok(Json(json!({ "exists": false })));
    };
    let guild: Guild = sqlx::query_as(&format!("SELECT {GUILD_COLS} FROM guilds WHERE id = $1"))
        .bind(guild_id)
        .fetch_one(&state.db)
        .await?;
    // Lazy settle keeps quests honest even if the finish-time hook missed
    // (e.g. membership changed after the last activity).
    settle(&state, guild_id).await?;
    render(&state, guild, user.user_id).await.map(Json)
}

#[derive(Serialize)]
struct MemberView {
    user_id: Uuid,
    display_name: String,
    role: String,
    is_me: bool,
    active_today: bool,
    /// % of the member's OWN weekly goal (0..1) — never absolute km,
    /// per the design's no-shaming principle.
    contribution_pct: f64,
}

#[derive(Debug, sqlx::FromRow)]
struct MemberRow {
    user_id: Uuid,
    display_name: Option<String>,
    phone: String,
    role: String,
    active_today: bool,
    weekly_km: f64,
    weekly_goal_km: f64,
}

async fn render(state: &AppState, guild: Guild, me: Uuid) -> Result<Value, AppError> {
    // Contribution windows start at max(week/day start, joined_at) so a new
    // member's pre-join runs never count (anti-sybil-lite).
    let rows: Vec<MemberRow> = sqlx::query_as(
        "SELECT gm.user_id, u.display_name, u.phone, gm.role, u.weekly_goal_km,
                COALESCE(t.active_today, false) AS active_today,
                COALESCE(w.weekly_km, 0) AS weekly_km
         FROM guild_members gm
         JOIN users u ON u.id = gm.user_id
         LEFT JOIN LATERAL (
             SELECT true AS active_today FROM activity_sessions s
             WHERE s.user_id = gm.user_id AND s.status = 'completed' AND s.verdict = 'clean'
               AND s.created_at >= GREATEST($2, gm.joined_at) LIMIT 1
         ) t ON true
         LEFT JOIN LATERAL (
             SELECT SUM(s.distance_m)::float8 / 1000.0 AS weekly_km FROM activity_sessions s
             WHERE s.user_id = gm.user_id AND s.status = 'completed' AND s.verdict = 'clean'
               AND s.created_at >= GREATEST($3, gm.joined_at)
         ) w ON true
         WHERE gm.guild_id = $1
         ORDER BY (gm.role = 'leader') DESC, gm.joined_at",
    )
    .bind(guild.id)
    .bind(rules::vn_day_start_utc())
    .bind(rules::vn_week_start_utc())
    .fetch_all(&state.db)
    .await?;

    let member_count = rows.len() as i64;
    let active_today = rows.iter().filter(|r| r.active_today).count();
    let is_leader = rows.iter().any(|r| r.user_id == me && r.role == "leader");
    let members: Vec<MemberView> = rows
        .into_iter()
        .map(|r| MemberView {
            display_name: r.display_name.clone().unwrap_or_else(|| {
                format!("Runner •••{}", &r.phone[r.phone.len().saturating_sub(3)..])
            }),
            contribution_pct: if r.weekly_goal_km > 0.0 {
                (r.weekly_km / r.weekly_goal_km).min(1.0)
            } else {
                0.0
            },
            is_me: r.user_id == me,
            user_id: r.user_id,
            role: r.role,
            active_today: r.active_today,
        })
        .collect();

    let quests = quest_board(state, guild.id, member_count).await?;

    Ok(json!({
        "exists": true,
        "id": guild.id,
        "name": guild.name,
        "emblem": guild.emblem,
        "code": guild.code,
        "zalo_link": guild.zalo_link,
        "xp": guild.xp,
        "level": 1 + guild.xp / XP_PER_LEVEL,
        "xp_in_level": guild.xp % XP_PER_LEVEL,
        "xp_per_level": XP_PER_LEVEL,
        "member_count": member_count,
        "max_members": MAX_MEMBERS,
        "active_today": active_today,
        "is_leader": is_leader,
        "members": members,
        "quests": quests,
    }))
}

// ---------- quests ----------

#[derive(Debug, sqlx::FromRow)]
struct GuildQuestDef {
    key: String,
    title: String,
    description: String,
    cadence: String,
    metric: String,
    target: f64,
    per_member: bool,
    xp_reward: i64,
}

#[derive(Serialize)]
struct GuildQuestStatus {
    key: String,
    title: String,
    description: String,
    cadence: String,
    target: f64,
    progress: f64,
    completed: bool,
    xp_reward: i64,
}

struct WindowStats {
    sessions: i64,
    distance_m: f64,
    active_members: i64,
}

async fn load_defs(state: &AppState) -> Result<Vec<GuildQuestDef>, AppError> {
    Ok(sqlx::query_as(
        "SELECT key, title, description, cadence, metric, target, per_member, xp_reward
         FROM guild_quest_defs WHERE active ORDER BY sort",
    )
    .fetch_all(&state.db)
    .await?)
}

/// Clean-session totals for the guild since `since`, counting only activity
/// recorded after each member joined.
async fn window_stats(
    state: &AppState,
    guild_id: Uuid,
    since: chrono::DateTime<chrono::Utc>,
) -> Result<WindowStats, AppError> {
    let (sessions, distance_m, active_members): (i64, f64, i64) = sqlx::query_as(
        "SELECT count(s.id), COALESCE(SUM(s.distance_m), 0)::float8, count(DISTINCT s.user_id)
         FROM activity_sessions s
         JOIN guild_members gm ON gm.user_id = s.user_id AND gm.guild_id = $1
         WHERE s.status = 'completed' AND s.verdict = 'clean'
           AND s.created_at >= GREATEST($2, gm.joined_at)",
    )
    .bind(guild_id)
    .bind(since)
    .fetch_one(&state.db)
    .await?;
    Ok(WindowStats {
        sessions,
        distance_m,
        active_members,
    })
}

/// Effective target and current progress for one def given guild size.
fn eval(def: &GuildQuestDef, stats: &WindowStats, member_count: i64) -> (f64, f64) {
    let members = member_count.max(1) as f64;
    match def.metric.as_str() {
        "sessions" => (
            if def.per_member {
                def.target * members
            } else {
                def.target
            },
            stats.sessions as f64,
        ),
        "distance_m" => (
            if def.per_member {
                def.target * members
            } else {
                def.target
            },
            stats.distance_m,
        ),
        // target stored as a fraction of members (0..1)
        "members_active" => (
            (def.target * members).ceil().max(1.0),
            stats.active_members as f64,
        ),
        _ => (f64::MAX, 0.0),
    }
}

fn period_source_id(guild_id: Uuid, key: &str, cadence: &str) -> Uuid {
    let period = match cadence {
        "weekly" => rules::current_week(),
        _ => rules::vn_today().to_string(),
    };
    let name = format!("gquest:{key}:{guild_id}:{period}");
    Uuid::new_v5(&Uuid::NAMESPACE_OID, name.as_bytes())
}

/// Mints guild XP for any quest whose window target is met and not yet paid.
/// Idempotent per (guild, quest, VN day/ISO week). Returns newly minted XP.
async fn settle(state: &AppState, guild_id: Uuid) -> Result<i64, AppError> {
    let defs = load_defs(state).await?;
    let member_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM guild_members WHERE guild_id = $1")
            .bind(guild_id)
            .fetch_one(&state.db)
            .await?;
    let daily = window_stats(state, guild_id, rules::vn_day_start_utc()).await?;
    let weekly = window_stats(state, guild_id, rules::vn_week_start_utc()).await?;

    let mut tx = state.db.begin().await?;
    let mut minted = 0i64;
    for def in &defs {
        let stats = if def.cadence == "weekly" {
            &weekly
        } else {
            &daily
        };
        let (target, progress) = eval(def, stats, member_count);
        if progress < target {
            continue;
        }
        let inserted = sqlx::query(
            "INSERT INTO guild_xp_ledger (guild_id, amount, kind, source_id)
             VALUES ($1, $2, 'quest', $3) ON CONFLICT DO NOTHING",
        )
        .bind(guild_id)
        .bind(def.xp_reward)
        .bind(period_source_id(guild_id, &def.key, &def.cadence))
        .execute(&mut *tx)
        .await?;
        if inserted.rows_affected() > 0 {
            minted += def.xp_reward;
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
    Ok(minted)
}

async fn quest_board(
    state: &AppState,
    guild_id: Uuid,
    member_count: i64,
) -> Result<Vec<GuildQuestStatus>, AppError> {
    let defs = load_defs(state).await?;
    let daily = window_stats(state, guild_id, rules::vn_day_start_utc()).await?;
    let weekly = window_stats(state, guild_id, rules::vn_week_start_utc()).await?;

    let mut out = Vec::with_capacity(defs.len());
    for def in defs {
        let stats = if def.cadence == "weekly" {
            &weekly
        } else {
            &daily
        };
        let (target, progress) = eval(&def, stats, member_count);
        let paid: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM guild_xp_ledger WHERE guild_id = $1 AND source_id = $2)",
        )
        .bind(guild_id)
        .bind(period_source_id(guild_id, &def.key, &def.cadence))
        .fetch_one(&state.db)
        .await?;
        out.push(GuildQuestStatus {
            completed: paid || progress >= target,
            progress,
            target,
            key: def.key,
            title: def.title,
            description: def.description,
            cadence: def.cadence,
            xp_reward: def.xp_reward,
        });
    }
    Ok(out)
}

/// Best-effort hook after a clean session: settle the runner's guild quests.
/// Never fails the finish request.
pub async fn on_activity(state: &AppState, user_id: Uuid) {
    let result = async {
        if let Some((guild_id, _)) = in_guild(state, user_id).await? {
            settle(state, guild_id).await?;
        }
        Ok::<(), AppError>(())
    }
    .await;
    if let Err(e) = result {
        tracing::error!(error = %e, %user_id, "guild quest settle failed");
    }
}

// ---------- discovery ----------

/// Active guilds only — a guild with zero clean sessions in the last 7 days
/// is invisible unless it was created in the last 7 days (grace period).
/// The design forbids surfacing dead guilds to newcomers.
async fn discover(_user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    #[derive(sqlx::FromRow, Serialize)]
    struct Row {
        id: Uuid,
        name: String,
        emblem: String,
        xp: i64,
        level: i64,
        member_count: i64,
        active_week: i64,
    }
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "SELECT g.id, g.name, g.emblem, g.xp, 1 + g.xp / {XP_PER_LEVEL} AS level,
                count(gm.user_id) AS member_count,
                COALESCE(a.active_week, 0) AS active_week
         FROM guilds g
         JOIN guild_members gm ON gm.guild_id = g.id
         LEFT JOIN LATERAL (
             SELECT count(DISTINCT s.user_id) AS active_week
             FROM activity_sessions s
             JOIN guild_members m2 ON m2.user_id = s.user_id AND m2.guild_id = g.id
             WHERE s.status = 'completed' AND s.verdict = 'clean'
               AND s.created_at >= now() - interval '7 days'
         ) a ON true
         GROUP BY g.id, a.active_week
         HAVING count(gm.user_id) < {MAX_MEMBERS}
            AND (COALESCE(a.active_week, 0) > 0 OR g.created_at >= now() - interval '7 days')
         ORDER BY COALESCE(a.active_week, 0) DESC, g.xp DESC
         LIMIT 20"
    ))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(json!({ "guilds": rows })))
}
