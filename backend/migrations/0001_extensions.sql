-- Baseline: required Postgres extensions.
-- timescaledb: GPS/activity time-series hypertables (M2).
-- pgcrypto: gen_random_uuid() for primary keys.
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
