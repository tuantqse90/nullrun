-- M3: anti-cheat verdicts on sessions.
-- Only verdict = 'clean' sessions may mint points (enforced by the M4 ledger).
-- 'suspicious' = quarantined for review; 'rejected' = hard fail, never earns.

ALTER TABLE activity_sessions
    ADD COLUMN fraud_score DOUBLE PRECISION,
    ADD COLUMN fraud_flags TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN verdict TEXT NOT NULL DEFAULT 'pending'
        CHECK (verdict IN ('pending', 'clean', 'suspicious', 'rejected'));

-- Review queue for the M6 admin console.
CREATE INDEX activity_sessions_review_idx ON activity_sessions (created_at)
    WHERE verdict = 'suspicious';
