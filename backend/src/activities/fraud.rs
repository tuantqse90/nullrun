//! Rules-based fraud scoring (M3). Runs at session finish, before any
//! points exist. Deliberately no ML — explainable flags, tunable weights.
//!
//! What this can and cannot do: it judges the *shape* of the submitted data.
//! It cannot prove the data came from a real phone in a real pocket — that is
//! what device attestation (App Attest) is for, which is why an unattested
//! device is itself a heavy flag. ZK (v1.5) proves computation, not sensor
//! truth; this layer stays load-bearing forever.

use serde::Serialize;

use crate::activities::compute::{haversine_m, Point};

/// Full sample row used for fraud evaluation (superset of compute::Point).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Sample {
    pub recorded_at: chrono::DateTime<chrono::Utc>,
    pub lat: f64,
    pub lon: f64,
    pub horizontal_accuracy_m: Option<f64>,
    pub step_cadence: Option<f64>,
}

impl Sample {
    pub fn as_point(&self) -> Point {
        Point {
            recorded_at: self.recorded_at,
            lat: self.lat,
            lon: self.lon,
            horizontal_accuracy_m: self.horizontal_accuracy_m,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct Evaluation {
    pub score: f64,
    pub flags: Vec<&'static str>,
    pub verdict: &'static str,
}

// Weights sum past 1.0 on purpose — several medium flags together should
// reach quarantine even when no single flag is damning.
const W_UNATTESTED: f64 = 0.40;
const W_TELEPORTS: f64 = 0.35;
const W_IMPLAUSIBLE_SPEED: f64 = 0.45;
const W_NO_CADENCE: f64 = 0.40;
const W_UNIFORM_MOTION: f64 = 0.35;
const W_JUNK_ACCURACY: f64 = 0.20;
const W_ABSURD_TOTALS: f64 = 1.0;

const SUSPICIOUS_AT: f64 = 0.30;
const REJECTED_AT: f64 = 0.70;

/// Max plausible sustained (session-average) moving speed, m/s.
fn max_avg_speed(activity_type: &str) -> f64 {
    match activity_type {
        "walk" => 2.5, // brisk walk ~1.8; race-walkers ~3, they can pick "run"
        _ => 6.0,      // 6 m/s sustained = 2:47/km — elite territory
    }
}

pub fn evaluate(
    activity_type: &str,
    device_attested: bool,
    distance_m: f64,
    moving_duration_s: f64,
    samples: &[Sample],
) -> Evaluation {
    let mut flags = Vec::new();
    let mut score = 0.0;
    let mut add = |flag: &'static str, weight: f64, flags: &mut Vec<&'static str>| {
        flags.push(flag);
        score += weight;
    };

    if !device_attested {
        add("unattested_device", W_UNATTESTED, &mut flags);
    }

    // Segment-level signals over raw (unfiltered) consecutive fixes.
    let mut speeds = Vec::new();
    let mut dts = Vec::new();
    let mut teleports = 0usize;
    for pair in samples.windows(2) {
        let (a, b) = (&pair[0], &pair[1]);
        let dt = (b.recorded_at - a.recorded_at).num_milliseconds() as f64 / 1000.0;
        if dt <= 0.0 {
            continue;
        }
        let v = haversine_m(a.lat, a.lon, b.lat, b.lon) / dt;
        if v > 12.0 {
            teleports += 1;
        } else if v > 0.3 {
            speeds.push(v);
            dts.push(dt);
        }
    }
    let n_segments = samples.len().saturating_sub(1).max(1);

    if teleports as f64 / n_segments as f64 > 0.05 {
        add("teleport_ratio", W_TELEPORTS, &mut flags);
    }

    if moving_duration_s > 60.0 && distance_m / moving_duration_s > max_avg_speed(activity_type) {
        add("implausible_avg_speed", W_IMPLAUSIBLE_SPEED, &mut flags);
    }

    // Moving for real distance but the pedometer never saw steps: classic
    // GPS-spoof-without-shaking. Only meaningful when cadence was reported
    // at all (older data / cycling in v1.x will revisit).
    let cadences: Vec<f64> = samples.iter().filter_map(|s| s.step_cadence).collect();
    if distance_m > 400.0 && !cadences.is_empty() {
        let moving_cadence =
            cadences.iter().filter(|c| **c > 20.0).count() as f64 / cadences.len() as f64;
        if moving_cadence < 0.3 {
            add("no_step_cadence_while_moving", W_NO_CADENCE, &mut flags);
        }
    }

    // Real GPS jitters. Near-zero variance in segment speed AND timing over
    // a long session = generated/replayed track.
    if speeds.len() >= 30 {
        let sv = stddev(&speeds) / mean(&speeds).max(0.01); // coefficient of variation
        let st = stddev(&dts);
        if sv < 0.02 && st < 0.05 {
            add("uniform_motion_profile", W_UNIFORM_MOTION, &mut flags);
        }
    }

    let junk = samples
        .iter()
        .filter(|s| s.horizontal_accuracy_m.is_some_and(|a| a > 50.0))
        .count();
    if !samples.is_empty() && junk as f64 / samples.len() as f64 > 0.3 {
        add("junk_accuracy_ratio", W_JUNK_ACCURACY, &mut flags);
    }

    if distance_m > 100_000.0 || moving_duration_s > 12.0 * 3600.0 {
        add("absurd_totals", W_ABSURD_TOTALS, &mut flags);
    }

    let score = score.min(1.0);
    let verdict = if score >= REJECTED_AT {
        "rejected"
    } else if score >= SUSPICIOUS_AT {
        "suspicious"
    } else {
        "clean"
    };

    Evaluation {
        score,
        flags,
        verdict,
    }
}

fn mean(xs: &[f64]) -> f64 {
    if xs.is_empty() {
        return 0.0;
    }
    xs.iter().sum::<f64>() / xs.len() as f64
}

fn stddev(xs: &[f64]) -> f64 {
    if xs.len() < 2 {
        return 0.0;
    }
    let m = mean(xs);
    (xs.iter().map(|x| (x - m).powi(2)).sum::<f64>() / xs.len() as f64).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{TimeZone, Utc};

    const DEG_PER_M: f64 = 1.0 / 111_195.0;

    /// Deterministic pseudo-jitter in [-0.5, 0.5).
    fn jitter(i: usize) -> f64 {
        ((i * 7919 + 104_729) % 1000) as f64 / 1000.0 - 0.5
    }

    /// Realistic-ish run: ~3 m/s with jittered speed, timing, and cadence.
    fn realistic_run(n: usize) -> Vec<Sample> {
        let mut t = 0.0f64;
        let mut lat = 21.0f64;
        (0..n)
            .map(|i| {
                let dt = 5.0 + jitter(i); // 4.5–5.5 s between fixes
                let v = 3.0 + jitter(i * 3) * 1.2; // 2.4–3.6 m/s
                t += dt;
                lat += v * dt * DEG_PER_M;
                Sample {
                    recorded_at: Utc
                        .timestamp_millis_opt(1_700_000_000_000 + (t * 1000.0) as i64)
                        .unwrap(),
                    lat,
                    lon: 105.8,
                    horizontal_accuracy_m: Some(4.0 + jitter(i * 7).abs() * 10.0),
                    step_cadence: Some(160.0 + jitter(i * 11) * 20.0),
                }
            })
            .collect()
    }

    fn totals(samples: &[Sample]) -> (f64, f64) {
        let pts: Vec<_> = samples.iter().map(|s| s.as_point()).collect();
        let stats = crate::activities::compute::session_stats(&pts);
        (stats.distance_m, stats.duration_s)
    }

    #[test]
    fn realistic_attested_run_is_clean() {
        let samples = realistic_run(200);
        let (d, dur) = totals(&samples);
        let eval = evaluate("run", true, d, dur, &samples);
        assert_eq!(eval.verdict, "clean", "{eval:?}");
        assert!(eval.flags.is_empty(), "{eval:?}");
    }

    #[test]
    fn unattested_device_is_quarantined() {
        let samples = realistic_run(200);
        let (d, dur) = totals(&samples);
        let eval = evaluate("run", false, d, dur, &samples);
        assert_eq!(eval.verdict, "suspicious", "{eval:?}");
        assert!(eval.flags.contains(&"unattested_device"));
    }

    #[test]
    fn bot_uniform_track_without_steps_is_rejected() {
        // Perfectly even 5 s / 15 m steps, zero cadence: scripted spoof.
        let samples: Vec<Sample> = (0..200)
            .map(|i| Sample {
                recorded_at: Utc.timestamp_opt(1_700_000_000 + i * 5, 0).unwrap(),
                lat: 21.0 + (i as f64) * 15.0 * DEG_PER_M,
                lon: 105.8,
                horizontal_accuracy_m: Some(5.0),
                step_cadence: Some(0.0),
            })
            .collect();
        let (d, dur) = totals(&samples);
        let eval = evaluate("run", true, d, dur, &samples);
        assert_eq!(eval.verdict, "rejected", "{eval:?}");
        assert!(eval.flags.contains(&"uniform_motion_profile"), "{eval:?}");
        assert!(
            eval.flags.contains(&"no_step_cadence_while_moving"),
            "{eval:?}"
        );
    }

    #[test]
    fn walk_at_run_speed_is_flagged() {
        // "Walk" moving at 4 m/s — moped in traffic.
        let mut samples = realistic_run(200);
        let mut t = 0.0;
        let mut lat = 21.0;
        for (i, s) in samples.iter_mut().enumerate() {
            let dt = 5.0 + jitter(i);
            t += dt;
            lat += (4.0 + jitter(i * 3)) * dt * DEG_PER_M;
            s.lat = lat;
            s.recorded_at = Utc
                .timestamp_millis_opt(1_700_000_000_000 + (t * 1000.0) as i64)
                .unwrap();
        }
        let (d, dur) = totals(&samples);
        let eval = evaluate("walk", true, d, dur, &samples);
        assert!(eval.flags.contains(&"implausible_avg_speed"), "{eval:?}");
        assert_ne!(eval.verdict, "clean");
    }

    #[test]
    fn teleport_heavy_track_is_flagged() {
        // Every 5th fix jumps ~1.2 km: > 5% of segments are teleports.
        let samples: Vec<Sample> = (0..100)
            .map(|i| {
                let jump = if i % 5 == 0 { 0.011 } else { 0.0 };
                Sample {
                    recorded_at: Utc
                        .timestamp_millis_opt(
                            1_700_000_000_000 + (i as f64 * (5.0 + jitter(i)) * 1000.0) as i64,
                        )
                        .unwrap(),
                    lat: 21.0 + (i as f64) * 15.0 * DEG_PER_M + jump,
                    lon: 105.8,
                    horizontal_accuracy_m: Some(5.0),
                    step_cadence: Some(160.0),
                }
            })
            .collect();
        let (d, dur) = totals(&samples);
        let eval = evaluate("run", true, d, dur, &samples);
        assert!(eval.flags.contains(&"teleport_ratio"), "{eval:?}");
    }

    #[test]
    fn absurd_totals_are_rejected_outright() {
        let samples = realistic_run(50);
        let eval = evaluate("run", true, 150_000.0, 3_600.0, &samples);
        assert_eq!(eval.verdict, "rejected");
        assert!(eval.flags.contains(&"absurd_totals"));
    }

    #[test]
    fn short_no_cadence_walk_is_not_flagged() {
        // < 400 m: too little signal to punish missing cadence.
        let samples: Vec<Sample> = realistic_run(20)
            .into_iter()
            .map(|mut s| {
                s.step_cadence = Some(0.0);
                s
            })
            .collect();
        let (d, dur) = totals(&samples);
        let eval = evaluate("walk", true, d, dur, &samples);
        assert!(
            !eval.flags.contains(&"no_step_cadence_while_moving"),
            "{eval:?}"
        );
    }
}
