-- M5: rewards + Guardian linking. Money-adjacent — everything auditable.

-- Refunds get their own ledger kind; balances can never go negative.
ALTER TABLE points_ledger DROP CONSTRAINT points_ledger_kind_check;
ALTER TABLE points_ledger ADD CONSTRAINT points_ledger_kind_check CHECK (kind IN
    ('activity_earn', 'challenge_reward', 'redemption_spend', 'redemption_refund', 'admin_adjust'));
ALTER TABLE users ADD CONSTRAINT users_points_balance_nonneg CHECK (points_balance >= 0);

-- Guardian (Hội Cam) membership link. One member id per account, globally.
ALTER TABLE users
    ADD COLUMN guardian_member_id TEXT UNIQUE,
    ADD COLUMN guardian_linked_at TIMESTAMPTZ;

-- Catalog. partner = adapter code; Guardian is the anchor partner, not the only one.
CREATE TABLE rewards (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner     TEXT NOT NULL DEFAULT 'guardian',
    title       TEXT NOT NULL,
    description TEXT,
    cost_points BIGINT NOT NULL CHECK (cost_points > 0),
    stock       INT CHECK (stock >= 0), -- NULL = unlimited
    active      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE redemptions (
    id              UUID PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reward_id       UUID NOT NULL REFERENCES rewards(id),
    cost_points     BIGINT NOT NULL, -- snapshot at redeem time
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'fulfilled', 'failed')),
    idempotency_key TEXT NOT NULL,
    voucher_code    TEXT,  -- issued by the partner adapter
    partner_ref     TEXT,  -- partner-side transaction reference
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Client retries must never double-spend.
CREATE UNIQUE INDEX redemptions_idem ON redemptions (user_id, idempotency_key);
CREATE INDEX redemptions_user_idx ON redemptions (user_id, created_at DESC);
CREATE INDEX redemptions_day_idx ON redemptions (created_at);

-- Dev seed catalog (voucher-code baseline until Guardian API reality is known).
INSERT INTO rewards (partner, title, description, cost_points, stock) VALUES
    ('guardian', 'Sticker NullShift', 'Sticker độc quyền cho runner', 25, NULL),
    ('guardian', 'Mẫu thử miễn phí Guardian', 'Nhận mẫu thử tại cửa hàng', 5, 1),
    ('guardian', 'Voucher Guardian 20.000đ', 'Áp dụng toàn bộ cửa hàng Guardian', 200, NULL),
    ('guardian', 'Voucher Guardian 50.000đ', 'Áp dụng toàn bộ cửa hàng Guardian', 450, 100);
