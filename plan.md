# NullShift — v1 Plan

> Scope = v1 only: **validate that activity → points → Guardian reward drives behavior.**
> Nothing outside this. ZERO AI. (v1.x/v1.5/v2 items are out of scope — see `CLAUDE.md` sequencing.)
> Progress tracking lives in `progress.md` — update it whenever a task lands.

## Goal & success criteria

Ship a closed loop to a small beta cohort:

1. User onboards on iOS, walks/runs with auto-capture (background GPS).
2. Genuine activity earns points → tier/streak/leaderboard.
3. Points redeem into a Guardian (Hội Cam) reward — or a mocked partner flow if BD access hasn't landed.
4. Fraud/abuse does not pay: spoofed or manual activity earns nothing.

## Workstreams & milestones

Backend (Rust) and iOS proceed in parallel after M1. Order within each workstream matters; anti-cheat (M3) gates rewards (M5) going live.

### M0 — Foundation ✅ DONE

- [x] Repo init, monorepo layout, `CLAUDE.md`, backend hello-world (Axum, `/health`)
- [x] Docker compose for local dev: Postgres + TimescaleDB extension + Redis (host ports 5433/6380 — machine runs its own PG/Redis on defaults)
- [x] Enable sqlx + migrations setup (migrate-on-startup), `fred` Redis client, `validator`
- [x] Config/env handling (`config.rs` + `.env`), `AppError` type with JSON responses, tower-http request tracing
- [x] CI: `cargo fmt --check`, `clippy -D warnings`, `cargo test` (GitHub Actions)

### M1 — Identity & device trust 🟡 (backend done; iOS scaffold unbuilt)

- [x] Auth: phone/OTP (VN phone-first), JWT sessions (15-min access + 30-day rotating refresh, hashed at rest)
- [x] Device registration + App Attest challenge/verify flow — ⚠️ `ATTEST_MODE=dev` accepts unverified; real Apple verification is a hard TODO before production (needs a physical-device iOS build to test)
- [x] User profile basics (`GET/PATCH /v1/me`)
- [x] iOS: source scaffold (XcodeGen spec, onboarding phone→OTP, permission priming location "Always" + motion, Keychain token storage)
- [x] iOS: first successful build + launch on iPhone 16 Pro simulator (iOS 18.3), onboarding renders against local backend
- [ ] SMS provider integration (currently `sms_mode=log`, OTP echoed in response — dev only)

### M2 — Activity engine 🟡 (backend done; iOS tracking pending)

- [x] Schema: activity_sessions + gps_points TimescaleDB hypertable (one open session per user via partial unique index)
- [x] Ingestion API: batched points → Redis stream → single-consumer writer worker (at-least-once, UNNEST batch insert, dedup on PK, stream trimmed after cursor advance)
- [x] Session lifecycle: create/pause/resume/finish/discard; finish flush-waits the stream then computes distance/moving-duration/pace server-side (accuracy >50 m dropped, >12 m/s teleports dropped, >120 s gaps earn nothing, <0.3 m/s = standing)
- [x] Walk + run activity types only (cycling = v1.x)
- [x] iOS: Core Location live tracking (`RunTracker`) + CMPedometer cadence, session state machine (prerun/run/locked/pause/finish), batched ordered upload to `/points`, live client estimate mirroring server gates — verified on simulator with simulated GPS: **server verdict clean, fraud_score 0.0**
- [ ] iOS: offline buffering + resumable upload hardening, background-mode field testing on a physical device (reliability IS the product)

### M3 — Anti-cheat core 🟢 (rules engine live; ledger enforcement lands with M4)

- [x] Sensor-fusion validation: GPS↔cadence coherence (`no_step_cadence_while_moving`), speed/cadence sanity, teleport ratio, uniform-motion (bot/replay) detection, junk-accuracy ratio
- [x] Fraud scoring per session at finish (rules, no ML): weighted explainable flags → score → verdict `clean|suspicious|rejected`; attestation state is a heavy input; emulator signal = App Attest itself (fails on emulators)
- [x] Rate caps: session-create cooldown (30 s) + daily session cap (20/day) via Redis → 429; caps run after cheap validation so bad requests don't burn the cooldown. Daily *point* caps land with M4 points.
- [x] Attest-key reuse across accounts blocked (global unique key id → 400)
- [ ] **Genuine-only earning enforced at the ledger** — M4 ledger mints ONLY from `verdict = 'clean'` sessions; no manual-entry endpoint exists at all
- [ ] Quarantine review UI: suspicious sessions are stored + indexed (`activity_sessions_review_idx`); admin visibility lands in M6 dashboard

### M4 — Gamification core 🟡 (backend loop live; iOS UI waits on designs, APNs pending)

- [x] Points ledger: append-only in Postgres (hybrid ledger per spec), idempotent minting via (user, kind, source) unique index, materialized balance on users; **mints ONLY from verdict='clean' sessions — genuine-only earning now enforced**
- [x] Earning rules engine, versioned (`rules_version` on every ledger row): v1 = walk 10 / run 15 pts/km, min 500 m, floor; **daily activity cap 300 pts** (challenge rewards uncapped)
- [x] Tiers from season (calendar-quarter, VN time) earnings: bronze 0 / silver 1k / gold 5k / platinum 15k; season key on ledger rows makes reset automatic
- [x] Streaks: strict one-credit-per-VN-day, consecutive-day extension, best tracked; **no freezes in v1** (v1.x shop can sell them)
- [x] Leaderboard + league: Redis ZSETs, weekly keys (VN ISO week, 21-day TTL); league = 50-user buckets assigned on first weekly earn; activity points only (challenge bonuses don't inflate rank)
- [x] Challenges: individual distance challenges, join/progress/auto-complete + reward mint in the same transaction; 2 dev challenges seeded (admin CRUD = M6)
- [x] Endpoints: `GET /v1/me/points`, `GET /v1/leaderboard/weekly`, `GET /v1/league`, `GET/POST /v1/challenges[/{id}/join]`; finish response now carries `points_earned` + `challenge_bonus`
- [x] iOS: designed screens implemented from founder's prototype (`docs/design/null-run-prototype.html`) — home (streak/weekly-goal/quests/level/league/wheel banner), run/locked/summary, rewards+redeem+voucher, wheel, body-scan flow; quests/XP/wheel are client-local until their backends land (v1.x)
- [x] iOS: splash + login (s02: Zalo/Apple visual-first — "sắp ra mắt" until OAuth lands; phone/OTP works today), Giải đấu (s11: zones + me-row, real `/v1/league` data), Hội teaser (guild principles; unlocks with density per guardrail); all 5 tabs live
- [ ] iOS: Zalo OAuth + Sign in with Apple (backend + app) to replace phone-first order per s02's intent
- [ ] Push: APNs for streak reminders, challenge/league events (needs Apple developer account + APNs keys)

### M5 — Rewards + Guardian linking 🟡 (backend done on mock adapter; real Guardian API still gated by BD)

- [x] **Partner adapter interface** (`rewards/partner.rs`) — Guardian resolved by partner code like any future partner; **GuardianMock** issues voucher codes so the loop demos without BD access
- [x] Reward catalog + redemption flow (voucher-code baseline): transactional redeem — balance lock, stock decrement (NULL = unlimited), spend ledger entry, THEN partner call outside the tx with automatic refund path (`redemption_refund` ledger kind) on failure
- [x] Hội Cam membership linking: format-validated (real format TBD with BD), one member id per account globally, required before redeeming Guardian rewards
- [x] Redemption ledger with idempotency (client `idempotency_key`, replay returns the same redemption — no double spend) + token-gated `/v1/partner/reconciliation` daily report (real partner auth lands with M6 dashboard)
- [x] iOS: rewards catalog (ticket vouchers + product cards), redeem bottom sheet with idempotency, voucher screen (barcode + code), Guardian link prompt, wallet — UI-test verified end-to-end against the live backend
- [ ] Swap GuardianMock for the real integration when BD access lands (❗ still the highest-priority unknown); revisit reward pricing so faucet < reward budget

### M6 — Partner dashboard + admin 🟢 (done; static-token auth is a placeholder)

- [x] Scaffold Next.js 15 in `web/` (landing + /admin + /partner; port 3100 locally — 3000 is occupied on this machine)
- [x] Guardian-facing `/partner`: redemption volume by day/status, active users by day, challenge join/completion — backed by `GET /v1/partner/stats`
- [x] Internal admin `/admin`: today-at-a-glance stats, **fraud review queue with approve/reject** (approve mints through the normal idempotent pipeline), user lookup by phone (balance/devices/sessions), challenge + reward CRUD via API
- [x] Landing page (basic, VN copy)
- [ ] Replace static-token auth (`ADMIN_API_TOKEN`/`PARTNER_API_TOKEN`) with real auth before anyone outside the founding team gets access (M7)
- [ ] Tighten CORS from permissive to the deployed dashboard origin (M7)

### M7 — Hardening & beta

- [ ] Load-test GPS ingestion path; index/partition review on Timescale
- [ ] Observability: Grafana + Loki dashboards, alerting on ingestion lag + fraud-rate anomalies
- [ ] Deploy: Hetzner + Coolify, staging + prod, backup/restore drill for Postgres
- [ ] Privacy pass: data inventory, retention policy, consent copy (guardrail #7)
- [ ] TestFlight beta cohort; measure the loop (D1/D7 retention, sessions/week, redemption rate)

## Cross-cutting rules (from CLAUDE.md — enforce in every PR)

- Server-authoritative everything that touches points/money; client is untrusted input.
- No gamifying weight loss; no calorie mechanics in v1 at all (guardrail #4 stays trivially satisfied — keep it that way).
- Keep API/protocol layer platform-agnostic (Android later must not require a rewrite).
- No Python, no local AI models, no on-chain writes in v1.

## Suggested order of attack (solo/small team)

1. M0 remainder → M1 backend auth+attestation (iOS scaffold in parallel)
2. M2 end-to-end skeleton: fake a session from a test client → ingestion → computed session
3. M3 minimum viable anti-cheat (rules + caps) — before any points exist
4. M4 points/tiers/leaderboard → loop is playable internally
5. M5 with mock adapter → loop is fully demonstrable → chase Guardian BD with the demo
6. M6 dashboard → M7 hardening → TestFlight

## Out of scope (do not start in v1)

3D body scan · ZK/Noir · Monad/on-chain anchors · guilds/guild war · AI/DeepSeek · cycling/multi-activity · Zalo/MoMo mini app · Android · lucky wheel · Health Connect · clinical anything.
