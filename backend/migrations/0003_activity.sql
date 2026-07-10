-- M2: activity engine — sessions + GPS time-series.

CREATE TABLE activity_sessions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id     UUID REFERENCES devices(id) ON DELETE SET NULL,
    activity_type TEXT NOT NULL CHECK (activity_type IN ('walk', 'run')),
    status        TEXT NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'paused', 'completed', 'discarded')),
    started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at      TIMESTAMPTZ,
    -- Server-authoritative stats, computed at finish from gps_points.
    -- duration_s = moving time (gap/teleport-filtered), not wall time.
    distance_m        DOUBLE PRECISION NOT NULL DEFAULT 0,
    duration_s        DOUBLE PRECISION NOT NULL DEFAULT 0,
    avg_pace_s_per_km DOUBLE PRECISION,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX activity_sessions_user_idx ON activity_sessions (user_id, started_at DESC);
-- One open (active/paused) session per user.
CREATE UNIQUE INDEX activity_sessions_one_open_idx ON activity_sessions (user_id)
    WHERE status IN ('active', 'paused');

-- High-volume GPS samples: TimescaleDB hypertable partitioned on recorded_at.
CREATE TABLE gps_points (
    session_id            UUID NOT NULL,
    recorded_at           TIMESTAMPTZ NOT NULL,
    lat                   DOUBLE PRECISION NOT NULL,
    lon                   DOUBLE PRECISION NOT NULL,
    altitude_m            DOUBLE PRECISION,
    horizontal_accuracy_m DOUBLE PRECISION,
    speed_mps             DOUBLE PRECISION,
    -- pedometer cadence at capture time; anti-cheat cross-check input (M3)
    step_cadence          DOUBLE PRECISION,
    PRIMARY KEY (session_id, recorded_at)
);
SELECT create_hypertable('gps_points', 'recorded_at');
CREATE INDEX gps_points_session_idx ON gps_points (session_id, recorded_at);
