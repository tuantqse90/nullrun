-- Guilds (Hội) — v1 core per the design's guild principles:
-- discovery only surfaces ACTIVE guilds; contribution reads as % of each
-- member's personal goal (never absolute km); chat lives on Zalo.
-- ECONOMY FIREWALL: guild quests mint GUILD XP (cosmetic glory/level) only —
-- never personal points, never anything Guardian-redeemable.

CREATE TABLE guilds (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL CHECK (char_length(name) BETWEEN 3 AND 30),
    emblem     TEXT NOT NULL DEFAULT '🦔',
    code       TEXT NOT NULL UNIQUE, -- 6-char join code
    created_by UUID NOT NULL REFERENCES users(id),
    zalo_link  TEXT, -- guild ↔ Zalo group; the app never builds chat
    xp         BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX guilds_name_idx ON guilds (lower(name));

CREATE TABLE guild_members (
    guild_id  UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
    user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (guild_id, user_id)
);
-- One guild per user (v1) — also blocks one account farming many guilds.
CREATE UNIQUE INDEX guild_members_one_guild ON guild_members (user_id);

-- Guild quest definitions — DB rows, tune without code changes.
-- per_member: target scales with member count (fair for small guilds).
-- members_active metric: target is a fraction of members (0..1).
CREATE TABLE guild_quest_defs (
    key       TEXT PRIMARY KEY,
    title     TEXT NOT NULL,
    description TEXT NOT NULL,
    cadence   TEXT NOT NULL CHECK (cadence IN ('daily', 'weekly')),
    metric    TEXT NOT NULL CHECK (metric IN ('sessions', 'distance_m', 'members_active')),
    target    DOUBLE PRECISION NOT NULL CHECK (target > 0),
    per_member BOOLEAN NOT NULL DEFAULT false,
    xp_reward BIGINT NOT NULL CHECK (xp_reward > 0),
    sort      INT NOT NULL DEFAULT 0,
    active    BOOLEAN NOT NULL DEFAULT true
);
INSERT INTO guild_quest_defs (key, title, description, cadence, metric, target, per_member, xp_reward, sort) VALUES
    ('gd_sessions', 'Cả hội cùng nhịp',    'Cả hội gom đủ số buổi tập sạch trong ngày',      'daily',  'sessions',       1,     true,  20, 1),
    ('gd_distance', 'Gom km chung',        'Tích luỹ đủ quãng đường sạch trong ngày',        'daily',  'distance_m',     2000,  true,  25, 2),
    ('gd_active',   'Điểm danh vận động',  'Quá nửa thành viên có hoạt động hôm nay',        'daily',  'members_active', 0.5,   false, 30, 3),
    ('gw_distance', 'Đường dài cùng nhau', 'Cả hội gom đủ quãng đường trong tuần',           'weekly', 'distance_m',     10000, true,  100, 4),
    ('gw_sessions', 'Bền bỉ cả tuần',      'Cả hội gom đủ số buổi tập trong tuần',           'weekly', 'sessions',       3,     true,  80,  5),
    ('gw_active',   'Không ai bị bỏ lại',  '70% thành viên có hoạt động trong tuần',         'weekly', 'members_active', 0.7,   false, 120, 6);

-- Guild XP ledger: append-only, idempotent per quest+period.
CREATE TABLE guild_xp_ledger (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guild_id  UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
    amount    BIGINT NOT NULL CHECK (amount > 0),
    kind      TEXT NOT NULL DEFAULT 'quest' CHECK (kind IN ('quest')),
    source_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (guild_id, kind, source_id)
);
