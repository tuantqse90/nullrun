# Null Run — Technical Overview

> Kiến trúc kỹ thuật: AI dùng ở đâu, Backend, Frontend (iOS), Camera/Vision, Web, Infra.
> Cập nhật 2026-07-12. Mảng kinh doanh: [business.md](business.md).

---

## 0. Nguyên tắc kiến trúc

- **Heavy compute là native + Rust** bất kể vỏ ngoài: 3D scan = Swift/Vision, sensor fusion = native, hot path backend (fraud, ledger, leaderboard, GPS ingest) = Rust.
- **Một ngôn ngữ backend end-to-end (Rust):** một toolchain, một deploy.
- **On-device là câu chuyện riêng tư:** ảnh cơ thể / ảnh thú cưng **không rời khỏi máy**.
- **Điểm là append-only ledger** (Postgres), idempotent mint, economy firewall (nguồn cosmetic không bao giờ chảy ngược thành điểm cá nhân).

---

## 1. AI dùng ở đâu 🧠

> **Lưu ý:** Spec gốc ghi "v1 = ZERO AI" (AI để v2). Vì track hackathon là **"AI-Powered Gamification"** nên đã **cố ý thêm AI vào app tiêu dùng** — đây là lệch có chủ đích, không phải bug.

### 1.1 Nhà cung cấp & kiến trúc chung
- **OpenAI-compatible API qua `reqwest`** (không local model, không GPU, không Python trong app layer).
- Cấu hình bằng env: `AI_BASE_URL` / `AI_API_KEY` / `AI_MODEL`.
- **Prod hiện dùng DeepSeek thật** (`deepseek-chat`, `https://api.deepseek.com/v1`). Trước đó là qwen-flash (DashScope). **Đổi provider = đổi 3 env, code không đổi.**
- Client dùng chung: `backend/src/ai.rs` — `chat()` (1 lượt) + `chat_messages()` (đa lượt, có JSON mode) + `parse_json()`.

### 1.2 Nguyên tắc AN TOÀN (áp cho mọi endpoint AI)
Model **KHÔNG được tự quyết** — nó chỉ:
1. **Diễn đạt số liệu THẬT** đã cung cấp (không bịa con số), hoặc
2. **Chọn từ whitelist** (nhiệm vụ/hành động do server định nghĩa), hoặc
3. **Viết copy trên điểm số deterministic** (churn score server tự tính).

Server **clamp + persist** mọi giá trị. Mọi endpoint có **template fallback** khi không có API key → demo không bao giờ chết vì thiếu credential. Guardrail (#4 rối loạn ăn uống, #6 tư vấn y tế) **nhúng thẳng vào system prompt**.

### 1.3 Các nơi dùng AI

| Nơi | Endpoint | AI làm gì | An toàn |
|---|---|---|---|
| **Coach insight** (Home) | `GET /v1/me/insight` | Diễn đạt số km tuần / mục tiêu / chuỗi ngày thành 1 câu động viên VN | Không bịa số; cấm nhắc cân nặng/hình thể (#4) |
| **Coach chat** ("Nhím Coach") | `POST /v1/me/coach/chat` | Chat đa lượt về **chạy bộ + ăn uống lành mạnh**, cá nhân hoá theo stats thật. Trả **JSON có cấu trúc** `{reply, chips, action}` | Cấm calo cực đoan / nhịn ăn / chẩn đoán bệnh; **soft-stop** → đẩy tới chuyên gia; rate cap 40/giờ/user; disclaimer |
| — nút tương tác | (trong chat) | AI gợi ý tối đa 3 **chip câu hỏi tiếp** + chọn **1 action từ whitelist** (`start_run`/`set_goal`/`none`) | Server sanitise chips + clamp action; client sở hữu label/hành vi → không chế được nút bậy |
| **VETC insight** (console) | `POST /v1/partner/ai/insight` | Thẻ insight cho tài xế từ số liệu 30 ngày thật | Không bịa số; không cổ vũ lái nhiều/nhanh |
| **VETC personalize** | `POST /v1/partner/ai/personalize` | Chọn ≤3 nhiệm vụ + hiệu chỉnh target | Chọn từ template; server clamp target (0.5×–2×) + persist `user_mission_overrides` |
| **VETC win-back** | `POST /v1/partner/ai/winback` | Viết tin nhắn win-back ngắn | Viết trên **churn score deterministic** server tính |

### 1.4 AI ở dev-time (không phải runtime)
- **Thiết kế catalog Tasco/VETC** dùng một **multi-agent workflow** (1 agent research hệ sinh thái + 8 agent thiết kế theo nhóm quà + 1 agent tổng hợp cân bằng giá), rồi 1 agent **review đối kháng**. Đây là công cụ dev, output là data seed vào DB.

---

## 2. Backend (BE) ⚙️

**100% Rust, monolith.**

- **Web framework:** Axum (tokio ecosystem) · serde · `validator`.
- **DB access:** `sqlx` — **runtime-checked queries** (không compile-time macro để CI chạy không cần DB), không ORM.
- **Data:** **PostgreSQL** primary + **TimescaleDB** (hypertable `gps_points` cho time-series GPS) + **pgvector** (embeddings, v2).
- **Redis** (`fred`): sorted-set leaderboard, rate-limit/anti-cheat counters, **Redis streams** cho hàng đợi ingest GPS.
- **Auth:** OTP (VN E.164, Redis TTL) → JWT access 15' + refresh rotation 30 ngày (hash trong DB). Device attestation (App Attest — `apple` mode chưa impl, `dev` mode chấp nhận unverified cho tới khi có iOS build thật).

### Các module chính (`backend/src/`)
- `auth/` — OTP, JWT, chuẩn hoá phone.
- `activities/` — session; `ingest.rs` (worker single-consumer drain Redis stream → hypertable, at-least-once + dedup); `compute.rs` (distance/pace, drop fix rác >50m, segment lỗi); `fraud.rs` (**7 tín hiệu có trọng số** → `fraud_score`/`verdict` clean|suspicious|rejected; rate cap 30s/20 ngày).
- `gamification/` — `on_clean_session` (mint **chỉ khi verdict='clean'**, một transaction: ledger + balance + streak + challenge + quest); `rules.rs` (versioned: walk 10 / run 15 pts/km, cap 300/ngày, tier theo quý VN); leaderboard/league; `wheel.rs`; `games.rs`; `quests.rs`; **coach insight + chat** (mục 1).
- `duels/` — đua 1v1, xử thắng theo **thời điểm cán mốc GPS** (`compute::crossing_time`).
- `guilds/` — hội chia nhiệm vụ; mint **guild XP** (cosmetic, `guild_xp_ledger`) — **economy firewall**, không đụng điểm cá nhân.
- `races/` — giải theo khung giờ (dawn/dusk VN), mốc cự ly → guild XP.
- `rewards/` — catalog + redeem **reserve-then-fulfill** (đặt điểm+stock trong 1 tx, gọi partner NGOÀI tx, refund nếu lỗi); **partner adapter** (`partner.rs`): `guardian`→GuardianMock, `vetc/vetcgo/tasco`→TascoMock (mã `VETC-/VGO-/TASCO-`); cổng link Guardian **chỉ áp cho quà guardian**.
- `mobility/` + `ai.rs` — adapter sự kiện VETC (toll/topup/fuel/parking) → mission; AI mục 1.
- `admin/` — extractor token tĩnh `AdminAuth`/`PartnerAuth`; stats, review-queue, CRUD.

### Bất biến (invariants)
- **Ledger append-only** — không bao giờ UPDATE/DELETE; điều chỉnh = row `admin_adjust` mới.
- **Idempotent mint** — UUIDv5 theo (user+kind+source+kỳ) → retry không double-mint.
- **`balance >= 0`** enforce bằng DB constraint.

### Deploy
- **KHÔNG build trên VPS** (box dùng chung). **Cross-compile trên Mac**: `cargo zigbuild --release --target x86_64-unknown-linux-musl` → binary tĩnh musl → Docker **COPY-only** (`Dockerfile.deploy`, Alpine) trên box → `docker compose up -d backend`. Migrations nhúng trong binary (`sqlx::migrate!`), tự chạy khi khởi động.
- VPS Hostinger, loopback :8500, Caddy reverse-proxy `api.nullshift.sh`. TimescaleDB + Redis riêng trong compose.

---

## 3. Frontend / iOS (FE) 📱

**Swift + SwiftUI native** (quyết định locked — background GPS/sensor/CV/ZK là native-only, không PWA/webview).

- **Project:** XcodeGen (`project.yml` → `xcodegen generate`).
- **Core (`NullShift/Core/`):**
  - `APIClient` — decode snake_case; on 401 **single-flight refresh** token rồi retry 1 lần; chỉ 401 refresh dứt khoát mới đá về login.
  - `AppModel` — state machine router mirror prototype; nạp dữ liệu song song (`async let`).
  - `RunTracker` — CoreLocation → batch upload `/points`; số live là ước tính client, số server là authoritative; publish toạ độ + route cho map.
  - `AuthStore`, `Keychain` (token sống qua reinstall).
- **Maps:** `Design/NullMap.swift` bọc **MapLibre Native** (SPM) trên **style NullMaps tự host** tại `maps.nullshift.sh` — "tự làm map, không đi thuê". Prerun theo fix live, Summary fit-bounds polyline.
- **Design system (`NullShift/Design/`):** tokens `Theme.swift` (hex khớp prototype), font **Be Vietnam Pro + IBM Plex Mono** (bundle trong `Fonts/`), mascot, motion kit (`Motion.swift`: Haptics, CountUpText, popIn, shineSweep, ConfettiRain — đều tôn trọng Reduce Motion), celebrations (tier > level-up > streak).
- **Screens (`NullShift/Screens/`):** một file/màn, bám design của founder. Gồm Home (có AI coach card), League/giải, Guild, Rewards (chia section theo đối tác + **artwork vector vẽ tay** `RewardArt`), Wheel, Games, Duel, Prerun/Run/Summary, Scan (body), Catch (bắt thú), HealthChat (Nhím Coach).
- **Rewards artwork:** minh hoạ vẽ bằng **SwiftUI Path/Canvas/gradient** (cổng thu phí, xe hơi, trụ xăng, ly cà phê…) — sắc nét mọi kích thước, không dùng file ảnh (iOS không render SVG native).

### Web
- **Next.js 15** — KHÔNG phải app tiêu dùng. Chỉ gồm: landing page, **admin console**, **partner dashboard** (Guardian), **VETC console** (`/vetc`, partner token). `output: "standalone"`, deploy loopback :3500 → `run.nullshift.sh`.

---

## 4. Camera / Vision 📷

Hai tính năng camera, **cả hai chạy Apple Vision on-device, không download model, không upload ảnh.**

### 4.1 Body scan (quét cơ thể) — `Core/ScanEngine.swift` + `ScanCamera`
- **Vision:** `VNGeneratePersonSegmentationRequest` → tách silhouette người → đo breadth/depth tại hàng eo/hông → tính chu vi ellipse, hiệu chỉnh bằng chiều cao user.
- **Camera:** front camera (AVFoundation). **Ảnh chỉ ở RAM**, drop ngay sau khi đo — **không ghi đĩa, không upload**.
- **Kết quả:** ước tính số đo ±vài cm, sửa tay được, gắn nhãn "từ máy quét". (v1.5 sẽ thay math bằng MediaPipe pose + SMPL fitting; luồng giữ nguyên.)
- **Hiển thị 3D:** `Design/BodyModel3D.swift` — **SceneKit** dựng nhân vật anime cel-shaded (da gradient teal→tím, đèn rim, mặt cute) + bạn đồng hành **nhím tím** (lớn theo level, đổi skin theo streak) trên bệ holo. **Không xuất số cân nặng tuyệt đối, không phán xét hình thể** (guardrail #4/#7).

### 4.2 "Thú Cưng Đường Phố" — bắt chó/mèo
- **Vision:** `VNRecognizeAnimalsRequest` — nhận diện **chó/mèo on-device** (không download model), live throttle ~5Hz trên serial queue.
- **Camera:** back camera (AVFoundation `AVCaptureVideoDataOutput` cho detect + `AVCapturePhotoOutput` cho ảnh bắt).
- **Engine (`Core/CritterEngine.swift`):** map bounding box Vision → reticle trên màn qua `layerRectConverted(fromMetadataOutputRect:)`; cơ chế **ná/slingshot** ném xương(chó)/cá(mèo).
- **Lưu trữ (`Core/CritterStore.swift`):** ảnh bắt lưu **trên máy** (`Documents/critters/`, `excludeFromBackup`, **không upload, không ghi vào Photo library**); thumbnail downsample off-main + cache (`ImageIO`).
- **Thẻ TCG (`Design/CritterCard.swift`):** độ hiếm (weighted roll), khung gradient, holographic sheen, kéo-nghiêng 3D (`rotation3DEffect`).
- **Hiệu ứng bắt (`Screens/CatchViews.swift` → `CatchBurst`):** flash + vòng sốc lan + tia nắng xoay + hạt/sao bắn (scale theo độ hiếm) + rung haptic. Đều tôn trọng Reduce Motion.
- **Firewall:** bắt thú **KHÔNG mint điểm** — bộ sưu tập cosmetic thuần local.

> Simulator không có camera → cả hai fallback nhẹ nhàng; test thật cần máy thật.

---

## 5. Platform decisions (LOCKED)

- **Mobile:** iOS native Swift/SwiftUI. Android (Kotlin native) sau — giữ API/protocol platform-agnostic.
- **Backend:** 100% Rust monolith (Axum + tokio + sqlx). gRPC/tonic chỉ khi tách service.
- **Data:** Postgres + TimescaleDB (không datastore riêng cho time-series) + pgvector (v2).
- **AI:** OpenAI-compatible qua reqwest (DeepSeek). Không local model/GPU/Python trong app layer.
- **Chain (roadmap):** Monad + Noir. **Hybrid ledger** — điểm tần suất cao off-chain (Postgres); on-chain chỉ neo artifact trust-minimized (achievement, finisher medal, milestone ZK proof). Điểm **soulbound/non-transferable** — không phải token đầu cơ. ZK generate on-device (Rust/Noir compile cho iOS, gọi qua UniFFI). *Chưa build — v1.5.*
- **Web KHÔNG phải app tiêu dùng.** Mini app Zalo/MoMo là funnel riêng, sau.
- **Infra:** VPS + Docker Compose + Caddy + Cloudflare DNS; APNs push (FCM khi có Android); observability Grafana + Loki (định hướng).

---

## 6. Auth/attestation ở prod (dev-grade — chưa cho user thật)
- `sms_mode=log`: OTP lộ trong response (cố định để test). Cần SMS provider thật trước khi mở user.
- `ATTEST_MODE=dev`: chấp nhận attestation unverified. Cần App Attest `apple` mode (verify CBOR + cert chain với Apple root) — **guardrail #1** bắt buộc trước production.
