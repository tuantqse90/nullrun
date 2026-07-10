-- M4: gamification core — points ledger, streaks, challenges.
-- HYBRID ledger per spec: high-frequency points live here in Postgres,
-- append-only. On-chain anchors (medals, milestone proofs) come in v1.5.

CREATE TABLE points_ledger (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount        BIGINT NOT NULL CHECK (amount != 0), -- positive = earn, negative = spend
    kind          TEXT NOT NULL CHECK (kind IN
                  ('activity_earn', 'challenge_reward', 'redemption_spend', 'admin_adjust')),
    source_id     UUID, -- session id / challenge id / redemption id
    rules_version TEXT NOT NULL,
    season        TEXT NOT NULL, -- e.g. 2026Q3 (VN time)
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Idempotent minting: one earn per (user, kind, source).
CREATE UNIQUE INDEX points_ledger_source_once
    ON points_ledger (user_id, kind, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX points_ledger_user_idx ON points_ledger (user_id, created_at DESC);
CREATE INDEX points_ledger_season_idx ON points_ledger (user_id, season);

-- Materialized balance + streak state (ledger stays the source of truth).
ALTER TABLE users
    ADD COLUMN points_balance BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN streak_current INT NOT NULL DEFAULT 0,
    ADD COLUMN streak_best INT NOT NULL DEFAULT 0,
    ADD COLUMN streak_last_date DATE; -- VN-timezone date of last streak credit

-- Individual challenges only (guild = v1.5).
CREATE TABLE challenges (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title         TEXT NOT NULL,
    description   TEXT,
    metric        TEXT NOT NULL DEFAULT 'distance_m' CHECK (metric IN ('distance_m')),
    target        DOUBLE PRECISION NOT NULL CHECK (target > 0),
    reward_points BIGINT NOT NULL CHECK (reward_points > 0),
    starts_at     TIMESTAMPTZ NOT NULL,
    ends_at       TIMESTAMPTZ NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_challenges (
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    progress     DOUBLE PRECISION NOT NULL DEFAULT 0,
    completed_at TIMESTAMPTZ,
    joined_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, challenge_id)
);

-- Dev seed data; admin CRUD for challenges lands with the M6 console.
INSERT INTO challenges (title, description, target, reward_points, starts_at, ends_at) VALUES
    ('Khởi động 2 km', 'Hoàn thành tổng 2 km hoạt động', 2000, 50,
     now() - interval '1 day', now() + interval '90 days'),
    ('Chinh phục 5 km', 'Hoàn thành tổng 5 km hoạt động', 5000, 200,
     now() - interval '1 day', now() + interval '90 days');
