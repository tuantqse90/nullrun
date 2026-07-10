# CLAUDE.md — NullShift Fitness/Health Gamification App

> Context file for Claude Code. Captures locked decisions, architecture, guardrails, and sequencing.
> Written in English for the coding agent — ask if you want a Vietnamese version.

---

## Project

A running/fitness **gamification** app for the **Vietnamese market**.

Core differentiators:
- **On-device 3D body-scan** progress (body composition / silhouette, NOT a scale replacement).
- **ZK-attested activity** (prove achievements without exposing raw biometric/movement data).
- **Guardian (Hội Cam) reward integration** — redeem genuine activity for real rewards.

**Business model — "Vitality-but-retailer":** earn points through *genuine* healthy activity → tier status → redeem rewards. The reward partner is a health/beauty **retailer** (Guardian, ~3.5M Hội Cam members) instead of an insurer. This is **B2B2C**: we sell engagement + first-party health data + store foot-traffic to Guardian; Guardian funds the rewards. The app is a **neutral activity + verification layer** — Guardian is the anchor partner; insurers/brands plug in later.

---

## Platform decisions (LOCKED)

### Mobile — iOS native, Swift (founder decision)
- **iOS:** Swift + SwiftUI.
- **3D body scan:** Core ML (MediaPipe pose + SMPL fitting), **on-device**.
- **Sensors / background GPS:** Core Motion + CoreLocation. Background-location reliability **IS the product** — anti-cheat depends on clean sensor data.
- **ZK proof generation on device:** Rust/Noir compiled for iOS, called from Swift via **UniFFI**.
- **Android:** Kotlin native, **LATER**. Do NOT lock v1 in a way that forces an Android rewrite — keep the API/protocol layer platform-agnostic.
- NOTE: iOS-first is a deliberate founder call. VN is Android-majority and the Guardian mass-market audience skews further Android — Android must follow for real reach.

### Backend — 100% Rust (no Python in app layer)
- **Web framework:** Axum (tokio ecosystem).
- **DB access:** sqlx — async, compile-time-checked SQL. No heavy ORM.
- **Runtime/utils:** tokio · serde · `validator` (replaces Pydantic).
- **Redis** (`fred` or `redis`): leaderboard (sorted sets), rate-limit counters, anti-cheat counters, ingestion queue (Redis streams).
- Monolith first. Use `tonic` (gRPC) only if/when a service is split out — the Python↔Rust bridge is gone, so internal gRPC is largely unnecessary now.

### Data
- **PostgreSQL** primary.
- **TimescaleDB** extension for activity/GPS time-series (high-volume GPS points) — still Postgres, no separate datastore.
- **pgvector** for embeddings (AI features, v2).

### AI — DeepSeek API only (v2 feature, NOT v1)
- All domain-11 AI (adaptive training plan, nutrition, insight engine, labs analyzer) → **DeepSeek API** via reqwest (OpenAI-compatible endpoint).
- **NO local model, NO Mac Studio / Ollama / vLLM.** No GPU infra to maintain.
- Optional later: a thin LiteLLM proxy as a provider gateway (swap/fallback) — NOT a Python app; decide at v2.
- **v1 ships with ZERO AI.** Backend is pure Rust.

### Chain — Monad + Noir
- Soulbound (non-transferable) points + finisher medals; ZK proof verification.
- **HYBRID ledger** — do NOT put every point on-chain. Off-chain points ledger in Postgres for high-frequency activity. On-chain ONLY anchors trust-minimized artifacts: achievements, finisher medals, milestone ZK proofs.
- Points are **non-transferable / soulbound** by design — kills speculation + bot-farming. Do NOT ship a tradeable speculative token (no StepN-style tokenomics).

### Web (NOT the consumer app)
- **Next.js:** Guardian partner dashboard + internal admin console + landing page only.
- Consumer product = iOS native. Do NOT build the consumer app in Next.js / as a PWA — webview cannot do background GPS, sensors, on-device CV, or on-device ZK.
- **Mini app (Zalo/MoMo):** acquisition/redemption funnel, **separate codebase, built LATER**. It funnels into the native app; it is not the engine.

### Infra
- Hetzner + Coolify (self-hosted). Push: APNs (add FCM when Android lands). Observability: Grafana + Loki.

---

## Architecture principles
- The **heavy compute is native + Rust** regardless of shell: 3D scan = Swift/Core ML, ZK = Rust/Noir, sensor fusion = native. Backend hot paths (fraud scoring, ledger, leaderboard aggregation, GPS ingestion) = Rust.
- **Single backend language end-to-end (Rust)** → one toolchain, one deploy, ZK verify lives in the same language as everything else. No Python↔Rust gRPC bridge.
- **3D scan on-device is the privacy story** (raw images/mesh never leave the device). If on-device is too heavy for v1.5, a server-side fallback (encrypt + delete-after-process) is possible but **punctures the privacy story** — this is a product decision, not a tech one.

---

## Non-negotiable guardrails (CRITICAL)

1. **Anti-cheat / integrity** — rewards = real money → industrial fraud (GPS spoof, shake-to-step, emulator). Required from day 1: sensor fusion validation, device attestation (App Attest / Play Integrity), fraud scoring, rate caps, **genuine-only earning** (no points for manually-added activity).
   - NOTE: ZK proves a computation ran correctly on data X — it does NOT prove data X wasn't spoofed at the source. Attestation + sensor fusion is still required *underneath* ZK.
2. **Anti-sybil (guild)** — must ship **BEFORE** any guild reward goes live. Block mass bot-guild creation; low-trust/new accounts contribute low weight; guild-level anomaly detection.
3. **Anti-sandbagging / collusion (guild war)** — must ship **BEFORE** war rewards. Matchmaking on true activity (not just current tier); detect drop-then-spike; reward structure must not pay tanking.
4. **Disordered-eating guardrail (NOT optional)** — gamified fitness + calorie targets + body scan + leaderboard is a proven trigger combo. No extreme calorie targets; do NOT gamify weight-loss as "more = win"; warning thresholds + soft-stops. Applies across body scan, gamification, and nutrition.
5. **Economy firewall** — multi-currency backed by real money. (a) Guild points must NOT buy anything that feeds back into personal points / Guardian rewards — guild shop is **cosmetic/utility only**. (b) Faucet/sink balance (shop + season reset are the sinks). Prevents the farm→power→reward flywheel.
6. **Health-advice liability / regulation** — nutrition + clinical = leaving "fitness app" for medical-advice territory; labs analyzer touches medical-device regulation. Disclaimers, deliberate design, clinical LAST.
7. **Privacy / data sensitivity** — health/body data is the most sensitive class. On-device processing + ZK + consent/selective disclosure turn the risk into the moat.

---

## Sequencing

- **v1 — test the loop:** onboarding, activity engine (walk + run), anti-cheat core, gamification core (points/tiers/streaks/league/leaderboard/challenges), rewards + Guardian linking, core backend + Guardian partner dashboard. **Goal:** validate that activity → points → Guardian reward drives behavior. Nothing outside this. **ZERO AI.**
- **v1.x — cheap, high-ROI:** virtual race/route + cycling + multi-activity, lucky wheel, Health Connect read, soulbound finisher-medal NFT, win-back. Reuses the engine.
- **v1.5 — differentiators:** 3D body scan, ZK/privacy + soulbound points, guild system (core → competition → discovery). Ship guild only when there's user density. Anti-sybil/guild-fraud ready first.
- **v2 — premium:** AI (DeepSeek) — training plan, nutrition, insight; corporate guild; brand-sponsored challenges. Disordered-eating guardrail mandatory.
- **v2.x — regulated + deepest meta:** clinical (labs / health metrics), guild seasonal meta (war/season/shop/quest), insurer tier, economy + live-ops tooling. This is a **live-ops commitment**, not ship-once.

---

## Hard "do NOT" list
- Do NOT build the consumer app as web/PWA/webview or as a Zalo/MoMo mini app — background GPS, sensors, on-device CV/ZK are native-only.
- Do NOT build guild chat — link guild ↔ Zalo group; the app owns competition/leaderboard, Zalo owns chat.
- Do NOT put every point on-chain — hybrid ledger; on-chain only for trust-minimized anchors.
- Do NOT make points a tradeable speculative token (no StepN tokenomics) — soulbound/non-transferable.
- Do NOT let the 3D scan output an absolute weight number — it is a progress / body-composition / silhouette engine; weight ground-truth = manual input / smart scale.
- Do NOT ship guild on day 1 with no density — empty guilds churn harder than no guild.
- Do NOT count manually-added activity for points — genuine auto-captured only.
- Do NOT open guild/war rewards before anti-sybil / anti-tank are live.
- Do NOT reintroduce Python in the app layer or a local model — DeepSeek API only.

---

## Open items (not yet decided)
- **Guardian (Hội Cam) API / BD access** — gates the entire product shape and the whole reward integration. Still open. Highest-priority unknown.

## Reference
- Full 106-feature breakdown lives in the feature-spec workbook (Feature Master / Roadmap / Guardrails sheets).
