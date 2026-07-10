-- Partner event adapter (VETC/mobility demo, AABW 2026): the engine's
-- earning input is source-agnostic — partners push signed events (toll
-- passes, top-ups, fuel, parking) and the same ledger/mission machinery
-- that powers runs mints points and settles missions. Everything a partner
-- can tune (event points, caps, missions) is DB rows.

CREATE TABLE partner_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner     TEXT NOT NULL,
    external_id TEXT NOT NULL,             -- partner's own id → idempotent ingest
    user_ref    TEXT NOT NULL,             -- partner's user handle (phone, E.164)
    user_id     UUID REFERENCES users(id), -- resolved at ingest when the user exists
    event_type  TEXT NOT NULL,
    amount_vnd  BIGINT,
    province    TEXT,
    station     TEXT,
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (partner, external_id)
);
CREATE INDEX partner_events_user_idx ON partner_events (user_id, occurred_at DESC);
CREATE INDEX partner_events_time_idx ON partner_events (partner, occurred_at DESC);

-- Points per event type — partner-tunable rows, never code constants.
-- daily_max caps how many of this type earn points per user per VN day.
CREATE TABLE partner_event_rules (
    partner    TEXT NOT NULL,
    event_type TEXT NOT NULL,
    title      TEXT NOT NULL,
    points     BIGINT NOT NULL CHECK (points >= 0),
    daily_max  INT NOT NULL DEFAULT 10,
    PRIMARY KEY (partner, event_type)
);
INSERT INTO partner_event_rules (partner, event_type, title, points, daily_max) VALUES
    ('vetc', 'toll_pass', 'Qua trạm thu phí ETC', 15, 6),
    ('vetc', 'topup',     'Nạp tiền tài khoản',   10, 2),
    ('vetc', 'fuel',      'Đổ xăng trạm đối tác', 20, 2),
    ('vetc', 'parking',   'Đỗ xe không dừng',      5, 4);

-- Mobility missions — same DB-driven philosophy as quest_defs/games.
-- Metrics are computed from partner_events; cadence daily|weekly|monthly.
CREATE TABLE mobility_missions (
    key           TEXT PRIMARY KEY,
    title         TEXT NOT NULL,
    description   TEXT NOT NULL,
    metric        TEXT NOT NULL CHECK (metric IN
                  ('events', 'toll_passes', 'offpeak_trips', 'topups', 'provinces', 'fuel_stops')),
    target        DOUBLE PRECISION NOT NULL CHECK (target > 0),
    reward_points BIGINT NOT NULL CHECK (reward_points > 0),
    cadence       TEXT NOT NULL CHECK (cadence IN ('daily', 'weekly', 'monthly')),
    active        BOOLEAN NOT NULL DEFAULT true,
    sort          INT NOT NULL DEFAULT 0
);
INSERT INTO mobility_missions (key, title, description, metric, target, reward_points, cadence, sort) VALUES
    ('m_daily_trip',   'Lăn bánh hôm nay',      'Qua trạm ETC ít nhất 1 lần trong ngày',            'toll_passes',   1, 10, 'daily',   1),
    ('m_offpeak_day',  'Né giờ cao điểm',       'Có chuyến đi ngoài khung 6-9h và 16-19h',          'offpeak_trips', 1, 15, 'daily',   2),
    ('m_toll_week',    'Bánh xe bền bỉ',        'Đi 5 chuyến cao tốc trong tuần',                   'toll_passes',   5, 40, 'weekly',  3),
    ('m_offpeak_week', 'Chiến binh thấp điểm',  '3 chuyến ngoài giờ cao điểm trong tuần',           'offpeak_trips', 3, 50, 'weekly',  4),
    ('m_topup_week',   'Ví luôn sẵn sàng',      'Nạp tiền trước khi cạn — 1 lần trong tuần',        'topups',        1, 20, 'weekly',  5),
    ('m_explore',      'Dấu chân đất Việt',     'Đi qua 3 tỉnh khác nhau trong tháng',              'provinces',     3, 80, 'monthly', 6);

-- AI-personalized target overrides: the personalizer picks missions and
-- calibrates targets per user (clamped server-side); settlement honors them.
CREATE TABLE user_mission_overrides (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mission_key TEXT NOT NULL REFERENCES mobility_missions(key) ON DELETE CASCADE,
    period_key  TEXT NOT NULL, -- VN day / ISO week / month the override applies to
    target      DOUBLE PRECISION NOT NULL CHECK (target > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, mission_key, period_key)
);

-- New ledger kinds for the adapter path.
ALTER TABLE points_ledger DROP CONSTRAINT points_ledger_kind_check;
ALTER TABLE points_ledger ADD CONSTRAINT points_ledger_kind_check CHECK (kind IN
    ('activity_earn', 'challenge_reward', 'quest_reward', 'wheel_prize', 'game_reward',
     'duel_win', 'partner_event', 'mission_reward', 'redemption_spend', 'redemption_refund',
     'admin_adjust'));
