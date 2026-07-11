//! Partner engagement adapter — the AABW/VETC story: the engine's earning
//! input is source-agnostic. Partners push signed events (toll passes,
//! top-ups, fuel, parking); the SAME ledger, caps and mission machinery
//! that powers GPS runs mints points and settles mobility missions.
//!
//! Design mirrors the fitness side: event points and caps are DB rows
//! (`partner_event_rules`), missions are DB rows (`mobility_missions`),
//! minting is idempotent (event id / uuid5 period source), and the safety
//! guardrail is structural: no rule may reward MORE or FASTER driving —
//! only off-peak shifts, punctual top-ups and partner services.

use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Datelike, Duration, FixedOffset, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    admin::PartnerAuth, ai, auth::jwt::AuthUser, error::AppError, gamification::rules,
    state::AppState,
};

const PARTNER: &str = "vetc";
// VN rush hours 6-9 & 16-19 (hardcoded in the off-peak SQL below).
// Guardrail: rules PAY people to avoid peaks — never to drive more/faster.

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/partner/events", post(ingest))
        .route("/partner/engage/stats", get(engage_stats))
        .route("/partner/ai/insight", post(ai_insight))
        .route("/partner/ai/personalize", post(ai_personalize))
        .route("/partner/ai/winback", post(ai_winback))
        .route("/missions", get(my_missions))
}

// ---------- ingest ----------

#[derive(Debug, Deserialize)]
struct EventIn {
    external_id: String,
    /// Partner's user handle — VETC knows drivers by phone.
    user_ref: String,
    event_type: String,
    amount_vnd: Option<i64>,
    province: Option<String>,
    station: Option<String>,
    occurred_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
struct IngestBody {
    events: Vec<EventIn>,
}

#[derive(Debug, sqlx::FromRow)]
struct EventRule {
    event_type: String,
    points: i64,
    daily_max: i32,
}

/// Resolve a partner user_ref (phone-ish) to a NullShift user.
async fn resolve_user(state: &AppState, user_ref: &str) -> Result<Option<Uuid>, AppError> {
    let normalized = if let Some(rest) = user_ref.strip_prefix('0') {
        format!("+84{rest}")
    } else {
        user_ref.to_string()
    };
    Ok(
        sqlx::query_scalar("SELECT id FROM users WHERE phone = $1 OR phone = $2")
            .bind(user_ref)
            .bind(&normalized)
            .fetch_optional(&state.db)
            .await?,
    )
}

async fn ingest(
    _: PartnerAuth,
    State(state): State<AppState>,
    Json(body): Json<IngestBody>,
) -> Result<Json<Value>, AppError> {
    if body.events.is_empty() || body.events.len() > 500 {
        return Err(AppError::BadRequest("1..=500 events per batch".into()));
    }
    let rules_rows: Vec<EventRule> = sqlx::query_as(
        "SELECT event_type, points, daily_max FROM partner_event_rules WHERE partner = $1",
    )
    .bind(PARTNER)
    .fetch_all(&state.db)
    .await?;

    let mut accepted = 0usize;
    let mut duplicates = 0usize;
    let mut unmatched = 0usize;
    let mut rejected_stale = 0usize;
    let mut points_minted = 0i64;
    let mut missions_completed: Vec<Value> = Vec::new();
    let season = rules::current_season();
    let now = Utc::now();
    // Distinct users touched this batch → settle missions once each at the end.
    let mut touched: std::collections::HashMap<Uuid, String> = std::collections::HashMap::new();

    for event in &body.events {
        let user_id = resolve_user(&state, &event.user_ref).await?;
        let inserted: Option<(Uuid,)> = sqlx::query_as(
            "INSERT INTO partner_events
                 (partner, external_id, user_ref, user_id, event_type, amount_vnd,
                  province, station, occurred_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             ON CONFLICT (partner, external_id) DO NOTHING
             RETURNING id",
        )
        .bind(PARTNER)
        .bind(&event.external_id)
        .bind(&event.user_ref)
        .bind(user_id)
        .bind(&event.event_type)
        .bind(event.amount_vnd)
        .bind(&event.province)
        .bind(&event.station)
        .bind(event.occurred_at)
        .fetch_optional(&state.db)
        .await?;

        let Some((event_id,)) = inserted else {
            duplicates += 1;
            continue;
        };
        accepted += 1;
        // Count as unmatched only once we know this is a *new* event (a
        // duplicate re-send must not inflate the unmatched stat).
        let Some(user_id) = user_id else {
            unmatched += 1;
            continue;
        };

        // Anti-abuse: events are stored for audit but only MINT if their
        // timestamp is sane — no future dates (would seed every later
        // mission period) and nothing older than 48h (a stale backfill or
        // token-replay must not bypass the daily cap by dodging today's
        // window). Legit same-day/yesterday events still reward.
        if event.occurred_at > now + Duration::minutes(15)
            || event.occurred_at < now - Duration::hours(48)
        {
            rejected_stale += 1;
            continue;
        }

        // Per-type daily cap, counted within the event's OWN VN day so
        // backdated events can't dodge the cap window.
        if let Some(rule) = rules_rows.iter().find(|r| r.event_type == event.event_type) {
            let (day_start, day_end) = vn_day_window(event.occurred_at);
            let today_count: i64 = sqlx::query_scalar(
                "SELECT count(*) FROM partner_events
                 WHERE user_id = $1 AND event_type = $2
                   AND occurred_at >= $3 AND occurred_at < $4 AND id != $5",
            )
            .bind(user_id)
            .bind(&event.event_type)
            .bind(day_start)
            .bind(day_end)
            .bind(event_id)
            .fetch_one(&state.db)
            .await?;
            if rule.points > 0 && today_count < rule.daily_max as i64 {
                let mut tx = state.db.begin().await?;
                let minted = sqlx::query(
                    "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
                     VALUES ($1, $2, 'partner_event', $3, $4, $5) ON CONFLICT DO NOTHING",
                )
                .bind(user_id)
                .bind(rule.points)
                .bind(event_id)
                .bind(rules::RULES_VERSION)
                .bind(&season)
                .execute(&mut *tx)
                .await?;
                if minted.rows_affected() > 0 {
                    sqlx::query(
                        "UPDATE users SET points_balance = points_balance + $2 WHERE id = $1",
                    )
                    .bind(user_id)
                    .bind(rule.points)
                    .execute(&mut *tx)
                    .await?;
                    points_minted += rule.points;
                }
                tx.commit().await?;
            }
        }

        // Defer mission settlement to once-per-user after the batch — a
        // 500-event batch from one driver must not run the 6-mission sweep
        // 500 times (that was thousands of serial round-trips per request).
        touched
            .entry(user_id)
            .or_insert_with(|| event.user_ref.clone());
    }

    for (user_id, user_ref) in &touched {
        for done in settle_missions(&state, *user_id).await? {
            missions_completed.push(json!({
                "user_ref": user_ref,
                "key": done.0,
                "title": done.1,
                "reward_points": done.2,
            }));
        }
    }

    Ok(Json(json!({
        "accepted": accepted,
        "duplicates": duplicates,
        "unmatched_users": unmatched,
        "rejected_stale": rejected_stale,
        "points_minted": points_minted,
        "missions_completed": missions_completed,
    })))
}

// ---------- missions ----------

#[derive(Debug, sqlx::FromRow, Clone)]
struct Mission {
    key: String,
    title: String,
    description: String,
    metric: String,
    target: f64,
    reward_points: i64,
    cadence: String,
}

async fn missions(state: &AppState) -> Result<Vec<Mission>, AppError> {
    Ok(sqlx::query_as(
        "SELECT key, title, description, metric, target, reward_points, cadence
         FROM mobility_missions WHERE active ORDER BY sort",
    )
    .fetch_all(&state.db)
    .await?)
}

/// The VN-calendar-day [start, end) in UTC that contains `ts`.
fn vn_day_window(ts: DateTime<Utc>) -> (DateTime<Utc>, DateTime<Utc>) {
    let offset = FixedOffset::east_opt(7 * 3600).expect("valid offset");
    let day = ts.with_timezone(&offset).date_naive();
    let start = day
        .and_hms_opt(0, 0, 0)
        .expect("midnight")
        .and_local_timezone(offset)
        .single()
        .expect("no DST in VN")
        .with_timezone(&Utc);
    (start, start + Duration::days(1))
}

fn vn_month_start_utc() -> DateTime<Utc> {
    let offset = FixedOffset::east_opt(7 * 3600).expect("valid offset");
    let today = rules::vn_today();
    today
        .with_day(1)
        .expect("first day exists")
        .and_hms_opt(0, 0, 0)
        .expect("midnight")
        .and_local_timezone(offset)
        .single()
        .expect("no DST in VN")
        .with_timezone(&Utc)
}

fn period_bounds(cadence: &str) -> (DateTime<Utc>, String) {
    match cadence {
        "weekly" => (rules::vn_week_start_utc(), rules::current_week()),
        "monthly" => {
            let d = rules::vn_today();
            (
                vn_month_start_utc(),
                format!("{}-{:02}", d.year(), d.month()),
            )
        }
        _ => (rules::vn_day_start_utc(), rules::vn_today().to_string()),
    }
}

/// Metric value for a user since `since`, straight from partner_events.
async fn metric_value(
    state: &AppState,
    user_id: Uuid,
    metric: &str,
    since: DateTime<Utc>,
) -> Result<f64, AppError> {
    let value: i64 = match metric {
        "events" => {
            sqlx::query_scalar(
                "SELECT count(*) FROM partner_events WHERE user_id = $1 AND occurred_at >= $2 AND occurred_at <= now()",
            )
            .bind(user_id)
            .bind(since)
            .fetch_one(&state.db)
            .await?
        }
        "toll_passes" | "topups" | "fuel_stops" => {
            let event_type = match metric {
                "toll_passes" => "toll_pass",
                "topups" => "topup",
                _ => "fuel",
            };
            sqlx::query_scalar(
                "SELECT count(*) FROM partner_events
                 WHERE user_id = $1 AND event_type = $2 AND occurred_at >= $3 AND occurred_at <= now()",
            )
            .bind(user_id)
            .bind(event_type)
            .bind(since)
            .fetch_one(&state.db)
            .await?
        }
        "offpeak_trips" => {
            // VN hour outside both rush windows — the traffic-shaping metric.
            sqlx::query_scalar(
                "SELECT count(*) FROM partner_events
                 WHERE user_id = $1 AND event_type = 'toll_pass' AND occurred_at >= $2 AND occurred_at <= now()
                   AND NOT (
                     EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'Asia/Ho_Chi_Minh') IN (6,7,8,16,17,18)
                   )",
            )
            .bind(user_id)
            .bind(since)
            .fetch_one(&state.db)
            .await?
        }
        "provinces" => {
            sqlx::query_scalar(
                "SELECT count(DISTINCT province) FROM partner_events
                 WHERE user_id = $1 AND province IS NOT NULL AND occurred_at >= $2 AND occurred_at <= now()",
            )
            .bind(user_id)
            .bind(since)
            .fetch_one(&state.db)
            .await?
        }
        _ => 0,
    };
    Ok(value as f64)
}

/// Effective target: the AI personalizer may have written an override for
/// this user+mission+period.
async fn effective_target(
    state: &AppState,
    user_id: Uuid,
    mission: &Mission,
    period_key: &str,
) -> Result<f64, AppError> {
    let over: Option<f64> = sqlx::query_scalar(
        "SELECT target FROM user_mission_overrides
         WHERE user_id = $1 AND mission_key = $2 AND period_key = $3",
    )
    .bind(user_id)
    .bind(&mission.key)
    .bind(period_key)
    .fetch_optional(&state.db)
    .await?;
    Ok(over.unwrap_or(mission.target))
}

fn mission_source(user_id: Uuid, key: &str, period_key: &str) -> Uuid {
    Uuid::new_v5(
        &Uuid::NAMESPACE_OID,
        format!("mmission:{key}:{user_id}:{period_key}").as_bytes(),
    )
}

/// Pays every mission whose period metric has crossed the (possibly
/// personalized) target. Returns newly completed (key, title, reward).
async fn settle_missions(
    state: &AppState,
    user_id: Uuid,
) -> Result<Vec<(String, String, i64)>, AppError> {
    let season = rules::current_season();
    let mut completed = Vec::new();
    for mission in missions(state).await? {
        let (since, period_key) = period_bounds(&mission.cadence);
        let value = metric_value(state, user_id, &mission.metric, since).await?;
        let target = effective_target(state, user_id, &mission, &period_key).await?;
        if value < target {
            continue;
        }
        let mut tx = state.db.begin().await?;
        let minted = sqlx::query(
            "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
             VALUES ($1, $2, 'mission_reward', $3, $4, $5) ON CONFLICT DO NOTHING",
        )
        .bind(user_id)
        .bind(mission.reward_points)
        .bind(mission_source(user_id, &mission.key, &period_key))
        .bind(rules::RULES_VERSION)
        .bind(&season)
        .execute(&mut *tx)
        .await?;
        if minted.rows_affected() > 0 {
            sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
                .bind(user_id)
                .bind(mission.reward_points)
                .execute(&mut *tx)
                .await?;
            completed.push((
                mission.key.clone(),
                mission.title.clone(),
                mission.reward_points,
            ));
        }
        tx.commit().await?;
    }
    Ok(completed)
}

/// The signed-in user's mobility mission board.
async fn my_missions(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, AppError> {
    let mut out = Vec::new();
    for mission in missions(&state).await? {
        let (since, period_key) = period_bounds(&mission.cadence);
        let value = metric_value(&state, user.user_id, &mission.metric, since).await?;
        let target = effective_target(&state, user.user_id, &mission, &period_key).await?;
        let paid: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM points_ledger
             WHERE user_id = $1 AND kind = 'mission_reward' AND source_id = $2)",
        )
        .bind(user.user_id)
        .bind(mission_source(user.user_id, &mission.key, &period_key))
        .fetch_one(&state.db)
        .await?;
        out.push(json!({
            "key": mission.key,
            "title": mission.title,
            "description": mission.description,
            "cadence": mission.cadence,
            "target": target,
            "personalized": target != mission.target,
            "progress": value,
            "completed": paid || value >= target,
            "reward_points": mission.reward_points,
        }));
    }
    Ok(Json(json!({ "missions": out })))
}

// ---------- console stats ----------

async fn engage_stats(
    _: PartnerAuth,
    State(state): State<AppState>,
) -> Result<Json<Value>, AppError> {
    let day_start = rules::vn_day_start_utc();

    let (events_today, drivers_today): (i64, i64) = sqlx::query_as(
        "SELECT count(*), count(DISTINCT user_ref) FROM partner_events
         WHERE partner = $1 AND occurred_at >= $2",
    )
    .bind(PARTNER)
    .bind(day_start)
    .fetch_one(&state.db)
    .await?;

    let points_today: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE kind IN ('partner_event', 'mission_reward') AND created_at >= $1",
    )
    .bind(day_start)
    .fetch_one(&state.db)
    .await?;

    let by_hour: Vec<(i32, i64)> = sqlx::query_as(
        "SELECT EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::int AS h, count(*)
         FROM partner_events WHERE partner = $1 AND occurred_at >= $2
         GROUP BY h ORDER BY h",
    )
    .bind(PARTNER)
    .bind(day_start)
    .fetch_all(&state.db)
    .await?;

    let by_type: Vec<(String, i64)> = sqlx::query_as(
        "SELECT event_type, count(*) FROM partner_events
         WHERE partner = $1 AND occurred_at >= $2 GROUP BY event_type ORDER BY count(*) DESC",
    )
    .bind(PARTNER)
    .bind(day_start)
    .fetch_all(&state.db)
    .await?;

    #[derive(sqlx::FromRow, Serialize)]
    struct Recent {
        user_ref: String,
        event_type: String,
        station: Option<String>,
        province: Option<String>,
        occurred_at: DateTime<Utc>,
    }
    let mut recent: Vec<Recent> = sqlx::query_as(
        "SELECT user_ref, event_type, station, province, occurred_at FROM partner_events
         WHERE partner = $1 ORDER BY occurred_at DESC LIMIT 12",
    )
    .bind(PARTNER)
    .fetch_all(&state.db)
    .await?;
    for r in &mut recent {
        let tail: String = r
            .user_ref
            .chars()
            .rev()
            .take(3)
            .collect::<String>()
            .chars()
            .rev()
            .collect();
        r.user_ref = format!("•••{tail}");
    }

    // Per-mission "achieved this period" counts, live from the metric.
    let mut mission_stats = Vec::new();
    for mission in missions(&state).await? {
        let (since, _) = period_bounds(&mission.cadence);
        let achieved: i64 = match mission.metric.as_str() {
            "provinces" => sqlx::query_scalar(
                "SELECT count(*) FROM (
                    SELECT user_id FROM partner_events
                    WHERE user_id IS NOT NULL AND province IS NOT NULL AND occurred_at >= $1
                    GROUP BY user_id HAVING count(DISTINCT province) >= $2
                 ) t",
            )
            .bind(since)
            .bind(mission.target as i64)
            .fetch_one(&state.db)
            .await?,
            "offpeak_trips" => sqlx::query_scalar(
                "SELECT count(*) FROM (
                    SELECT user_id FROM partner_events
                    WHERE user_id IS NOT NULL AND event_type = 'toll_pass' AND occurred_at >= $1
                      AND NOT (EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'Asia/Ho_Chi_Minh') IN (6,7,8,16,17,18))
                    GROUP BY user_id HAVING count(*) >= $2
                 ) t",
            )
            .bind(since)
            .bind(mission.target as i64)
            .fetch_one(&state.db)
            .await?,
            metric => {
                let event_type = match metric {
                    "toll_passes" => Some("toll_pass"),
                    "topups" => Some("topup"),
                    "fuel_stops" => Some("fuel"),
                    _ => None,
                };
                sqlx::query_scalar(
                    "SELECT count(*) FROM (
                        SELECT user_id FROM partner_events
                        WHERE user_id IS NOT NULL AND occurred_at >= $1
                          AND ($2::text IS NULL OR event_type = $2)
                        GROUP BY user_id HAVING count(*) >= $3
                     ) t",
                )
                .bind(since)
                .bind(event_type)
                .bind(mission.target as i64)
                .fetch_one(&state.db)
                .await?
            }
        };
        mission_stats.push(json!({
            "key": mission.key,
            "title": mission.title,
            "description": mission.description,
            "cadence": mission.cadence,
            "target": mission.target,
            "reward_points": mission.reward_points,
            "achieved_count": achieved,
        }));
    }

    Ok(Json(json!({
        "today": {
            "events": events_today,
            "drivers": drivers_today,
            "points_minted": points_today,
        },
        "events_by_hour": by_hour.iter().map(|(h, c)| json!({"hour": h, "count": c})).collect::<Vec<_>>(),
        "by_type": by_type.iter().map(|(t, c)| json!({"event_type": t, "count": c})).collect::<Vec<_>>(),
        "recent": recent,
        "missions": mission_stats,
        "peak_hours": [[6, 9], [16, 19]],
    })))
}

// ---------- AI endpoints ----------

#[derive(Deserialize)]
struct UserRefBody {
    user_ref: String,
}

/// 30-day driver profile — the raw material for every AI feature.
async fn driver_profile(state: &AppState, user_id: Uuid) -> Result<Value, AppError> {
    let since = Utc::now() - Duration::days(30);
    let (trips, provinces, topups): (i64, i64, i64) = sqlx::query_as(
        "SELECT
            count(*) FILTER (WHERE event_type = 'toll_pass'),
            count(DISTINCT province) FILTER (WHERE province IS NOT NULL),
            count(*) FILTER (WHERE event_type = 'topup')
         FROM partner_events WHERE user_id = $1 AND occurred_at >= $2 AND occurred_at <= now()",
    )
    .bind(user_id)
    .bind(since)
    .fetch_one(&state.db)
    .await?;
    let offpeak: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM partner_events
         WHERE user_id = $1 AND event_type = 'toll_pass' AND occurred_at >= $2
           AND NOT (EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'Asia/Ho_Chi_Minh') IN (6,7,8,16,17,18))",
    )
    .bind(user_id)
    .bind(since)
    .fetch_one(&state.db)
    .await?;
    let top_station: Option<String> = sqlx::query_scalar(
        "SELECT station FROM partner_events
         WHERE user_id = $1 AND station IS NOT NULL AND occurred_at >= $2
         GROUP BY station ORDER BY count(*) DESC LIMIT 1",
    )
    .bind(user_id)
    .bind(since)
    .fetch_optional(&state.db)
    .await?;
    let points_30d: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND kind IN ('partner_event', 'mission_reward') AND created_at >= $2",
    )
    .bind(user_id)
    .bind(since)
    .fetch_one(&state.db)
    .await?;
    let last_event: Option<DateTime<Utc>> =
        sqlx::query_scalar("SELECT MAX(occurred_at) FROM partner_events WHERE user_id = $1")
            .bind(user_id)
            .fetch_one(&state.db)
            .await?;
    let days_inactive = last_event
        .map(|t| (Utc::now() - t).num_days().max(0))
        .unwrap_or(999);

    Ok(json!({
        "trips_30d": trips,
        "offpeak_trips_30d": offpeak,
        "offpeak_pct": if trips > 0 { offpeak * 100 / trips } else { 0 },
        "provinces_30d": provinces,
        "topups_30d": topups,
        "top_station": top_station,
        "points_30d": points_30d,
        "days_inactive": days_inactive,
    }))
}

async fn require_user(state: &AppState, user_ref: &str) -> Result<Uuid, AppError> {
    resolve_user(state, user_ref)
        .await?
        .ok_or_else(|| AppError::BadRequest("user_ref chưa có tài khoản".into()))
}

/// Spotify-Wrapped-style insight card, written by the model from REAL
/// numbers (the model never invents stats — it phrases them).
async fn ai_insight(
    _: PartnerAuth,
    State(state): State<AppState>,
    Json(body): Json<UserRefBody>,
) -> Result<Json<Value>, AppError> {
    let user_id = require_user(&state, &body.user_ref).await?;
    let profile = driver_profile(&state, user_id).await?;

    if let Some(config) = ai::AiConfig::from_env() {
        let system = "Bạn là trợ lý của VETC (thu phí không dừng Việt Nam). Viết thẻ insight \
            thân thiện, tích cực bằng tiếng Việt từ số liệu THẬT được cung cấp — tuyệt đối \
            không bịa số. Không khuyến khích lái nhanh hay lái nhiều. \
            Trả về JSON: {\"headline\": \"...(<=60 ký tự)\", \"body\": \"...(<=200 ký tự)\"}";
        let user_msg = format!("Số liệu 30 ngày của tài xế: {profile}");
        match ai::chat(&config, system, &user_msg, true).await {
            Ok(raw) => {
                if let Some(parsed) = ai::parse_json(&raw) {
                    return Ok(Json(json!({
                        "ai": true,
                        "headline": parsed["headline"],
                        "body": parsed["body"],
                        "stats": profile,
                    })));
                }
            }
            Err(e) => tracing::error!(error = %e, "ai insight failed, falling back"),
        }
    }
    // Template fallback — the demo never dies on a missing key.
    Ok(Json(json!({
        "ai": false,
        "headline": format!("{} chuyến ETC trong 30 ngày!", profile["trips_30d"]),
        "body": format!(
            "Bạn đã đi qua {} tỉnh, {}% chuyến ngoài giờ cao điểm và tích {} điểm. Giữ nhịp nhé!",
            profile["provinces_30d"], profile["offpeak_pct"], profile["points_30d"]
        ),
        "stats": profile,
    })))
}

/// AI mission personalizer: the model PICKS from the whitelisted mission
/// templates and calibrates targets; the server clamps and persists. The
/// model never invents missions or rewards — economy stays deterministic.
async fn ai_personalize(
    _: PartnerAuth,
    State(state): State<AppState>,
    Json(body): Json<UserRefBody>,
) -> Result<Json<Value>, AppError> {
    let user_id = require_user(&state, &body.user_ref).await?;
    let profile = driver_profile(&state, user_id).await?;
    let all = missions(&state).await?;

    // (key, target) picks — from the model, or a heuristic fallback.
    let mut picks: Vec<(String, f64)> = Vec::new();
    let mut rationale = String::new();
    let mut used_ai = false;

    if let Some(config) = ai::AiConfig::from_env() {
        let menu: Vec<Value> = all
            .iter()
            .map(|m| {
                json!({"key": m.key, "title": m.title, "metric": m.metric,
                            "base_target": m.target, "cadence": m.cadence})
            })
            .collect();
        let system = "Bạn là hệ thống cá nhân hoá nhiệm vụ của VETC. Chọn tối đa 3 nhiệm vụ \
            từ danh sách cho tài xế này và hiệu chỉnh chỉ tiêu (target) phù hợp mức độ hoạt \
            động — thấp thì dễ hơn để tạo đà, cao thì thách thức hơn. target trong khoảng \
            0.5x đến 2x base_target. KHÔNG khuyến khích lái nhanh/nhiều bất chấp. \
            Trả về JSON: {\"picks\": [{\"key\": \"...\", \"target\": số}], \"rationale\": \"1 câu tiếng Việt\"}";
        let user_msg = format!(
            "Hồ sơ 30 ngày: {profile}\nDanh sách nhiệm vụ: {}",
            json!(menu)
        );
        match ai::chat(&config, system, &user_msg, true).await {
            Ok(raw) => {
                if let Some(parsed) = ai::parse_json(&raw) {
                    if let Some(arr) = parsed["picks"].as_array() {
                        for p in arr.iter().take(3) {
                            if let (Some(key), Some(target)) =
                                (p["key"].as_str(), p["target"].as_f64())
                            {
                                picks.push((key.to_string(), target));
                            }
                        }
                        rationale = parsed["rationale"].as_str().unwrap_or("").to_string();
                        used_ai = !picks.is_empty();
                    }
                }
            }
            Err(e) => tracing::error!(error = %e, "ai personalize failed, falling back"),
        }
    }
    if picks.is_empty() {
        // Heuristic: quiet drivers get easier weekly targets, busy ones harder.
        let busy = profile["trips_30d"].as_i64().unwrap_or(0) >= 12;
        let factor = if busy { 1.5 } else { 0.6 };
        for m in all.iter().filter(|m| m.cadence == "weekly").take(2) {
            picks.push((m.key.clone(), m.target * factor));
        }
        rationale = if busy {
            "Tài xế hoạt động nhiều — nâng chỉ tiêu để giữ độ thách thức.".into()
        } else {
            "Tài xế mới quay lại — hạ chỉ tiêu để tạo đà.".into()
        };
    }

    // Clamp to the whitelist and persist overrides for the current period.
    let mut applied = Vec::new();
    for (key, wanted) in picks {
        let Some(mission) = all.iter().find(|m| m.key == key) else {
            continue;
        };
        let target = wanted
            .clamp(mission.target * 0.5, mission.target * 2.0)
            .round()
            .max(1.0);
        let (_, period_key) = period_bounds(&mission.cadence);
        sqlx::query(
            "INSERT INTO user_mission_overrides (user_id, mission_key, period_key, target)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (user_id, mission_key, period_key) DO UPDATE SET target = $4",
        )
        .bind(user_id)
        .bind(&mission.key)
        .bind(&period_key)
        .bind(target)
        .execute(&state.db)
        .await?;
        applied.push(json!({
            "key": mission.key,
            "title": mission.title,
            "cadence": mission.cadence,
            "base_target": mission.target,
            "personal_target": target,
            "reward_points": mission.reward_points,
        }));
    }

    Ok(Json(json!({
        "ai": used_ai,
        "rationale": rationale,
        "applied": applied,
        "profile": profile,
    })))
}

/// Churn scoring (deterministic heuristic) + AI-written win-back copy.
async fn ai_winback(
    _: PartnerAuth,
    State(state): State<AppState>,
    Json(body): Json<UserRefBody>,
) -> Result<Json<Value>, AppError> {
    let user_id = require_user(&state, &body.user_ref).await?;
    let profile = driver_profile(&state, user_id).await?;
    let days = profile["days_inactive"].as_i64().unwrap_or(999);
    // 0..1 — two silent weeks ≈ churned. Deterministic: scoring is ours,
    // only the WORDS are the model's.
    let risk = (days as f64 / 14.0).clamp(0.0, 1.0);

    let suggested = json!({
        "key": "m_daily_trip",
        "title": "Lăn bánh hôm nay",
        "reward_points": 10,
    });

    if let Some(config) = ai::AiConfig::from_env() {
        let system = "Bạn viết tin nhắn win-back ngắn (<=160 ký tự, tiếng Việt, giọng ấm áp, \
            không gây áp lực) cho tài xế VETC lâu không hoạt động. Nhắc nhẹ phần thưởng đang \
            chờ. Trả về JSON: {\"message\": \"...\"}";
        let user_msg =
            format!("Tài xế im ắng {days} ngày. Hồ sơ: {profile}. Nhiệm vụ gợi ý: {suggested}");
        match ai::chat(&config, system, &user_msg, true).await {
            Ok(raw) => {
                if let Some(parsed) = ai::parse_json(&raw) {
                    return Ok(Json(json!({
                        "ai": true,
                        "risk_score": risk,
                        "days_inactive": days,
                        "message": parsed["message"],
                        "suggested_mission": suggested,
                    })));
                }
            }
            Err(e) => tracing::error!(error = %e, "ai winback failed, falling back"),
        }
    }
    Ok(Json(json!({
        "ai": false,
        "risk_score": risk,
        "days_inactive": days,
        "message": format!(
            "Lâu rồi không thấy bạn trên cao tốc! Nhiệm vụ 'Lăn bánh hôm nay' (+10 điểm) đang chờ — hẹn gặp lại nhé."
        ),
        "suggested_mission": suggested,
    })))
}
