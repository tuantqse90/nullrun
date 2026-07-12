# Null Run — Pitch content (5 slides, fundraising voice, English)

Each slide: **headline** (big text on slide) + supporting bullets (small text) + *spoken* (not on slide).
`[...]` = numbers/names the founder must lock before pitching.

Voice rule: slide text carries no pronouns (or "we" when unavoidable). Spoken lines use "we" throughout, plain and direct.

---

## Slide 1 — Problem

**Headline:** Companies want to reward healthy behavior. Nobody can prove it's real.

Bullets:
- The Vitality model runs in dozens of markets. AIA already brought it to Vietnam. Demand is proven.
- But that's one insurer's closed program. Retail, banks, mobility have no neutral layer to plug into.
- Because step counters can be faked in five minutes. Shake your phone, earn rewards.
- StepN paid tokens per step. Bots farmed it. The whole economy collapsed.

*Spoken:* The buyers already exist. What's missing is proof — nobody can tell who actually ran and who shook their phone in bed. That's the exact gap we build for.

Visual: text only. No images.

---

## Slide 2 — Product

**Headline:** Null Run: a running app where points come with proof.

Bullets:
- Real runs only. The app ships raw GPS; the server recomputes every distance and scores it against 7 fraud signals. The phone can't lie its way to a single point.
- Retention through play: streaks, leagues, quests, 1v1 duels, guilds, a lucky wheel.
- 3D body scan runs on-device. Photos never leave the phone. Insurers care about exactly this.
- Live in production. Not a prototype.

*Spoken:* There are plenty of running apps. What nobody built is the verification layer underneath. We built that layer first, then wrapped a game around it so it has users.

Visual: 1 real app screenshot (run screen + map). Dashed placeholder until the shot exists.

---

## Slide 3 — Business model

**Headline:** Users run for free. Partners pay.

Bullets:
- B2B2C: partners fund rewards for their own members. We charge per verified activity, plus behavioral health data partners can't measure themselves.
- [X] per verified activity + [Y] per user/month for insights. Partners currently push vouchers through channels they can't measure, at [Z] per redemption. Cheaper — and every redemption is proven.
- Points are pure loyalty points: soulbound, non-tradeable, no cash-out. Not a token, so there's no speculative economy to collapse.
- Vietnam: 100M people. [N] mass-participation races a year; [one verified race] sells out weeks ahead. Life insurers are starving for engagement tools.
- The loop: Real run → Verified → Points → Rewards (partner-funded).

*Spoken:* Runners never pay us. Businesses are the customer — they need certainty that their rewards reach people who actually move, not bots.

Visual: text only + the loop line in mono, Notion-callout style.

---

## Slide 4 — Why this is hard to copy

**Headline:** Adding the second partner costs almost nothing.

Bullets:
- Build the engine once; every event source is just input. Proven at this hackathon: VETC plugged in without touching the engine. Tolls, fuel, parking become in-app missions.
- Missions reward off-peak driving only — avoiding 6–9am and 4–7pm. Never pays anyone to drive more or faster. Exactly Tasco's congestion problem.
- Disciplined AI: the backend computes every number, AI only does the words. Picks missions from a whitelist, writes win-back copy over a deterministic churn score. It cannot invent a number. That's what lets an enterprise plug its data in.
- Strava sells social to serious runners. UpRace is step-counting CSR with no fraud defense. Vitality is locked inside one insurer. A neutral verification layer any partner can plug into: still empty. The hard part is device attestation, the fraud engine, on-device processing. UI can be copied in a week. These three can't.

*Spoken:* The right question is: what does partner number two or three cost to add? Almost zero. The verification engine stands alone; any event source is just input. And with no AI key, the system falls back to templates and keeps running — the demo never depends on a live model.

Visual: mono flow line: TOLL / TOP-UP / FUEL / PARKING → ADAPTER → IN-APP MISSIONS.

---

## Slide 5 — Team, execution, ask

**Headline:** It's real and it's running. [X] makes it fast.

Bullets:
- Execution speed — shipped live during this hackathon: Rust backend, native iOS app, self-hosted map tiles, partner console. No public users yet; that is exactly what this round buys.
- Team: [4 people — name, role, one line of experience each]
- Ask: [X] for 12 months, three milestones:
  - Production-grade fraud defense and real SMS.
  - One paid pilot: a retail partner + VETC.
  - 10,000 beta users in HCMC/Hanoi at ≥[Y]% week-4 retention.
- Hit those three and the next round prices itself. Live demo, right now.

*Spoken:* We have zero users, and we'll say that plainly. What we do have is the engine a competitor would need a year to rebuild — and VETC's actual problem demoed on live software at this hackathon. Beta users won't be bought with ad spend either: partners push the app to their existing member base, so the distribution channel is the paying customer. This money buys speed, not direction.

Visual: 4 team boxes (real photos) + QR to the live demo.

---

## Q&A backup (not on slides — memorize)

- **"What about GPS spoofing?"** — Spoofed GPS leaves fingerprints: uniform tracks, impossible speeds, devices that fail attestation. That's what the 7 fraud signals are for. A dirty session mints nothing.
- **"AIA already has Vitality."** — Vitality is closed, AIA-only. We're the neutral layer: one engine, many partners. AIA could be a customer.
- **"How is this different from UpRace?"** — UpRace is a CSR step campaign: no fraud defense, no real economy. We sell the verification layer real money can safely flow through.
- **"How many users?"** — Zero public users, plainly. That's what this round buys: production infra, a paid pilot, 10k beta.
- **"Why not Android first?"** — iOS first because App Attest and a cleaner sensor stack make anti-cheat stronger. Android follows once the engine is proven; the API is platform-agnostic already.
