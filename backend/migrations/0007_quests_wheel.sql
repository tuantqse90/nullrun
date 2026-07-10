-- De-hardcode pass: daily quests, lucky wheel, weekly goal, voucher expiry.

ALTER TABLE points_ledger DROP CONSTRAINT points_ledger_kind_check;
ALTER TABLE points_ledger ADD CONSTRAINT points_ledger_kind_check CHECK (kind IN
    ('activity_earn', 'challenge_reward', 'quest_reward', 'wheel_prize',
     'redemption_spend', 'redemption_refund', 'admin_adjust'));

-- Personal weekly distance goal (design s05); editable in the app.
ALTER TABLE users ADD COLUMN weekly_goal_km DOUBLE PRECISION NOT NULL DEFAULT 25
    CHECK (weekly_goal_km >= 5 AND weekly_goal_km <= 200);

-- Vouchers carry a real validity window (copy says 90 days).
ALTER TABLE redemptions ADD COLUMN expires_at TIMESTAMPTZ;
UPDATE redemptions SET expires_at = created_at + interval '90 days';
ALTER TABLE redemptions ALTER COLUMN expires_at SET NOT NULL;
ALTER TABLE redemptions ALTER COLUMN expires_at SET DEFAULT (now() + interval '90 days');
