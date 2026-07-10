-- Time-windowed daily races ("giải khung giờ"): the arena only opens during
-- fixed VN-time windows (dawn 5-9, dusk 18-22). Clean distance accumulated
-- inside a window crosses milestones; each crossed milestone contributes
-- GUILD XP (glory — the economy firewall keeps race rewards off personal
-- points/Guardian). Windows and milestones are DB rows — tune, add windows,
-- or run specials without code changes.

CREATE TABLE race_windows (
    code       TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    icon       TEXT NOT NULL DEFAULT '🏁',
    start_hour INT NOT NULL CHECK (start_hour BETWEEN 0 AND 23),
    end_hour   INT NOT NULL CHECK (end_hour BETWEEN 1 AND 24),
    active     BOOLEAN NOT NULL DEFAULT true,
    sort       INT NOT NULL DEFAULT 0,
    CHECK (end_hour > start_hour)
);

INSERT INTO race_windows (code, title, icon, start_hour, end_hour, sort) VALUES
    ('dawn', 'Giải Bình Minh', '🌅', 5, 9, 1),
    ('dusk', 'Giải Hoàng Hôn', '🌆', 18, 22, 2);

CREATE TABLE race_milestones (
    distance_m DOUBLE PRECISION PRIMARY KEY CHECK (distance_m > 0),
    guild_xp   BIGINT NOT NULL CHECK (guild_xp > 0),
    sort       INT NOT NULL DEFAULT 0
);

INSERT INTO race_milestones (distance_m, guild_xp, sort) VALUES
    (500, 10, 1),
    (2000, 25, 2),
    (5000, 60, 3);

-- Race contributions land in the guild XP ledger under their own kind.
ALTER TABLE guild_xp_ledger DROP CONSTRAINT guild_xp_ledger_kind_check;
ALTER TABLE guild_xp_ledger ADD CONSTRAINT guild_xp_ledger_kind_check
    CHECK (kind IN ('quest', 'race'));
