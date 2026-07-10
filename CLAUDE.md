# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**NullShift** — a running/fitness gamification app for the Vietnamese market. Core differentiators: on-device 3D body-scan progress, ZK-attested activity (prove achievements without exposing raw biometric data), and Guardian (Hội Cam) reward integration.

Business model is "Vitality-but-retailer" (B2B2C): genuine healthy activity → points → tier status → real rewards funded by Guardian. The app is a neutral activity + verification layer; Guardian is the anchor partner, insurers/brands plug in later.

Full original spec: `docs/init-prompt.md`. The 106-feature breakdown lives in the feature-spec workbook (Feature Master / Roadmap / Guardrails sheets), outside this repo.

**Working docs:** `plan.md` holds the v1 milestone plan (M0–M7); `progress.md` is the living log — when you complete a task, check it off in `plan.md` and add a dated line to `progress.md` (and record any deviation from the spec in its Decisions section).

**iOS screens: do NOT build new screens/visual UI proactively.** The founder designs them (with Claude) and hands the designs over for implementation. iOS infrastructure (tracking layer, API client, state machines) is fine to build; visual screens wait for designs.

## Repo layout

- `backend/` — Rust monolith (Axum). The only code that exists so far.
- `ios/` — iOS native app (Swift/SwiftUI). Not scaffolded yet; create the Xcode project here.
- `web/` — Next.js: Guardian partner dashboard + admin console + landing page ONLY. Not scaffolded yet.
- `docs/` — project spec and decisions.

## Commands

Local services first (repo root; this machine uses standalone `docker-compose` via colima — run `colima start` if the daemon is down):

```sh
docker-compose up -d   # Postgres+TimescaleDB on host port 5433, Redis on 6380
                       # (5433/6380 because this machine runs its own Postgres/Redis on the default ports)
```

Backend (run from `backend/`; fails fast at startup if Postgres/Redis are unreachable, and runs sqlx migrations from `backend/migrations/` automatically):

```sh
cargo run              # start server on :8080 (/health reports db+redis connectivity)
cargo test             # all tests
cargo test <name>      # single test by name substring
cargo clippy --all-targets -- -D warnings   # lint (CI-enforced)
cargo fmt              # format (CI checks --check)
```

Config via env vars or `backend/.env` (see `backend/.env.example`); defaults in `backend/src/config.rs` match docker-compose. CI (`.github/workflows/ci.yml`) runs fmt/clippy/test without services — keep compile-time-checked `sqlx::query!` macros out until an offline-cache (`cargo sqlx prepare`) step is added.

Web (`web/`, Next.js 15): `npm install && PORT=3100 npm run dev` (**3000 is occupied by another app on this machine**); `npm run build` to verify. Pages: `/` landing, `/admin` (header `x-admin-token` = `ADMIN_API_TOKEN`), `/partner` (`x-partner-token` = `PARTNER_API_TOKEN`). API base override: `NEXT_PUBLIC_API_BASE`.

Deploy (staging, 2026-07-10): shared Hostinger VPS `srv1589451` (creds + runbook in the founder's `~/Downloads/Telegram Desktop/config.txt`, section "NullShift run app"). On-VPS `/opt/null-run` compose: backend loopback :8500 (`api.nullshift.sh`), Next standalone web loopback :3500 (`run.nullshift.sh`), own TimescaleDB+Redis. **Never build Rust/npm on that box** — cross-compile locally (`cargo zigbuild --target x86_64-unknown-linux-musl`, see `backend/Dockerfile.deploy`) and ship artifacts; web ships as `output: "standalone"` tarball. Caddy fragment `/etc/caddy/conf.d/null-run.caddy` (shared Caddy — always `caddy validate` before reload). Still dev-grade auth in prod (sms_mode=log, ATTEST_MODE=dev) — no real users until SMS + App Attest land.

iOS (`ios/`): XcodeGen project. Build/run from `ios/`:

```sh
xcodegen generate                      # regenerate after changing project.yml or adding files
xcodebuild -project NullShift.xcodeproj -scheme NullShift \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild ... -destination 'id=<sim udid>' test   # XCUITest flow suite (UITests/)
```

**Do NOT pass `CODE_SIGNING_ALLOWED=NO`** — it breaks simulator Keychain (token writes fail → every authed call 401). Default ad-hoc simulator signing needs no dev account. If `xcodebuild` complains about CommandLineTools, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select on this machine may still point at CLT — switching needs sudo).

**Motion (dd6 spec in the design doc):** `Design/Motion.swift` is the kit — Haptics, CountUpText (600ms + tick haptics), popIn (350ms overshoot), shineSweep, riseIn stagger, ConfettiRain. Celebrations (`Screens/CelebrationViews.swift`) trigger from server-data deltas in `AppModel.detectCelebrations` (tier ceremony m01 > level-up > streak milestones; baseline cleared on logout). Every motion component respects Reduce Motion (150ms fades). Body-measurement surfaces stay static by design. QA hooks: `DEV_CELEBRATE=tier|level|streak`.

**iOS app structure:** the UI implements the founder's designs at `docs/design/null-run-prototype.html` (interactive prototype, 12 screens) and `docs/design/null-run-full-screens.html` (full screen catalog: login s02, league s11, tiers s12, etc. — truncated at 256KB, guild s20–s22 missing; re-fetch via DesignSync if needed) — treat them as the visual source of truth (colors/typography/copy). Login is phone/OTP today; Zalo/Apple buttons are design-faithful but "sắp ra mắt" until OAuth lands. `DEV_SCREEN=league|guild|rewards|wheel|games|duel|prerun|scancam` env (DEBUG) jumps to a screen for design QA. Body scan is REAL: `Core/ScanEngine.swift` (Vision person segmentation → silhouette breadth/depth at waist/hip rows → ellipse circumference calibrated by user height) + `ScanCamera` (front camera; photos live in RAM only, dropped after measuring). It's an honest ±few-cm estimate, editable by hand and labelled "từ máy quét"; the v1.5 MediaPipe+SMPL engine replaces the math, not the flow. Simulator has no camera — test on device. `NullShift/Design/` = tokens (Theme.swift, exact prototype hexes; Be Vietnam Pro + IBM Plex Mono bundled in `Fonts/`), mascot, shared components. `NullShift/Core/` = APIClient (snake_case decode; on 401 it single-flight-refreshes the token pair and retries once — only a definitive refresh 401 posts `authSessionExpired` → AuthStore drops to login; iOS Keychain survives reinstall, so stale tokens from another backend are expected), AppModel (screen router mirroring the prototype's state machine), RunTracker (CoreLocation → batched `/points` upload; live numbers are client estimates, server stats are authoritative; publishes `currentCoordinate`+`route` for the map). Maps: `Design/NullMap.swift` wraps MapLibre Native (SPM) over the self-hosted NullMaps styles at maps.nullshift.sh (public read-only); Prerun follows the live fix, Summary fit-bounds the run polyline, the Run screen stays stats-only per design. `NullShift/Screens/` = one file per designed screen. Quests/XP/wheel/games/duels/guilds are all server-driven; only body-scan stays client-local (on-device by design, real scan v1.5). GuildView has two states: no-guild (hero + join-by-code + discovery) and member home (XP hero with tap-to-copy invite code, Zalo chat link card, daily/weekly quest board, member contribution rings as % of each member's own weekly goal). Dev auto-login: launch with env `DEV_AUTOLOGIN_PHONE` (DEBUG builds only; uses the sms_mode=log debug code). Simulate runs: `simctl privacy <udid> grant location-always com.nullshift.app`, then jittered `simctl location set` loops (uniform tracks correctly trip the fraud engine).

## Backend API surface (M1)

All under `/v1`; auth = `Authorization: Bearer <access JWT>` (15-min expiry, refresh via rotation, 30-day refresh tokens stored hashed in `refresh_tokens`).

- `POST /v1/auth/otp/request {phone}` — VN numbers normalized to E.164 (`auth/phone.rs`); OTP in Redis, 5-min TTL, 3 requests/15 min/phone, 5 verify attempts. `sms_mode=log` (the only mode so far) logs the code AND echoes it as `debug_code` — remove when a real SMS provider lands.
- `POST /v1/auth/otp/verify {phone, code}` — creates the user on first login, returns `{access_token, refresh_token, user}`.
- `POST /v1/auth/refresh` / `POST /v1/auth/logout {refresh_token}` — rotation revokes the presented token; reuse of a rotated token → 401.
- `GET|PATCH /v1/me` — profile (display_name only so far).
- `POST /v1/devices/attest/challenge` → one-time nonce (Redis, 5 min); `POST /v1/devices/register` — device row; attestation optional but earning points must later require `attested_at IS NOT NULL`. **`ATTEST_MODE=dev` accepts attestations unverified** (no iOS build exists to make real ones); the `apple` mode (CBOR + cert chain against Apple's App Attest root) is unimplemented and REQUIRED before production — guardrail #1.

Activities (M2), all authenticated:

- `POST /v1/activities {activity_type: walk|run, device_id?}` — one open session per user (partial unique index → 400 on second). NOTE: no trailing slash — `/v1/activities/` 404s (axum nest behavior).
- `POST /v1/activities/{id}/points {points: [...]}` — ≤500/batch; goes to Redis stream `ingest:gps`, drained by a single-consumer background worker (`activities/ingest.rs`) into the `gps_points` hypertable. At-least-once + PK dedup; cursor in `ingest:gps:cursor`.
- `POST .../pause|resume|finish|discard`, `GET /v1/activities[?limit]`, `GET /v1/activities/{id}` — `finish` flush-waits the stream (≤5 s), then computes distance/moving-duration/pace in `activities/compute.rs` (drops fixes >50 m accuracy, segments >12 m/s or >120 s gap; <0.3 m/s doesn't count as moving). Stats are server-authoritative; client-reported speed is never trusted.

Anti-cheat (M3): `finish` also runs `activities/fraud.rs` — 7 weighted rule signals → `fraud_score`/`fraud_flags`/`verdict` (`clean|suspicious|rejected`) stored on the session. Session creation is rate-capped (30 s cooldown, 20/day, Redis) → 429; caps are checked read-only up front and recorded only after a successful insert, so NO failed create (validation, stranded open session) ever burns the cooldown — the iOS client relies on this to self-heal: on 400 it re-registers a stale device or discards a stranded open session, then retries once (`PrerunView.begin`). Attest key ids are globally unique — reuse on a second account → 400. Thresholds/weights are launch guesses; tune with beta data.

Gamification (M4, `src/gamification/`): `finish` mints points **only when `verdict='clean'`** via `on_clean_session` — one transaction covers ledger insert (idempotent on user+kind+source), balance, streak (strict, VN calendar days), challenge progress/completion+reward, **daily-quest settlement** (`quests.rs`: 3 server-verified quests/day, +5 each, idempotent via `rules::daily_source_id` UUIDv5 per VN day); Redis weekly leaderboard + 50-user league buckets update best-effort after commit and rank **activity points only** (quest/wheel mints never touch rank). Lucky wheel (`wheel.rs`): unlocked by a clean session today, one spin/VN-day, prize decided server-side pre-animation, kind `wheel_prize`. XP = lifetime positive ledger sum (`lifetime_earned` in `/v1/me/points` — no column). `weekly_goal_km` lives on users (PATCH `/v1/me`, 5–200) and `weekly_km` is server-computed from clean sessions since VN Monday. Rules are versioned in `rules.rs` (v1: walk 10 / run 15 pts/km, min 500 m, 300/day cap; tiers per VN quarter season). Endpoints: `/v1/me/points`, `/v1/leaderboard/weekly`, `/v1/league`, `/v1/challenges` (+`/{id}/join`), `/v1/quests`, `/v1/wheel` (+`/spin`). The ledger is append-only Postgres (hybrid-ledger spec) — never UPDATE/DELETE ledger rows; adjustments are new `admin_adjust` rows.

Games (`gamification/games.rs`, seeded from the founder's games sheet into the `games` table — edit rows, not code): 3 verification classes — `auto_distance|auto_duration|auto_streak` (server-verified from clean sessions/streak), `sensor_steps` (client pedometer value, attested device required), `self` (honor system: small reward, max 3 successful claims/day via Redis, cap consumed only on success). Rewards were scaled ~1/10 of the sheet's tokens to fit the point economy. `GET /v1/games`, `POST /v1/games/{code}/claim`.

Duels (`src/duels/`): 1v1 race, first to `target_m` (default 500 m). Flow: `POST /v1/duels` → 6-char code → `POST /v1/duels/join` → both create sessions with `duel_id` → `GET /v1/duels/{id}` polls live filtered distances and settles the winner by **earliest GPS crossing timestamp** (`compute::crossing_time`), minting `duel_win` idempotently. Quest defs live in `quest_defs`, wheel segments in `wheel_segments` — display info is DB rows, never code constants.

Guilds (`src/guilds/`, migration 0009): crews sharing daily/weekly quests. `POST /v1/guilds` (1 create/user/day), `POST /v1/guilds/join {code}` or `/{id}/join`, `GET /v1/guilds/mine` (members + quest board, lazy-settles), `PATCH /v1/guilds/mine/settings` (leader: emblem/zalo_link), `POST /v1/guilds/leave` (leader hands off to longest-standing member; empty guild dissolves), `GET /v1/guilds/discover` (**active-in-7d guilds only**, 7-day grace for new, full guilds hidden). Quest defs in `guild_quest_defs` (DB rows; `per_member` targets scale with size, `members_active` target is a fraction). Progress counts **clean sessions recorded after each member joined** only. Completion mints **guild XP** into `guild_xp_ledger` (idempotent per guild+quest+VN-day/ISO-week via UUIDv5) — `guilds.xp` → guild level (200 XP/level). **ECONOMY FIREWALL: guild XP never touches points_ledger/balance** — cosmetic glory only until full anti-sybil lands (guardrails #2/#5). Settle hook runs best-effort at the end of `on_clean_session`. JSON gotcha: never put a digit right after `_` in field names — Swift's convertFromSnakeCase turns `active_7d` into `active7D` and decode fails silently (field is named `active_week` for this reason).

Races (`src/races/`, migration 0010): time-windowed daily races — `race_windows` DB rows (dawn 5-9h, dusk 18-22h VN) + `race_milestones` (500m/2km/5km → guild XP). Only CLEAN sessions STARTED inside a window count; distance accumulates across sessions within one day's window; each crossed milestone mints guild XP (`kind='race'`, idempotent per user+window+milestone+VN-day) — economy firewall intact (races pay guild glory only). `GET /v1/races` returns open/closed + countdowns + my progress + top-5 standings. Settle hook after `on_clean_session`. iOS: live/teaser cards in LeagueView.

Rewards (M5, `src/rewards/`): partner adapter layer (`partner.rs`) — Guardian is partner code `guardian`, currently **GuardianMock** issuing voucher codes; swap internals when BD access lands. Redeem flow: reserve points+stock in one tx (spend ledger row, balance ≥ 0 enforced by constraint), partner call OUTSIDE the tx, refund (`redemption_refund` row) on failure — keep this shape for the real API. Client `idempotency_key` (unique per user) makes retries return the same redemption. Guardian membership must be linked (`POST /v1/guardian/link`, member id globally unique) before redeeming. `GET /v1/partner/reconciliation` is gated by the `PARTNER_API_TOKEN` env (`x-partner-token` header). Endpoints: `GET /v1/rewards`, `POST /v1/rewards/{id}/redeem`, `GET /v1/redemptions`.

Mobility/VETC demo layer (`src/mobility/` + `src/ai.rs`, migration 0011 — AABW 2026): partner event adapter proving the engine is source-agnostic. `POST /v1/partner/events` (x-partner-token) ingests toll/topup/fuel/parking events (idempotent per partner+external_id, users matched by phone); `partner_event_rules` + `mobility_missions` are DB rows; missions settle idempotently per user+mission+VN-period (daily/weekly/monthly). Off-peak metric excludes VN rush hours 6-9/16-19 — rules reward avoiding peaks, NEVER driving more/faster. AI endpoints (`/v1/partner/ai/insight|personalize|winback`) use the locked v2 architecture (OpenAI-compatible via reqwest, env AI_BASE_URL/AI_API_KEY/AI_MODEL; qwen-flash on the VPS): the model only phrases real stats / picks from whitelisted templates (server clamps + persists `user_mission_overrides`) / writes win-back copy over a deterministic churn score — and every endpoint falls back to templates when no key is set. Console at `web/app/vetc` (run.nullshift.sh/vetc, partner token); demo seeder: scratchpad `vetc_sim.py` (must set a browser-ish UA — Cloudflare blocks python-urllib).

Admin/partner (M6, `src/admin/`): static-token extractors `AdminAuth`/`PartnerAuth`. `/v1/admin/*`: stats, review-queue, `POST sessions/{id}/review {approve}` (approve mints via the idempotent `on_clean_session`; reject buries), `users/{phone}` lookup, challenge/reward CRUD. `/v1/partner/stats` for the Guardian dashboard. CORS is permissive — tighten plus replace static tokens at deploy (M7).

Handler pattern: extractor `AuthUser` (in `auth/jwt.rs`) for authenticated routes; runtime-checked `sqlx::query_as` + `bind`; errors via `AppError`.

## Platform decisions (LOCKED — do not revisit)

- **Mobile:** iOS native, Swift + SwiftUI (founder decision). 3D body scan = Core ML (MediaPipe pose + SMPL fitting), **on-device**. Sensors = Core Motion + CoreLocation — background-location reliability IS the product; anti-cheat depends on clean sensor data. ZK proofs generated on-device via Rust/Noir compiled for iOS, called from Swift via UniFFI. Android (Kotlin native) comes LATER — keep the API/protocol layer platform-agnostic so v1 never forces an Android rewrite.
- **Backend:** 100% Rust, monolith first. Axum + tokio + serde + `validator`. DB access via sqlx (compile-time-checked SQL, no heavy ORM). Redis for leaderboards (sorted sets), rate-limit/anti-cheat counters, and ingestion queue (Redis streams). `tonic`/gRPC only if a service is ever split out.
- **Data:** PostgreSQL primary; TimescaleDB extension for GPS/activity time-series (no separate datastore); pgvector for embeddings (v2).
- **AI:** v1 ships with **ZERO AI**. All v2 AI (training plan, nutrition, insights, labs analyzer) uses the DeepSeek API via reqwest (OpenAI-compatible). No local models, no GPU infra, no Python in the app layer.
- **Chain:** Monad + Noir. **Hybrid ledger** — high-frequency points live off-chain in Postgres; on-chain anchors only trust-minimized artifacts (achievements, finisher medals, milestone ZK proofs). Points are soulbound/non-transferable by design.
- **Web is NOT the consumer app.** Next.js serves the partner dashboard/admin/landing only. Zalo/MoMo mini app is a later, separate acquisition funnel.
- **Infra:** Hetzner + Coolify (self-hosted), APNs push (FCM when Android lands), Grafana + Loki observability.

## Architecture principles

- Heavy compute is native + Rust regardless of shell: 3D scan = Swift/Core ML, ZK = Rust/Noir, sensor fusion = native. Backend hot paths (fraud scoring, ledger, leaderboard aggregation, GPS ingestion) = Rust.
- Single backend language end-to-end (Rust): one toolchain, one deploy, ZK verification lives in the same language as everything else.
- On-device 3D scan is the privacy story (raw images/mesh never leave the device). A server-side fallback is a product decision, not a tech one — it punctures the privacy story.

## Non-negotiable guardrails

1. **Anti-cheat from day 1** — rewards = real money → industrial fraud. Sensor fusion validation, device attestation (App Attest / Play Integrity), fraud scoring, rate caps, genuine-only earning. Note: ZK proves a computation ran on data X — it does NOT prove X wasn't spoofed at the source; attestation + sensor fusion sit underneath ZK.
2. **Anti-sybil ships BEFORE any guild reward**; low-trust accounts contribute low weight; guild-level anomaly detection.
3. **Anti-sandbagging/collusion ships BEFORE guild-war rewards** — matchmaking on true activity, detect drop-then-spike, reward structure must not pay tanking.
4. **Disordered-eating guardrail (not optional)** — no extreme calorie targets; never gamify weight-loss as "more = win"; warning thresholds + soft-stops across body scan, gamification, nutrition.
5. **Economy firewall** — guild points must NOT feed back into personal points / Guardian rewards (guild shop is cosmetic/utility only); maintain faucet/sink balance.
6. **Health-advice liability** — nutrition/clinical features approach medical-advice/medical-device territory; disclaimers, deliberate design, clinical LAST.
7. **Privacy** — health/body data is the most sensitive class; on-device processing + ZK + consent/selective disclosure turn the risk into the moat.

## Sequencing

- **v1 (test the loop):** onboarding, activity engine (walk + run), anti-cheat core, gamification core (points/tiers/streaks/league/leaderboard/challenges), rewards + Guardian linking, backend + partner dashboard. Nothing outside this. ZERO AI.
- **v1.x:** virtual race/route, cycling, multi-activity, lucky wheel, Health Connect read, soulbound finisher-medal NFT, win-back.
- **v1.5:** 3D body scan, ZK/privacy + soulbound points, guild system (only when user density exists; anti-sybil first).
- **v2:** AI via DeepSeek (training plan, nutrition, insight), corporate guild, brand challenges.
- **v2.x:** clinical (labs), guild seasonal meta (war/season/shop/quest), insurer tier, live-ops tooling.

## Hard "do NOT" list

- Do NOT build the consumer app as web/PWA/webview or Zalo/MoMo mini app — background GPS, sensors, on-device CV/ZK are native-only.
- Do NOT build guild chat — link guild ↔ Zalo group; the app owns competition, Zalo owns chat.
- Do NOT put every point on-chain, and do NOT make points a tradeable token (no StepN tokenomics).
- Do NOT let the 3D scan output an absolute weight number — it is a progress/body-composition/silhouette engine; weight ground-truth = manual input / smart scale.
- Do NOT count manually-added activity for points — genuine auto-captured only.
- Do NOT ship guild on day 1, and do NOT open guild/war rewards before anti-sybil / anti-tank are live.
- Do NOT reintroduce Python in the app layer or a local model — DeepSeek API only.

## Open items

- **Guardian (Hội Cam) API / BD access** — still open; gates the entire reward integration and product shape. Highest-priority unknown.
