pub mod games;
pub mod quests;
pub mod rules;
pub mod wheel;

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, NaiveDate, Utc};
use fred::prelude::*;
use serde::Serialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{ai, auth::jwt::AuthUser, error::AppError, state::AppState};

const LEAGUE_BUCKET_SIZE: i64 = 50;
const WEEKLY_KEY_TTL_SECS: i64 = 21 * 86_400;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/points", get(my_points))
        .route("/me/insight", get(my_insight))
        .route("/leaderboard/weekly", get(weekly_leaderboard))
        .route("/league", get(my_league))
        .route("/challenges", get(list_challenges))
        .route("/challenges/{id}/join", post(join_challenge))
        .route("/quests", get(quest_board))
        .route("/wheel", get(wheel_state))
        .route("/wheel/spin", post(wheel_spin))
        .route("/games", get(games::list))
        .route("/games/{code}/claim", post(games::claim))
}

async fn quest_board(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<quests::QuestStatus>>, AppError> {
    quests::board(&state.db, user.user_id).await.map(Json)
}

async fn wheel_state(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<wheel::WheelState>, AppError> {
    wheel::state(&state.db, user.user_id).await.map(Json)
}

async fn wheel_spin(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<wheel::SpinResult>, AppError> {
    wheel::spin(&state.db, user.user_id).await.map(Json)
}

/// Mints points for a CLEAN session (the only caller passes verdict-checked
/// sessions — fraud never reaches this function), updates streak and
/// challenge progress transactionally, then leaderboards best-effort.
/// Returns (activity_points, challenge_bonus).
pub async fn on_clean_session(
    state: &AppState,
    user_id: Uuid,
    session_id: Uuid,
    activity_type: &str,
    distance_m: f64,
) -> Result<(i64, i64), AppError> {
    let base = rules::activity_points(activity_type, distance_m);
    let season = rules::current_season();

    let mut tx = state.db.begin().await?;

    // Lock the user row: serializes concurrent finishes for streak + balance.
    let streak: Option<(i32, i32, Option<NaiveDate>)> = sqlx::query_as(
        "SELECT streak_current, streak_best, streak_last_date FROM users
         WHERE id = $1 FOR UPDATE",
    )
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some((streak_current, streak_best, streak_last)) = streak else {
        return Err(AppError::NotFound);
    };

    // Daily cap applies to activity earnings only.
    let earned_today: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND kind = 'activity_earn' AND created_at >= $2",
    )
    .bind(user_id)
    .bind(rules::vn_day_start_utc())
    .fetch_one(&mut *tx)
    .await?;
    let activity_points = base.min((rules::DAILY_ACTIVITY_CAP - earned_today).max(0));

    if activity_points > 0 {
        let minted = sqlx::query(
            "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
             VALUES ($1, $2, 'activity_earn', $3, $4, $5)
             ON CONFLICT DO NOTHING",
        )
        .bind(user_id)
        .bind(activity_points)
        .bind(session_id)
        .bind(rules::RULES_VERSION)
        .bind(&season)
        .execute(&mut *tx)
        .await?;
        if minted.rows_affected() == 0 {
            // Already minted for this session — nothing else to do.
            tx.rollback().await?;
            return Ok((0, 0));
        }
        sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
            .bind(user_id)
            .bind(activity_points)
            .execute(&mut *tx)
            .await?;
    }

    // Streak: one credit per VN calendar day; consecutive days extend it.
    // Strict in v1 — no freezes (shop can sell them in v1.x).
    let today = rules::vn_today();
    if distance_m >= 500.0 && streak_last != Some(today) {
        let new_current = if streak_last == Some(today.pred_opt().expect("date has predecessor")) {
            streak_current + 1
        } else {
            1
        };
        sqlx::query(
            "UPDATE users SET streak_current = $2, streak_best = GREATEST(streak_best, $2),
                              streak_last_date = $3 WHERE id = $1",
        )
        .bind(user_id)
        .bind(new_current)
        .bind(today)
        .execute(&mut *tx)
        .await?;
        let _ = streak_best; // best handled by GREATEST above
    }

    // Challenge progress on joined, active, incomplete challenges.
    let mut challenge_bonus = 0i64;
    if distance_m > 0.0 {
        sqlx::query(
            "UPDATE user_challenges uc SET progress = uc.progress + $2
             FROM challenges c
             WHERE uc.challenge_id = c.id AND uc.user_id = $1 AND uc.completed_at IS NULL
               AND c.metric = 'distance_m' AND c.starts_at <= now() AND c.ends_at > now()",
        )
        .bind(user_id)
        .bind(distance_m)
        .execute(&mut *tx)
        .await?;

        let completed: Vec<(Uuid, i64)> = sqlx::query_as(
            "UPDATE user_challenges uc SET completed_at = now()
             FROM challenges c
             WHERE uc.challenge_id = c.id AND uc.user_id = $1
               AND uc.completed_at IS NULL AND uc.progress >= c.target
             RETURNING c.id, c.reward_points",
        )
        .bind(user_id)
        .fetch_all(&mut *tx)
        .await?;

        for (challenge_id, reward) in completed {
            let minted = sqlx::query(
                "INSERT INTO points_ledger (user_id, amount, kind, source_id, rules_version, season)
                 VALUES ($1, $2, 'challenge_reward', $3, $4, $5)
                 ON CONFLICT DO NOTHING",
            )
            .bind(user_id)
            .bind(reward)
            .bind(challenge_id)
            .bind(rules::RULES_VERSION)
            .bind(&season)
            .execute(&mut *tx)
            .await?;
            if minted.rows_affected() > 0 {
                challenge_bonus += reward;
            }
        }
        if challenge_bonus > 0 {
            sqlx::query("UPDATE users SET points_balance = points_balance + $2 WHERE id = $1")
                .bind(user_id)
                .bind(challenge_bonus)
                .execute(&mut *tx)
                .await?;
        }
    }

    // Daily quests settle in the same transaction (their rewards show up in
    // the finish response as bonus points).
    challenge_bonus += quests::settle(&mut tx, user_id).await?;

    tx.commit().await?;

    // Leaderboards are derived state — best-effort, never fail the request.
    if activity_points > 0 {
        if let Err(e) = bump_leaderboards(state, user_id, activity_points).await {
            tracing::error!(error = %e, %user_id, "leaderboard update failed");
        }
    }
    // Guild quests + race windows settle on their own ledger (guild XP
    // only) — best-effort, never fail the finish.
    crate::guilds::on_activity(state, user_id).await;
    crate::races::on_activity(state, user_id, session_id).await;

    Ok((activity_points, challenge_bonus))
}

/// Weekly global leaderboard + league bucket (assigned on first earn of the
/// week, ~LEAGUE_BUCKET_SIZE users per bucket). Activity points only.
async fn bump_leaderboards(state: &AppState, user_id: Uuid, amount: i64) -> Result<(), AppError> {
    let week = rules::current_week();
    let uid = user_id.to_string();

    let lb_key = format!("lb:weekly:{week}");
    let _: f64 = state.redis.zincrby(&lb_key, amount as f64, &uid).await?;
    let _: bool = state
        .redis
        .expire(&lb_key, WEEKLY_KEY_TTL_SECS, None)
        .await?;

    let member_key = format!("league:member:{week}:{uid}");
    let bucket: Option<i64> = state.redis.get(&member_key).await?;
    let bucket = match bucket {
        Some(b) => b,
        None => {
            let n: i64 = state.redis.incr(format!("league:count:{week}")).await?;
            let b = (n - 1) / LEAGUE_BUCKET_SIZE;
            let _: () = state
                .redis
                .set(
                    &member_key,
                    b,
                    Some(Expiration::EX(WEEKLY_KEY_TTL_SECS)),
                    None,
                    false,
                )
                .await?;
            b
        }
    };
    let bucket_key = format!("league:lb:{week}:{bucket}");
    let _: f64 = state
        .redis
        .zincrby(&bucket_key, amount as f64, &uid)
        .await?;
    let _: bool = state
        .redis
        .expire(&bucket_key, WEEKLY_KEY_TTL_SECS, None)
        .await?;
    Ok(())
}

// ---------- endpoints ----------

#[derive(sqlx::FromRow)]
struct MeRow {
    points_balance: i64,
    streak_current: i32,
    streak_best: i32,
    weekly_goal_km: f64,
    display_name: Option<String>,
}

async fn my_points(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let me: MeRow = sqlx::query_as(
        "SELECT points_balance, streak_current, streak_best, weekly_goal_km, display_name
         FROM users WHERE id = $1",
    )
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    // XP = lifetime positive points; weekly km counts clean sessions only.
    let lifetime_earned: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND amount > 0",
    )
    .bind(user.user_id)
    .fetch_one(&state.db)
    .await?;
    let weekly_km: f64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(distance_m), 0)::float8 / 1000.0 FROM activity_sessions
         WHERE user_id = $1 AND status = 'completed' AND verdict = 'clean' AND started_at >= $2",
    )
    .bind(user.user_id)
    .bind(rules::vn_week_start_utc())
    .fetch_one(&state.db)
    .await?;

    let season = rules::current_season();
    let season_earned: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND season = $2 AND amount > 0",
    )
    .bind(user.user_id)
    .bind(&season)
    .fetch_one(&state.db)
    .await?;
    let today_earned: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND amount > 0 AND created_at >= $2",
    )
    .bind(user.user_id)
    .bind(rules::vn_day_start_utc())
    .fetch_one(&state.db)
    .await?;

    let (tier, next_tier_at) = rules::tier(season_earned);
    Ok(Json(json!({
        "balance": me.points_balance,
        "season": season,
        "season_earned": season_earned,
        "today_earned": today_earned,
        "lifetime_earned": lifetime_earned,
        "tier": tier,
        "next_tier_at": next_tier_at,
        "streak_current": me.streak_current,
        "streak_best": me.streak_best,
        "daily_cap": rules::DAILY_ACTIVITY_CAP,
        "weekly_goal_km": me.weekly_goal_km,
        "weekly_km": weekly_km,
        "display_name": me.display_name,
        "level": 2 + lifetime_earned / 120,
        "xp_in_level": lifetime_earned % 120,
        "xp_per_level": 120,
    })))
}

/// AI coach — a short, personalized nudge phrased from the user's REAL
/// activity numbers. Same locked architecture as the VETC AI: the model only
/// PHRASES the provided stats (never invents a figure) and the endpoint falls
/// back to a deterministic template when no key is set — the demo never dies
/// on a missing credential. Guardrail #4: the coach talks about ACTIVITY and
/// CONSISTENCY only — never body/weight, never "less = better". It mints
/// nothing (economy firewall): this is copy, not currency.
async fn my_insight(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let me: MeRow = sqlx::query_as(
        "SELECT points_balance, streak_current, streak_best, weekly_goal_km, display_name
         FROM users WHERE id = $1",
    )
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let weekly_km: f64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(distance_m), 0)::float8 / 1000.0 FROM activity_sessions
         WHERE user_id = $1 AND status = 'completed' AND verdict = 'clean' AND started_at >= $2",
    )
    .bind(user.user_id)
    .bind(rules::vn_week_start_utc())
    .fetch_one(&state.db)
    .await?;
    let season = rules::current_season();
    let season_earned: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND season = $2 AND amount > 0",
    )
    .bind(user.user_id)
    .bind(&season)
    .fetch_one(&state.db)
    .await?;
    let today_earned: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(amount), 0)::bigint FROM points_ledger
         WHERE user_id = $1 AND amount > 0 AND created_at >= $2",
    )
    .bind(user.user_id)
    .bind(rules::vn_day_start_utc())
    .fetch_one(&state.db)
    .await?;
    let (tier, _next) = rules::tier(season_earned);

    let name = me.display_name.clone().unwrap_or_default();
    let goal = me.weekly_goal_km.max(1.0);
    let remaining = (goal - weekly_km).max(0.0);
    let pct = ((weekly_km / goal) * 100.0).round() as i64;

    // Compact, factual stat block for the model to phrase (never invent).
    let stats = json!({
        "ten": name,
        "km_tuan": (weekly_km * 10.0).round() / 10.0,
        "muc_tieu_km_tuan": (goal * 10.0).round() / 10.0,
        "phan_tram_muc_tieu": pct,
        "chuoi_ngay": me.streak_current,
        "diem_hom_nay": today_earned,
        "hang": tier,
    });

    if let Some(config) = ai::AiConfig::from_env() {
        let system = "Bạn là huấn luyện viên chạy bộ thân thiện trong app Null Run. Viết một lời \
            động viên NGẮN bằng tiếng Việt, CHỈ dựa trên số liệu THẬT được cung cấp — tuyệt đối \
            không bịa thêm bất kỳ con số nào. Chỉ nói về VẬN ĐỘNG, sự đều đặn, chuỗi ngày và mục \
            tiêu tuần. TUYỆT ĐỐI không nhắc tới cân nặng/giảm cân/hình thể, không hàm ý 'ít hơn là \
            tốt hơn'. Giọng ấm áp, khích lệ, có thể dùng 1 emoji. \
            Trả về JSON: {\"headline\": \"...(<=48 ký tự)\", \"body\": \"...(<=140 ký tự)\"}";
        let user_msg = format!("Số liệu tuần này của người dùng: {stats}");
        match ai::chat(&config, system, &user_msg, true).await {
            Ok(raw) => {
                if let Some(parsed) = ai::parse_json(&raw) {
                    if parsed["headline"].is_string() && parsed["body"].is_string() {
                        return Ok(Json(json!({
                            "ai": true,
                            "headline": parsed["headline"],
                            "body": parsed["body"],
                            "stats": stats,
                        })));
                    }
                }
            }
            Err(e) => tracing::error!(error = %e, "me insight ai failed, falling back"),
        }
    }

    // Deterministic template — the demo never dies on a missing key.
    let (headline, body) =
        insight_template(&name, weekly_km, goal, remaining, pct, me.streak_current);
    Ok(Json(json!({
        "ai": false,
        "headline": headline,
        "body": body,
        "stats": stats,
    })))
}

/// Encouraging VN coach copy from real numbers — activity/consistency only,
/// never body/weight (guardrail #4).
fn insight_template(
    name: &str,
    weekly_km: f64,
    goal: f64,
    remaining: f64,
    pct: i64,
    streak: i32,
) -> (String, String) {
    let hi = if name.is_empty() {
        "Chào bạn".to_string()
    } else {
        format!("Chào {name}")
    };
    let streak_tail = if streak >= 2 {
        format!(" Chuỗi {streak} ngày đang cháy 🔥 giữ nhịp nhé!")
    } else {
        String::new()
    };
    if weekly_km <= 0.01 {
        (
            "Bắt đầu tuần mới thôi! 🌱".into(),
            format!(
                "{hi}! Tuần này mục tiêu {goal:.0} km. Một buổi đi bộ nhẹ là khởi động đẹp rồi.{streak_tail}"
            ),
        )
    } else if remaining <= 0.01 {
        (
            "Đạt mục tiêu tuần! 🎉".into(),
            format!(
                "{hi}! Bạn đã hoàn thành {weekly_km:.1} km tuần này — chạm mốc rồi. Quá tuyệt!{streak_tail}"
            ),
        )
    } else {
        (
            format!("Đã {pct}% mục tiêu tuần"),
            format!(
                "{hi}! Bạn đi được {weekly_km:.1}/{goal:.0} km, còn {remaining:.1} km nữa là chạm mốc.{streak_tail}"
            ),
        )
    }
}

#[derive(Serialize)]
struct LeaderboardRow {
    rank: i64,
    display_name: String,
    points: i64,
    is_me: bool,
}

async fn weekly_leaderboard(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, AppError> {
    let week = rules::current_week();
    let key = format!("lb:weekly:{week}");
    let top: Vec<(String, f64)> = state.redis.zrevrange(&key, 0, 19, true).await?;
    let rows = named_rows(&state, &top, user.user_id).await?;

    let uid = user.user_id.to_string();
    let my_rank: Option<i64> = state.redis.zrevrank(&key, &uid, false).await?;
    let my_points: Option<f64> = state.redis.zscore(&key, &uid).await?;

    Ok(Json(json!({
        "week": week,
        "top": rows,
        "me": {
            "rank": my_rank.map(|r| r + 1),
            "points": my_points.unwrap_or(0.0) as i64,
        },
    })))
}

async fn my_league(user: AuthUser, State(state): State<AppState>) -> Result<Json<Value>, AppError> {
    let week = rules::current_week();
    let uid = user.user_id.to_string();
    let bucket: Option<i64> = state
        .redis
        .get(format!("league:member:{week}:{uid}"))
        .await?;
    let Some(bucket) = bucket else {
        return Ok(Json(json!({ "week": week, "joined": false })));
    };

    let key = format!("league:lb:{week}:{bucket}");
    let standings: Vec<(String, f64)> = state.redis.zrevrange(&key, 0, -1, true).await?;
    let rows = named_rows(&state, &standings, user.user_id).await?;

    Ok(Json(json!({
        "week": week,
        "joined": true,
        "bucket": bucket,
        "standings": rows,
    })))
}

/// Resolves user ids to display names (masked phone as fallback).
async fn named_rows(
    state: &AppState,
    scored: &[(String, f64)],
    me: Uuid,
) -> Result<Vec<LeaderboardRow>, AppError> {
    let ids: Vec<Uuid> = scored
        .iter()
        .filter_map(|(id, _)| id.parse().ok())
        .collect();
    let names: Vec<(Uuid, Option<String>, String)> =
        sqlx::query_as("SELECT id, display_name, phone FROM users WHERE id = ANY($1)")
            .bind(&ids)
            .fetch_all(&state.db)
            .await?;

    Ok(scored
        .iter()
        .enumerate()
        .filter_map(|(i, (id, points))| {
            let uid: Uuid = id.parse().ok()?;
            let (_, display_name, phone) = names.iter().find(|(nid, _, _)| *nid == uid)?;
            let name = display_name.clone().unwrap_or_else(|| {
                format!("Runner •••{}", &phone[phone.len().saturating_sub(3)..])
            });
            Some(LeaderboardRow {
                rank: i as i64 + 1,
                display_name: name,
                points: *points as i64,
                is_me: uid == me,
            })
        })
        .collect())
}

#[derive(Serialize, sqlx::FromRow)]
struct ChallengeRow {
    id: Uuid,
    title: String,
    description: Option<String>,
    target: f64,
    reward_points: i64,
    starts_at: DateTime<Utc>,
    ends_at: DateTime<Utc>,
    joined: bool,
    progress: Option<f64>,
    completed_at: Option<DateTime<Utc>>,
}

async fn list_challenges(
    user: AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Vec<ChallengeRow>>, AppError> {
    let rows: Vec<ChallengeRow> = sqlx::query_as(
        "SELECT c.id, c.title, c.description, c.target, c.reward_points, c.starts_at, c.ends_at,
                (uc.user_id IS NOT NULL) AS joined, uc.progress, uc.completed_at
         FROM challenges c
         LEFT JOIN user_challenges uc ON uc.challenge_id = c.id AND uc.user_id = $1
         WHERE c.ends_at > now()
         ORDER BY c.starts_at, c.target",
    )
    .bind(user.user_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

async fn join_challenge(
    user: AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    let active: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM challenges WHERE id = $1 AND starts_at <= now() AND ends_at > now())",
    )
    .bind(id)
    .fetch_one(&state.db)
    .await?;
    if !active {
        return Err(AppError::NotFound);
    }

    sqlx::query(
        "INSERT INTO user_challenges (user_id, challenge_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING",
    )
    .bind(user.user_id)
    .bind(id)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "joined": true })))
}
