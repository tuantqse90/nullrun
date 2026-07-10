use chrono::{DateTime, Utc};

/// A GPS sample as stored in gps_points (subset needed for stats).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Point {
    pub recorded_at: DateTime<Utc>,
    pub lat: f64,
    pub lon: f64,
    pub horizontal_accuracy_m: Option<f64>,
}

#[derive(Debug, Default, PartialEq)]
pub struct SessionStats {
    pub distance_m: f64,
    /// Moving time, not wall time.
    pub duration_s: f64,
    pub avg_pace_s_per_km: Option<f64>,
}

/// Segment filters. These are baseline data-quality rules, not the fraud
/// engine — M3 adds sensor-fusion scoring on top.
const MAX_ACCURACY_M: f64 = 50.0; // drop low-quality fixes
const MAX_SPEED_MPS: f64 = 12.0; // > 43 km/h on foot = GPS jump/teleport
const MAX_GAP_S: f64 = 120.0; // longer gap = pause/signal loss, no distance credit
const MIN_MOVING_SPEED_MPS: f64 = 0.3; // below = standing still (GPS drift)
const MIN_DISTANCE_FOR_PACE_M: f64 = 100.0;

/// Computes server-authoritative stats from time-ordered GPS points.
pub fn session_stats(points: &[Point]) -> SessionStats {
    let usable: Vec<&Point> = points
        .iter()
        .filter(|p| p.horizontal_accuracy_m.is_none_or(|a| a <= MAX_ACCURACY_M))
        .collect();

    let mut distance_m = 0.0;
    let mut duration_s = 0.0;

    for pair in usable.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        let dt = (b.recorded_at - a.recorded_at).num_milliseconds() as f64 / 1000.0;
        if dt <= 0.0 || dt > MAX_GAP_S {
            continue;
        }
        let d = haversine_m(a.lat, a.lon, b.lat, b.lon);
        let speed = d / dt;
        if speed > MAX_SPEED_MPS {
            continue;
        }
        if speed >= MIN_MOVING_SPEED_MPS {
            distance_m += d;
            duration_s += dt;
        }
    }

    let avg_pace_s_per_km =
        (distance_m >= MIN_DISTANCE_FOR_PACE_M).then(|| duration_s / (distance_m / 1000.0));

    SessionStats {
        distance_m,
        duration_s,
        avg_pace_s_per_km,
    }
}

/// Instant at which cumulative (filtered) distance first reaches `target_m`,
/// or None if it never does. Same data-quality gates as `session_stats` —
/// used to decide PvP duel winners by who crossed the line first.
pub fn crossing_time(points: &[Point], target_m: f64) -> Option<DateTime<Utc>> {
    let usable: Vec<&Point> = points
        .iter()
        .filter(|p| p.horizontal_accuracy_m.is_none_or(|a| a <= MAX_ACCURACY_M))
        .collect();
    let mut cum = 0.0;
    for pair in usable.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        let dt = (b.recorded_at - a.recorded_at).num_milliseconds() as f64 / 1000.0;
        if dt <= 0.0 || dt > MAX_GAP_S {
            continue;
        }
        let d = haversine_m(a.lat, a.lon, b.lat, b.lon);
        let speed = d / dt;
        if !(MIN_MOVING_SPEED_MPS..=MAX_SPEED_MPS).contains(&speed) {
            continue;
        }
        cum += d;
        if cum >= target_m {
            return Some(b.recorded_at);
        }
    }
    None
}

/// Great-circle distance in meters.
pub fn haversine_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const EARTH_RADIUS_M: f64 = 6_371_000.0;
    let (phi1, phi2) = (lat1.to_radians(), lat2.to_radians());
    let dphi = (lat2 - lat1).to_radians();
    let dlambda = (lon2 - lon1).to_radians();
    let a = (dphi / 2.0).sin().powi(2) + phi1.cos() * phi2.cos() * (dlambda / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * a.sqrt().asin()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn pt(t_secs: i64, lat: f64, lon: f64, accuracy: Option<f64>) -> Point {
        Point {
            recorded_at: Utc.timestamp_opt(1_700_000_000 + t_secs, 0).unwrap(),
            lat,
            lon,
            horizontal_accuracy_m: accuracy,
        }
    }

    // ~0.00009 degrees latitude ≈ 10 m.
    const DEG_PER_10M: f64 = 10.0 / 111_195.0;

    #[test]
    fn straight_run_distance_and_pace() {
        // 3 m/s northward, one fix per 10 s → 30 m (= 3 × DEG_PER_10M) per
        // step, 60 segments = ~1800 m in 600 s.
        let points: Vec<Point> = (0..=60)
            .map(|i| {
                pt(
                    i * 10,
                    21.0 + (i as f64) * 3.0 * DEG_PER_10M,
                    105.8,
                    Some(5.0),
                )
            })
            .collect();
        let stats = session_stats(&points);
        assert!((stats.distance_m - 1800.0).abs() < 20.0, "{stats:?}");
        assert!((stats.duration_s - 600.0).abs() < 1.0, "{stats:?}");
        let pace = stats.avg_pace_s_per_km.unwrap();
        assert!((pace - 333.3).abs() < 5.0, "pace {pace}");
    }

    #[test]
    fn teleport_segment_is_dropped() {
        let points = vec![
            pt(0, 21.0, 105.8, Some(5.0)),
            pt(10, 21.0 + 3.0 * DEG_PER_10M, 105.8, Some(5.0)), // 30 m, ok
            pt(20, 21.1, 105.8, Some(5.0)),                     // ~11 km in 10 s: teleport
            pt(30, 21.1 + 3.0 * DEG_PER_10M, 105.8, Some(5.0)), // 30 m, ok
        ];
        let stats = session_stats(&points);
        assert!((stats.distance_m - 60.0).abs() < 2.0, "{stats:?}");
    }

    #[test]
    fn inaccurate_fixes_are_dropped() {
        let points = vec![
            pt(0, 21.0, 105.8, Some(5.0)),
            pt(10, 21.0 + 3.0 * DEG_PER_10M, 105.8, Some(500.0)), // junk fix
            pt(20, 21.0 + 6.0 * DEG_PER_10M, 105.8, Some(5.0)),
        ];
        let stats = session_stats(&points);
        // Junk point removed: one 20 s / 60 m segment remains.
        assert!((stats.distance_m - 60.0).abs() < 2.0, "{stats:?}");
        assert!((stats.duration_s - 20.0).abs() < 0.1, "{stats:?}");
    }

    #[test]
    fn long_gap_earns_no_distance() {
        let points = vec![
            pt(0, 21.0, 105.8, Some(5.0)),
            pt(600, 21.01, 105.8, Some(5.0)), // 10-minute gap
        ];
        let stats = session_stats(&points);
        assert_eq!(stats.distance_m, 0.0);
    }

    #[test]
    fn standing_still_earns_nothing() {
        let points: Vec<Point> = (0..=30)
            .map(|i| pt(i * 10, 21.0, 105.8, Some(5.0)))
            .collect();
        let stats = session_stats(&points);
        assert_eq!(stats.distance_m, 0.0);
        assert_eq!(stats.duration_s, 0.0);
        assert_eq!(stats.avg_pace_s_per_km, None);
    }

    #[test]
    fn short_distance_has_no_pace() {
        let points = vec![
            pt(0, 21.0, 105.8, Some(5.0)),
            pt(10, 21.0 + 3.0 * DEG_PER_10M, 105.8, Some(5.0)),
        ];
        assert_eq!(session_stats(&points).avg_pace_s_per_km, None);
    }

    #[test]
    fn haversine_known_distance() {
        // 1 degree of latitude ≈ 111.2 km.
        let d = haversine_m(21.0, 105.8, 22.0, 105.8);
        assert!((d - 111_195.0).abs() < 200.0, "{d}");
    }
}
