//! Versioned earning rules. Bump RULES_VERSION whenever the formula changes —
//! every ledger row records the version it was minted under.

use chrono::{DateTime, Datelike, FixedOffset, NaiveDate, Utc};
use uuid::Uuid;

/// Deterministic per-day source id for idempotent daily mints
/// (quest rewards, wheel prizes) — same user + tag + VN day = same UUID.
pub fn daily_source_id(user_id: Uuid, tag: &str) -> Uuid {
    let name = format!("{tag}:{user_id}:{}", vn_today());
    Uuid::new_v5(&Uuid::NAMESPACE_OID, name.as_bytes())
}

pub const RULES_VERSION: &str = "v1";

/// Daily cap on activity-earned points (guardrail #1 / #5: bound the faucet).
/// Challenge rewards are not subject to this cap.
pub const DAILY_ACTIVITY_CAP: i64 = 300;

const MIN_DISTANCE_M: f64 = 500.0;
const WALK_POINTS_PER_KM: f64 = 10.0;
const RUN_POINTS_PER_KM: f64 = 15.0;

/// Points for a completed CLEAN session. Walking pays less per km than
/// running (time cost parity, and walking is easier to fake casually).
pub fn activity_points(activity_type: &str, distance_m: f64) -> i64 {
    if distance_m < MIN_DISTANCE_M {
        return 0;
    }
    let per_km = match activity_type {
        "walk" => WALK_POINTS_PER_KM,
        _ => RUN_POINTS_PER_KM,
    };
    (distance_m / 1000.0 * per_km).floor() as i64
}

/// Tier from season earnings. Returns (tier, points needed for next tier).
pub fn tier(season_earned: i64) -> (&'static str, Option<i64>) {
    const THRESHOLDS: [(&str, i64); 4] = [
        ("bronze", 0),
        ("silver", 1_000),
        ("gold", 5_000),
        ("platinum", 15_000),
    ];
    let mut current = THRESHOLDS[0].0;
    let mut next_at = None;
    for (name, at) in THRESHOLDS {
        if season_earned >= at {
            current = name;
        } else {
            next_at = Some(at);
            break;
        }
    }
    (current, next_at)
}

/// Vietnam is UTC+7 with no DST — a fixed offset is correct.
pub fn vn_now() -> DateTime<FixedOffset> {
    Utc::now().with_timezone(&FixedOffset::east_opt(7 * 3600).expect("valid offset"))
}

pub fn vn_today() -> NaiveDate {
    vn_now().date_naive()
}

/// UTC instant of today's midnight in VN time (for daily-cap queries).
pub fn vn_day_start_utc() -> DateTime<Utc> {
    let today = vn_today();
    let start = today
        .and_hms_opt(0, 0, 0)
        .expect("midnight exists")
        .and_local_timezone(FixedOffset::east_opt(7 * 3600).expect("valid offset"))
        .single()
        .expect("no DST in VN");
    start.with_timezone(&Utc)
}

/// UTC instant of Monday 00:00 VN time this week (weekly goal window).
pub fn vn_week_start_utc() -> DateTime<Utc> {
    let today = vn_today();
    let monday = today - chrono::Duration::days(today.weekday().num_days_from_monday() as i64);
    monday
        .and_hms_opt(0, 0, 0)
        .expect("midnight exists")
        .and_local_timezone(FixedOffset::east_opt(7 * 3600).expect("valid offset"))
        .single()
        .expect("no DST in VN")
        .with_timezone(&Utc)
}

/// Season key, e.g. "2026Q3". Tier progress resets each quarter.
pub fn current_season() -> String {
    let d = vn_now();
    format!("{}Q{}", d.year(), (d.month() - 1) / 3 + 1)
}

/// ISO-week key for leaderboards/leagues, e.g. "2026W28".
pub fn current_week() -> String {
    let w = vn_now().iso_week();
    format!("{}W{:02}", w.year(), w.week())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn points_formula() {
        assert_eq!(activity_points("run", 3_000.0), 45);
        assert_eq!(activity_points("walk", 3_000.0), 30);
        assert_eq!(activity_points("run", 2_971.0), 44); // floors
        assert_eq!(activity_points("run", 499.0), 0); // below minimum
        assert_eq!(activity_points("run", 500.0), 7);
    }

    #[test]
    fn tier_thresholds() {
        assert_eq!(tier(0), ("bronze", Some(1_000)));
        assert_eq!(tier(999), ("bronze", Some(1_000)));
        assert_eq!(tier(1_000), ("silver", Some(5_000)));
        assert_eq!(tier(7_500), ("gold", Some(15_000)));
        assert_eq!(tier(20_000), ("platinum", None));
    }

    #[test]
    fn vn_keys_are_consistent() {
        let season = current_season();
        assert!(season.contains('Q') && season.len() == 6, "{season}");
        let week = current_week();
        assert!(week.contains('W') && week.len() == 7, "{week}");
        assert!(vn_day_start_utc() <= Utc::now());
    }
}
