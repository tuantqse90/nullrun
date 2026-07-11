# Null Run — Demo Script (Tasco VETC Mobility · AI-Powered Gamification)

**Total: ~3:00.** English narration for judges; `[VN]` notes are for you.
Golden rule: **show the loop working, then show it works for VETC.** Don't
explain the architecture — let the running app + the console carry it. Every
number on screen is server-authoritative, so nothing here is faked for the demo.

Pre-flight checklist ▸ see the bottom of this file.

---

## 0:00 – 0:20 · Hook (talk over the app icon / hero)

> "Move-to-earn apps all died the same way — bots farmed the rewards. Loyalty
> programs reward *spending*, not *health*. And paying a toll is a transaction
> with zero reason to come back.
>
> **Null Run is the layer that fixes all three: one engine that proves activity
> is real, then lets any partner reward it.** It's live in production today."

`[VN]` Nói chậm, tự tin. Đây là câu định vị — đừng vội.

---

## 0:20 – 1:10 · The loop, live (iOS)

**Do:** Open the app (already logged in). Tap **Bắt đầu đi bộ** → the Prerun map
centers on the live GPS fix. Start walking (or run the sim track). Let it move a
few seconds so the route line draws on **our own map tiles**.

> "This is native iOS — background GPS, real sensors. The map you're looking at
> is **self-hosted; we render our own vector tiles**, we don't rent them. As I
> move, the app shows a client-side *estimate* — but it never gets to decide
> what I earned."

**Do:** Hold to finish → Summary screen with the fitted route polyline + stats.

> "On finish, the backend re-computes the distance from the raw GPS, drops the
> junk fixes, and runs a **7-signal fraud engine**. Only a *clean* session mints.
> These points, this streak, this tier — all server-authoritative."

`[VN]` Nếu quay trên simulator: chạy `gps_sim` track jitter trước. Nếu đi thật
ngoài đường thì càng tốt — cho thấy GPS thật.

---

## 1:10 – 1:40 · The privacy moment (body scan)

**Do:** Open **Quét cơ thể** → the 3D hologram spins on its holo-pedestal, the
hedgehog companion beside it.

> "Here's our differentiator and our moat: **on-device**. This 3D silhouette is
> built from an on-device Vision scan — the photos never leave the phone, never
> hit a server, excluded from backup. Same for the street-pet collection. The
> body model shows *shape*, never a weight number — no thin-or-fat judgement
> anywhere. Privacy isn't a setting; it's the product."

`[VN]` Đây là chỗ "khoe" — để hình hologram xoay 1-2 giây cho đẹp. Nhấn mạnh
"never leaves the phone".

---

## 1:40 – 2:30 · Why it wins the VETC track (web console)

**Do:** Switch to **run.nullshift.sh/vetc** (partner token already set).

> "Now the track. Because verification is *decoupled* from the reward source,
> VETC is just another input — no rebuild."

**Do:** Trigger / show a partner event landing (the seeder or a live POST).

> "A toll, a top-up, a fuel or parking event comes in through the partner
> adapter — idempotent, matched to the driver by phone — and turns into a
> **mission**. Crucially, the missions reward driving **off-peak** — avoiding
> rush hours. We never pay people to drive *more* or *faster*; the incentive
> matches Tasco's congestion goals."

**Do:** Show the AI panel (insight / personalize / win-back copy).

> "And this is *safe* AI-powered gamification. The model only **phrases real
> stats**, **picks from a whitelist** of missions, or writes win-back copy over
> a **churn score the backend computes deterministically**. It never invents a
> number — the server clamps and persists everything. No key? It falls back to
> templates. The demo never depends on a live model."

`[VN]` Nếu AI key còn sống thì show câu AI thật; nếu không, template vẫn ra —
nói luôn "đây là fallback, có chủ đích".

---

## 2:30 – 3:00 · Close (back to the deck's last slide)

> "One Rust engine. A native app. Our own maps. All deployed. The business is
> B2B2C — we sell **trusted engagement** and first-party health signals; Guardian,
> VETC, insurers and brands **fund** what their members earn. We built the engine
> once. Every new partner is just a new input.
>
> **Genuine activity, real rewards — and now, real trips.** Thank you."

---

## Pre-flight checklist

- [ ] iPhone (or simulator) logged in; a stranded open session discarded.
- [ ] Backend reachable: `curl https://api.nullshift.sh/health` → `status:ok`.
- [ ] Web console reachable: `run.nullshift.sh/vetc` loads with the partner token.
- [ ] A demo driver seeded so a VETC event has someone to match (phone-matched).
- [ ] If on simulator: location granted + `gps_sim` jittered track ready.
- [ ] Body-scan hologram renders (needs a real device for the *camera* scan; the
      result screen + hologram render anywhere via pre-seeded measures).
- [ ] Pitch deck open in a tab: the published Artifact (hero + moat + close).
- [ ] Screen-record as backup in case live GPS/network wobbles on stage.

## If something breaks (graceful fallbacks)

- **Live GPS won't fix** → play the backup screen-record of the run.
- **Camera scan unavailable** (simulator) → jump straight to the hologram result
  screen (`DEV_SCREEN=scanres`); it's the "wow", not the capture.
- **AI endpoint down / no key** → the template fallback is *the point*; say so.
- **VETC event won't POST live** → show the already-seeded missions in the console.
