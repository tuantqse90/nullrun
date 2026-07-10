-- Games (from "NullShift - Games.xlsx") + PvP duels.
-- Everything display-facing lives in DB rows — no hardcoded feature info.

ALTER TABLE points_ledger DROP CONSTRAINT points_ledger_kind_check;
ALTER TABLE points_ledger ADD CONSTRAINT points_ledger_kind_check CHECK (kind IN
    ('activity_earn', 'challenge_reward', 'quest_reward', 'wheel_prize',
     'game_reward', 'duel_win', 'redemption_spend', 'redemption_refund', 'admin_adjust'));

-- Wellness games. verification:
--   auto_distance  — clean GPS meters today >= target (server-verified)
--   auto_duration  — a clean session today with moving seconds >= target
--   auto_streak    — streak_current >= target
--   sensor_steps   — device pedometer steps today >= target (attested device)
--   self           — honor system: small reward, capped per day, auditable
CREATE TABLE games (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          TEXT NOT NULL UNIQUE,
    title         TEXT NOT NULL,
    description   TEXT NOT NULL,
    category      TEXT NOT NULL,
    tier          TEXT NOT NULL CHECK (tier IN ('easy', 'medium', 'hard')),
    verification  TEXT NOT NULL CHECK (verification IN
                  ('auto_distance', 'auto_duration', 'auto_streak', 'sensor_steps', 'self')),
    target_value  DOUBLE PRECISION NOT NULL,
    unit          TEXT NOT NULL,
    reward_points BIGINT NOT NULL CHECK (reward_points > 0),
    cadence       TEXT NOT NULL DEFAULT 'daily' CHECK (cadence IN ('daily', 'once')),
    active        BOOLEAN NOT NULL DEFAULT true,
    sort          INT NOT NULL DEFAULT 0
);

-- Rewards scaled ~1/10 of the sheet's tokens to fit the v1 point economy
-- (voucher 20K = 200 pts). Tune per-row in DB, not in code.
INSERT INTO games (code, title, description, category, tier, verification, target_value, unit, reward_points, cadence, sort) VALUES
    ('step_3k',        'Khởi động bước chân',   'Đạt 3.000 bước trong ngày',                              'physical',  'easy',   'sensor_steps',  3000, 'bước',  5,  'daily', 1),
    ('water_8',        'Uống đủ nước',          'Uống đủ 8 ly nước hôm nay',                              'nutrition', 'easy',   'self',          8,    'ly',    5,  'daily', 2),
    ('mindful_3m',     'Phút chánh niệm',       '3 phút hít thở hoặc thiền có hướng dẫn',                 'mental',    'easy',   'self',          3,    'phút',  5,  'daily', 3),
    ('gratitude_3',    'Nhật ký biết ơn',       'Viết 3 điều bạn biết ơn hôm nay',                        'mental',    'easy',   'self',          3,    'điều',  5,  'daily', 4),
    ('stretch_10m',    'Giãn cơ 10 phút',       'Bài giãn cơ hoặc mobility 10 phút',                      'physical',  'easy',   'self',          10,   'phút',  5,  'daily', 5),
    ('step_8k',        'Bước tiến lớn',         'Đạt 8.000 bước trong ngày',                              'physical',  'medium', 'sensor_steps',  8000, 'bước',  15, 'daily', 6),
    ('sweat_20m',      'Đổ mồ hôi 20 phút',     'Một buổi tập 20 phút — tự xác minh từ buổi chạy sạch',   'physical',  'medium', 'auto_duration', 1200, 'giây',  15, 'daily', 7),
    ('sleep_7h',       'Ngủ đủ giấc',           'Ngủ 7–8 tiếng đêm qua',                                  'wellness',  'medium', 'self',          7,    'giờ',   15, 'daily', 8),
    ('balanced_plate', 'Bữa ăn cân bằng',       'Một bữa đủ đạm – rau – tinh bột',                        'nutrition', 'medium', 'self',          1,    'bữa',   15, 'daily', 9),
    ('brain_boost',    'Tập não',               'Hoàn thành 1 trò chơi trí nhớ hoặc câu đố',              'mental',    'medium', 'self',          1,    'lượt',  15, 'daily', 10),
    ('buddy_workout',  'Tập cùng bạn',          'Tập cùng một người bạn hôm nay',                         'social',    'medium', 'self',          1,    'buổi',  15, 'daily', 11),
    ('detox_4h',       'Cai điện thoại 4 giờ',  '4 giờ không điện thoại + vài dòng cảm nhận',             'mental',    'hard',   'self',          4,    'giờ',   30, 'daily', 12),
    ('hiit_1',         'Chiến binh HIIT',       'Hoàn thành 1 buổi HIIT trọn vẹn',                        'physical',  'hard',   'self',          1,    'buổi',  30, 'daily', 13),
    ('run_5k',         'Chinh phục 5K',         'Chạy/đi bộ nhanh 5 km — xác minh GPS tự động',           'physical',  'hard',   'auto_distance', 5000, 'm',     30, 'daily', 14),
    ('streak_30',      'Chuỗi 30 ngày',         'Giữ chuỗi 30 ngày liên tiếp — thưởng cột mốc',           'overall',   'hard',   'auto_streak',   30,   'ngày',  100, 'once', 15);

-- PvP duel: first to target_m (default 500 m) wins.
CREATE TABLE duels (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code          TEXT NOT NULL UNIQUE, -- 6-char join code
    creator_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    opponent_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    target_m      DOUBLE PRECISION NOT NULL DEFAULT 500
                  CHECK (target_m >= 100 AND target_m <= 10000),
    reward_points BIGINT NOT NULL DEFAULT 25,
    status        TEXT NOT NULL DEFAULT 'open'
                  CHECK (status IN ('open', 'active', 'finished', 'cancelled')),
    winner_id     UUID REFERENCES users(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at   TIMESTAMPTZ
);
CREATE INDEX duels_creator_idx ON duels (creator_id, created_at DESC);
CREATE INDEX duels_opponent_idx ON duels (opponent_id, created_at DESC);

ALTER TABLE activity_sessions ADD COLUMN duel_id UUID REFERENCES duels(id);
CREATE INDEX activity_sessions_duel_idx ON activity_sessions (duel_id) WHERE duel_id IS NOT NULL;

-- Quest definitions move from code constants into rows (metrics stay keyed).
CREATE TABLE quest_defs (
    key           TEXT PRIMARY KEY,
    title         TEXT NOT NULL,
    target        DOUBLE PRECISION NOT NULL,
    reward_points BIGINT NOT NULL,
    sort          INT NOT NULL DEFAULT 0,
    active        BOOLEAN NOT NULL DEFAULT true
);
INSERT INTO quest_defs (key, title, target, reward_points, sort) VALUES
    ('session_1',   'Hoàn thành 1 buổi tập',    1,    5, 1),
    ('points_30',   'Tích 30 điểm trong ngày',  30,   5, 2),
    ('distance_2k', 'Đi/chạy 2 km trong ngày',  2000, 5, 3);

-- Wheel segments become data too (weights must sum to 100).
CREATE TABLE wheel_segments (
    idx    INT PRIMARY KEY,
    value  BIGINT NOT NULL CHECK (value > 0),
    weight INT NOT NULL CHECK (weight > 0)
);
INSERT INTO wheel_segments (idx, value, weight) VALUES
    (0, 20, 25), (1, 50, 15), (2, 30, 20), (3, 100, 5), (4, 20, 20), (5, 30, 15);
