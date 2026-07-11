# NullShift — Progress

> Living log. One line per completed item, newest first. Milestone status mirrors `plan.md`.

## Milestone status

| Milestone | Status |
|---|---|
| M0 — Foundation | ✅ Done (2026-07-09) |
| M1 — Identity & device trust | 🟢 Done + verified incl. iOS build (2026-07-09) — remaining: SMS provider + real App Attest (production blockers, not dev blockers) |
| M2 — Activity engine | 🟡 Backend done + verified (2026-07-09); iOS background tracking pending |
| M3 — Anti-cheat core | ✅ Done + verified (2026-07-09); ledger enforcement now live via M4; review UI with M6 |
| M4 — Gamification core | 🟡 Backend done + verified (2026-07-10); iOS UI waits on designs; APNs pending |
| M5 — Rewards + Guardian | 🟡 Backend done + verified on mock adapter (2026-07-10) · ❗ real Guardian API still gated by BD access |
| M6 — Dashboard + admin | 🟢 Done + verified (2026-07-10); static-token auth + permissive CORS to harden in M7 |
| M7 — Hardening & beta | 🟡 Deployed to VPS (2026-07-10, staging-grade: sms_mode=log + ATTEST_MODE=dev + static tokens còn nguyên) — hardening checklist chưa làm |

## Log

### 2026-07-11 (Thú Cưng Đường Phố — bắt chó mèo thật kiểu Pokémon-GO)

Founder đặt hàng trực tiếp màn hình + cơ chế (không phải mình tự vẽ) → build trọn bộ, bám design system.

- [x] **Scout workflow (3 agent song song)** chốt: Vision `VNRecognizeAnimalsRequest` (on-device, chó/mèo, không tải model — analog của body-scan segmentation); cơ chế **ná bắn mồi** (kéo-thả slingshot, vui 5/5 khả thi 5/5, ngắm bằng kỹ năng); lưu **on-device** (Documents+JSON, ảnh KHÔNG upload — đúng privacy), **KHÔNG mint điểm** (bắt mèo ≠ vận động → economy firewall), chỉ "cấp nhà sưu tầm" cosmetic
- [x] **`Core/CritterEngine.swift`**: camera SAU, `AVCaptureVideoDataOutput` throttle ~5Hz chạy VNRecognizeAnimalsRequest + `AVCapturePhotoOutput` chụp ảnh nét khi bắt; map bbox Vision→reticle qua `layerRectConverted`. **`Core/CritterStore.swift`**: bộ sưu tập on-device, ảnh Documents (excludeFromBackup), collector XP/level/badge cosmetic. **`Screens/CatchViews.swift`**: intro (có disclaimer "nhẹ nhàng đừng đuổi các bé") + game bắt (5 state: tìm→thấy→ngắm→ném→bắt/hụt, ná co giãn + đường bay parabola + reticle lock xanh + confetti + tên VN dễ thương tự sinh) + Sổ Bạn Nhỏ (Pokédex grid). Vào từ card Home; Reduce Motion tôn trọng
- [x] **Review workflow (10 agent adversarial) bắt 4 bug — 1 CRITICAL mà simulator KHÔNG THỂ thấy** (không có camera): `captureOutput` gọi `queue.sync` trên chính serial queue đang chạy → Vision deadlock frame đầu, cả feature chết trên máy thật. Fix. + 3 medium: reticle clamp tạo vùng chết nửa dưới khung (mèo dưới chân không bắt được), hysteresis xoá `held` giữa lúc ném (mồi biến mất + bắt trúng mà mất im lặng), `CritterStore.load()` nuốt decode-lỗi → catch tiếp ghi đè xoá sạch bộ sưu tập (giờ backup file hỏng). 2 finding bị bác (ảnh 720p không phình RAM, start/stop race không thật)
- [x] Verify: build sạch, screenshot intro + Sổ Bạn Nhỏ (collector cấp 2 + huy hiệu + grid), camera-fallback không crash trên sim; UI test 3/3 pass (card Home mới không phá flow). Game đầy đủ (ná + Vision) cần máy thật — device binary build sẵn chờ cắm iPhone

### 2026-07-11 (Bug hunt toàn project — 33-agent review, fix 24 bug)

Workflow 7 lens (backend-new/economy/security, ios-core/screens, api-contract, web) + adversarial verify chéo → 25 confirmed, 1 refuted (SceneView rebuild — SwiftUI prune body đúng). Fix 24, deploy + verify hết:

**Backend (economy/security):**
- [x] **Duel mint từ GPS chưa qua fraud (HIGH)** — settle từ live GPS TRƯỚC finish → session giả/rejected vẫn mint. Fix: chỉ settle khi crossing từ session `completed`+`clean`; và chỉ khi không còn ai đang chạy có thể cán sớm hơn (tránh "B finish trước nhưng A cán sớm hơn thắng sai"). Smoke mới xác nhận duel KHÔNG settle khi session còn mở
- [x] **Partner event bypass cap + re-mint mission (2×HIGH)** — `occurred_at` do đối tác gửi không validate → event lùi ngày né cap hôm nay, event tương lai tính vào mọi kỳ mission về sau. Fix: chặn mint ngoài [now-48h, now+15m], cap đếm theo VN-day CỦA event, metric mission có chặn trên `<= now()`. Smoke `m_vetc_abuse` 6/6 (backdated ≤ cap, stale/future rejected, replay idempotent)
- [x] **Guild join capacity race (MED)** — count-then-insert không lock → vượt MAX_MEMBERS. Fix: `SELECT … FOR UPDATE` serialize theo guild
- [x] **Race window theo ngày settle-time không phải session-day (MED)** + **race XP không idempotent qua đổi hội / bỏ qua joined_at (MED)** — fix: bounds theo VN-day của session, window_distance clamp `joined_at`, source id dùng `{:.1}` không truncate
- [x] **admin review retry 404 (MED)** — approve chấp nhận session đã `clean` để re-mint idempotent; **finish() retry-safe** (re-fetch completed session, mint lại idempotent thay vì mất điểm)
- [x] **games self-cap non-atomic (LOW)** — reserve slot bằng INCR trước mint, DECR khi trùng
**iOS:**
- [x] **GPS batch mất khi upload fail (HIGH)** — requeue vào buffer + flushNow retry 4 lần; **redeem idempotency key giữ ổn định/sheet (HIGH)** — không double-spend khi retry; **date encode fractional-seconds** — 2 fix GPS cùng giây không đè PK
- [x] rotateTokens vs logout race (guard token còn hiện tại mới ghi); Guild create/settings + Guardian link error giờ hiển thị; VoucherView THẬT tăng độ sáng; Fmt.time có giờ; LeagueView hạng kế theo tier; HomeView đếm ngày tuần Monday-start; SummaryView splits = số THẬT từ tracker (bỏ jitter bịa); RunView milestone baseline sống qua khoá màn; ScanView flash render được; showToast không bị timer cũ xoá; RunTracker deinit dọn timer
**Web:** partner "active hôm nay" khớp đúng ngày VN (bỏ `[0]` stale); vetc `.console.gate` selector compound
- [x] Verify: backend clippy sạch + 29 unit + 6 smoke suite (m3/m4/guild/races/duel-14/vetc-abuse-6) pass; iOS build + UI 3/3 pass; web tsc + build sạch. Deploy VPS (abuse smoke 6/6 trên api.nullshift.sh) + web; device binary build sẵn chờ cắm iPhone

### 2026-07-11 (VETC/AABW demo layer — engine đổi nguồn sự kiện, thêm lớp AI)

- [x] **Partner event adapter (migration 0011)**: `POST /v1/partner/events` (x-partner-token, batch ≤500) — VETC đẩy sự kiện toll_pass/topup/fuel/parking; idempotent theo (partner, external_id); map user qua SĐT (event đến trước khi có account thì lưu chờ); mint `partner_event` theo `partner_event_rules` (điểm + cap/ngày/loại — DB rows) vào CÙNG points_ledger của fitness. Chứng minh luận điểm pitch: engine source-agnostic
- [x] **6 mission mobility (`mobility_missions`, DB rows)**: Lăn bánh hôm nay, Né giờ cao điểm (metric offpeak — NGOÀI khung 6-9/16-19 VN: trả thưởng để giãn ùn tắc, guardrail "không bao giờ thưởng lái nhanh/nhiều"), Bánh xe bền bỉ 5 chuyến/tuần, Chiến binh thấp điểm, Ví luôn sẵn sàng, Dấu chân đất Việt 3 tỉnh/tháng. Settle idempotent theo user+mission+kỳ (ngày/tuần/tháng VN); `GET /v1/missions` cho user
- [x] **Lớp AI (kiến trúc v2 đã khoá: OpenAI-compatible qua reqwest — `src/ai.rs`, env AI_BASE_URL/KEY/MODEL)**: `/v1/partner/ai/insight` (thẻ Wrapped từ số THẬT — model chỉ viết lời, không bịa số), `/personalize` (model CHỌN mission từ whitelist + hiệu chỉnh target, server clamp 0.5x-2x rồi ghi `user_mission_overrides` — board user đổi ngay, economy vẫn deterministic), `/winback` (churn score = heuristic ta tính, model chỉ viết tin nhắn). **Mọi endpoint có fallback template khi thiếu key — demo không bao giờ chết**. Chạy thật với qwen-flash (dashscope compatible-mode; qwen-plus hết free quota)
- [x] **VETC Engagement Console** (`run.nullshift.sh/vetc`): stat cards, biểu đồ lưu lượng theo giờ VN với vùng cao điểm tô đỏ, bảng mission + số tài xế đạt theo kỳ, feed sự kiện (SĐT che), panel AI 3 nút. **Simulator `vetc_sim.py`**: 8 tài xế + ~38 sự kiện/lượt, chạy được cả local lẫn prod
- [x] Verify trên PRODUCTION: seed 8 tài xế thật → 36 sự kiện, 1.580 điểm mint, missions nổ (Bánh xe bền bỉ +40, Dấu chân đất Việt +80); AI insight `ai:true` câu chữ tự nhiên từ stats thật. Gotcha: Cloudflare bot-fight chặn UA python-urllib (403 code 1010) → script phải set UA
- [x] Fitness app KHÔNG bị ảnh hưởng: bảng mới riêng, chỉ mở rộng kind ledger; cargo test + clippy xanh

### 2026-07-11 (Giải khung giờ — Bình Minh 5-9h / Hoàng Hôn 18-22h)

- [x] **Migration 0010**: `race_windows` (dawn 5-9h 🌅, dusk 18-22h 🌆 — giờ VN, DB rows thêm/sửa giải không cần code) + `race_milestones` (500m +10 / 2km +25 / 5km +60 guild XP); `guild_xp_ledger.kind` mở rộng thêm `'race'`
- [x] **Luật chơi**: chỉ session SẠCH **bắt đầu trong khung giờ** mới tính; quãng đường **cộng dồn qua nhiều session** trong 1 lần mở; mỗi mốc vượt qua mint **XP cho hội** của runner (idempotent theo user+giải+mốc+ngày VN — mỗi thành viên đóng góp riêng). **Economy firewall giữ nguyên**: đua trả vinh quang hội, điểm cá nhân vẫn chỉ từ pipeline session thường; không hội thì vào BXH cho vui nhưng không mint
- [x] **`GET /v1/races`**: trạng thái mở/đóng + đếm ngược mở/đóng, tiến độ mốc của tôi, BXH live top 5 (tên che số). Settle hook best-effort sau `on_clean_session` (cạnh guild quests)
- [x] **iOS (tab Giải đấu)**: khung mở = card gradient (bình minh cam / hoàng hôn tím) với badge ĐANG MỞ pulse + đếm ngược đóng + 3 chip mốc tick + dẫn đầu + nút Vào đua → prerun; khung đóng = row teaser "mở sau XhYY'". Screenshot verify cả 2 trạng thái
- [x] Smoke 6/6 (window test 0-24h trong dev DB: mốc cộng dồn 2 session, idempotent, không hội không mint, guilds.xp khớp ledger); clippy + cargo test xanh; **đã deploy VPS** (migration tự chạy, /races live trên api.nullshift.sh) + cài iPhone

### 2026-07-10 (Tủ đồ nhím theo streak + sân khấu hologram)

- [x] **Tủ đồ nhím mở khoá theo `streak_current` server, cộng dồn** (trùng mốc celebration): 3 ngày khăn quàng xanh + đuôi khăn, 7 băng đô cam runner, 14 kính mát đen, 30 áo choàng tím, 50 hào quang lửa xoay. Caption động: đủ đồ hiện "chuỗi N ngày 🧣🎽😎🦸🔥", chưa có gì hiện teaser "chuỗi X ngày nữa là nhím có khăn quàng" — mồi giữ chuỗi tự nhiên
- [x] **Sân khấu hologram**: bệ đĩa glow xanh + 2 vòng ring (xanh trong, tím ngoài) pulse thở; vai xuôi mượt (thêm control rows), tay thon ôm thân hơn, wireframe nhẹ 0.15, camera nhỉnh lên
- [x] Hook QA `DEV_PET_STREAK=n` (DEBUG) xem trước tủ đồ; screenshot verify full-gear streak 50. Đã cài lên iPhone

### 2026-07-10 (Nhím Tím 3D — thú cưng nuôi bằng vận động)

- [x] **Nhím Tím 3D thuần SceneKit** đứng cạnh hologram cơ thể: thân cầu tím mũm mĩm (palette mascot 2D), mặt kem, mắt hạt cườm + glint, mũi, 26 gai nón rải bán cầu lưng (scatter deterministic — không random), 4 chân stub, idle bob thở nhè nhẹ (Reduce Motion → đứng yên)
- [x] **Cơ chế "nuôi": kích thước nhím = f(level server)** (0.72 + 0.045×level, cap 25) — chạy thật thì XP thật thì nhím lớn thật; **cấp ≥10 nhím đội vương miện vàng**. Caption: "Nhím Tím cấp N đồng hành — vận động mỗi ngày để nuôi nhím lớn 🌱"
- [x] Lighting tách lớp bằng categoryBitMask: đèn rim xanh/tím 750–900 chỉ chiếu hologram kim loại; nhím lambert có omni dịu riêng 320 — không bị cháy trắng. **2 bug đáng nhớ:** `0x7A / 255` là integer division = 0 → mọi màu thành đen (fix `255.0`); PBR matte dưới rig đèn hologram trắng bệch → pet dùng `.lambert` lấy diffuse literal
- [x] Đã cài lên iPhone

### 2026-07-10 (Hologram 3D cơ thể từ số đo)

- [x] **`Design/BodyModel3D.swift`** — SceneKit hologram trong màn Số đo cơ thể: figure param hoá (đầu/vai/thân + 2 chân + 2 tay loft từ profile nhân trắc), **eo và hông của mô hình co giãn theo số đo THẬT** (chu vi → bán trục ellipse → scale Gaussian quanh đúng cao độ eo/hông; khoảng cách 2 chân giãn theo hông). Quét lại eo nhỏ hơn → con 3D thon lại thấy được
- [x] **Render "ngầu" đúng yêu cầu:** sân khấu tím than (palette nghi lễ m01), mesh PBR metal tối + lưới wireframe glow xanh, đèn rim xanh+tím 2 bên, **tia scan chạy dọc người loop**, tự xoay 14s/vòng + kéo để xoay (allowsCameraControl); Reduce Motion → đứng yên, không beam
- [x] Guardrail giữ nguyên: hologram cách điệu chứ không phải ảnh cơ thể (caption ghi thẳng), không phán xét gầy/béo, mọi thứ on-device. SMPL v1.5 sau này thay geometry, giữ card. Hook mới `DEV_SCREEN=scanres`. Đã cài lên iPhone

### 2026-07-10 (Máy quét cơ thể THẬT — camera + Vision, on-device)

- [x] **`Core/ScanEngine.swift`**: Vision `VNGeneratePersonSegmentationRequest` (.accurate, chạy hoàn toàn trên máy, không model ngoài) → mask theo dòng (runs liên tục, lọc speckle) → **bề ngang eo (front) + bề dày eo (side)** tại cao độ nhân trắc học (eo 38% / hông 47% từ đỉnh đầu), chỉ đo run chứa tâm thân người (tay dang không lẫn vào số đo) → chu vi ellipse Ramanujan, quy đổi cm theo chiều cao user. Validation: không thấy người / người quá nhỏ trong khung (<50%) / kết quả phi lý → lỗi tiếng Việt + quét lại
- [x] **`ScanCamera`**: AVFoundation front camera thật + preview; xin quyền camera (NSCameraUsageDescription); ảnh chỉ ở RAM (`app.scanFront/scanSide`), xoá ngay sau khi đo — mọi claim privacy giờ ĐÚNG
- [x] **Flow**: intro (quét = CTA chính trở lại, thước dây = phụ) → hỏi chiều cao 1 lần (lưu máy) → tư thế 1 chính diện tay dang / tư thế 2 xoay ngang tay khoanh, mỗi tư thế đếm ngược 10s (tick haptic 3s cuối) + flash + haptic khi chụp → màn đo chạy THẬT (progress theo milestone thật: tách bóng → đo → bỏ ảnh) → kết quả ghi store nguồn `"scan"`, badge "từ máy quét", chỉnh tay được (ghi đè nguồn `"manual"`)
- [x] Sai số vài cm ghi rõ ở intro + processing + màn kết quả — là ước tính hình bóng, không phải SMPL; engine v1.5 (MediaPipe+SMPL) thay phần toán, giữ nguyên flow. Simulator không có camera → fallback tử tế (mở Cài đặt / nhập thước dây). Đã cài lên iPhone — cần test người thật đứng 2–3m

### 2026-07-10 (Body scan: dẹp theater, nói thật)

- [x] **Audit theo câu hỏi của founder "quét cơ thể có hardcode không":** số đo = THẬT (tự nhập thước dây, lưu on-device, delta + tỷ lệ eo–hông tính thật); nhưng camera = KỊCH — không hề mở camera, "Đang đo 87%" là timer, và claim "Xoá ảnh gốc khỏi máy" trong khi chưa từng chụp (fake privacy claim = poison cho con hào privacy — user tinh ý thấy app không xin quyền camera là mất trust)
- [x] **Fix theo pattern Zalo "sắp ra mắt":** ScanIntro viết lại — nút chính = "Nhập số đo (thước dây)" (tính năng thật hôm nay), quét camera thành teaser card "Sắp ra mắt · Core ML đang hoàn thiện"; 3 bullet privacy giữ lại toàn câu ĐÚNG (chỉ lưu trên iPhone / không ai thấy / không chấm điểm cơ thể — guardrail #4); title "Kết quả quét" → "Số đo cơ thể". Màn cam/processing (design v1.5) giữ nguyên sau `DEV_SCREEN=scancam` cho design QA — không user nào lạc vào được
- [x] Đã cài lên iPhone. Việc v1.5 không đổi: MediaPipe pose + SMPL fitting, on-device

### 2026-07-10 (Fix giữ-để-kết-thúc không ăn trên máy thật)

- [x] **Gốc rễ:** `onLongPressGesture` tự huỷ khi ngón tay xê dịch >10pt — tay run sau khi vận động là cancel hoài nên ring không bao giờ đầy. Simulator/XCUITest "giữ" đứng yên tuyệt đối nên test vẫn xanh — bug chỉ lộ trên máy thật. Fix: `DragGesture(minimumDistance: 0)` bắt finger down/up thô (cho phép rung tay), **timer tự quyết mốc 3s** (haptic heavy khi đủ) thay vì để gesture quyết
- [x] **Polish kèm:** trạng thái "Đang chốt…" (ring đầy + spinner) khi đang gửi server (finish flush-wait tới 5s trên mạng thật — trước đây nhìn như đơ); finish fail → **retry 3 lần backoff**, vẫn fail thì Ở LẠI màn chạy + báo "giữ nút lần nữa" thay vì âm thầm văng về home (nhìn như mất buổi chạy — session server vẫn mở, giữ lại là chốt tiếp); nút pause/khoá đóng băng khi đang chốt
- [x] testRunLoop pass 175s (press 3.6s vẫn ăn với gesture mới); đã cài lên iPhone

### 2026-07-10 (Bước chân live cho đi bộ)

- [x] **RunTracker publish `steps`** từ CMPedometer `numberOfSteps` — cùng 1 stream pedometer vừa hiện UI vừa stamp cadence lên từng điểm GPS cho anti-cheat (gate mở rộng: isStepCountingAvailable HOẶC isCadenceAvailable); reset mỗi buổi
- [x] **Màn đi bộ**: cột giữa = **Bước chân** (đi bộ thì bước chân quan trọng hơn pace); chạy bộ giữ Nhịp độ /km. **Cờ mốc mỗi 1.000 bước** cho đi bộ (haptic + pill 2s, cùng chỗ với cờ km của chạy bộ). Summary: đi bộ hiện Bước chân thay Nhịp độ TB (bước là số local của máy — server chỉ nhận cadence)
- [x] Ghi chú: simulator không có pedometer → luôn 0; số thật chỉ nhảy trên iPhone. testRunLoop pass 174.9s; đã cài lên iPhone

### 2026-07-10 (Quét cả họ bug stale-state — "unknown device_id" và bạn bè)

- [x] **Gốc rễ: cả Keychain LẪN UserDefaults sống sót qua cài đè app** → mọi state gắn với (user, server) đều có thể "mồ côi" khi backend đổi. Kiểm kê đủ: token (đã fix trước), `device.id` (gây "unknown device_id"), `guardian.linked`, `seen.*` baseline; `body.measures` giữ nguyên chủ đích (on-device by design, không gắn server)
- [x] **Force-logout giờ wipe đúng bằng logout thường** (`wipeLocalSession()` dùng chung) — lỗ hổng là chính đường authSessionExpired mới thêm chỉ xoá token, để lại device.id cũ cho user dính tiếp
- [x] **Self-heal khi bấm bắt đầu** (PrerunView): 400 "unknown device_id" → đăng ký device mới + retry 1 lần; 400 "open session already exists" (app bị kill giữa buổi → session kẹt trên server chặn vĩnh viễn) → tự discard session kẹt + retry. Kèm NSLog `[heal]` để debug field
- [x] **Backend: caps ghi-khi-thành-công** — trước đây create fail (session kẹt) vẫn đốt cooldown 30s nên retry heal sẽ dính 429; giờ `check_create_caps` (read-only) trước insert + `record_create` sau khi thành công. m3 smoke 6/6 (cooldown sau create thành công vẫn 429 đúng), 29 unit tests xanh. Đã deploy bản này lên VPS
- [x] Verify heal trên simulator: session kẹt → bấm start → discard + retry → vào màn chạy trong ~1s (chứng minh luôn caps fix); device-id heal chạy đúng nhánh (lần fail duy nhất là artifact của harness — `simctl spawn defaults write` ghi vào domain ngoài container mà app không xoá được; máy thật không thể gặp vì app tự ghi key trong container của nó)
- [x] Bonus map: fix camera không snap zoom 16 khi fix đầu trùng toạ độ fallback (flag `centeredOnce`)

### 2026-07-10 (Fix 401 sau deploy + map thật từ NullMaps)

- [x] **Fix "unauthorized" khi bấm bắt đầu trên iPhone:** 2 nguyên nhân gốc — (1) Keychain iOS **sống sót qua cài đè app** nên token của backend cũ (Mac LAN) còn nguyên, app bỏ qua login và gọi server mới bằng token lạ; (2) access token hết hạn **15 phút** mà client chưa hề có logic refresh. Fix trong `APIClient`: 401 → **refresh single-flight** (actor `RefreshCoordinator` — rotation thu hồi token cũ nên 2 refresh song song = reuse-detection, phải gom về 1) → retry đúng 1 lần; refresh bị 401 dứt khoát → xoá token + notification `authSessionExpired` → `AuthStore` về màn login. Mạng chập chờn lúc refresh KHÔNG đá user ra (chỉ 401 thật mới xoá token)
- [x] **Map thật thay map vẽ tay:** MapLibre Native (SPM 6.27) + style tự host `maps.nullshift.sh` (`style.json`/`style-dark.json` — public read-only, key chỉ chắn route/geocode API). `Design/NullMap.swift`: camera follow fix đầu (snap zoom 16 kể cả khi fix trùng camera fallback), polyline route xanh #34B37D qua MLNShapeSource, fit-bounds cho summary. `RunTracker` nhả `currentCoordinate` + `route` (fix sạch ≤50m, thin 3m). **Prerun** = map sáng + marker ripple design gốc đè lên; **Summary** = route thật fit khung + cờ đích (doodle giữ làm fallback khi không có track). Màn Run giữ nguyên stats tối theo design — không chế thêm
- [x] Verify: screenshot prerun (Sài Gòn, label tiếng Việt) + summary (Hồ Gươm + polyline track sim); **testRunLoop 177s pass** (full loop prerun→GPS→finish→summary với cả 2 thay đổi), testRedeemVoucher + testPhoneEntry pass; cài lên iPhone

### 2026-07-10 (Deploy lên VPS — api.nullshift.sh + run.nullshift.sh)

- [x] **Backend deploy lên VPS Hostinger dùng chung** (srv1589451, ~50 tenant containers): cross-compile trên Mac bằng `cargo zigbuild --target x86_64-unknown-linux-musl` (binary tĩnh 8.8MB, 94s) → scp → docker build **COPY-only** trên box → compose tại `/opt/null-run` (TimescaleDB + Redis + backend loopback `:8500`, mem limits, secrets sinh mới trong `.env` chmod 600). **Tuyệt đối không build Rust/npm trên box** — box này từng sập vì build nặng (ghi trong config.txt của founder)
- [x] **Web deploy**: Next.js `output: "standalone"` build trên Mac (baked `NEXT_PUBLIC_API_BASE=https://api.nullshift.sh`) → tarball → node:20-alpine COPY-only, loopback `:3500`
- [x] **Caddy fragment** `/etc/caddy/conf.d/null-run.caddy` (validate + reload nhẹ, không đụng ~15 tenant khác): `api.nullshift.sh` → 8500, `run.nullshift.sh` → 3500; routing verify bằng Host-header (308 → https đúng)
- [x] **Smoke trên box**: health db+redis ok, migrations tự chạy, seed đủ (2 challenges/4 rewards/15 games/3+6 quest defs/6 wheel), full flow OTP → token → points/games/quests/guilds chạy ngon
- [x] **DNS live**: founder đưa token CF mới → tạo A record `api` + `run` (proxied). Gotcha học được: host thêm vào Caddy TRƯỚC khi DNS tồn tại thì ACME nằm backoff (525 hoài) — `systemctl reload caddy` sau khi DNS sống là cert cấp liền. Verify: `https://api.nullshift.sh/health` 200 + `https://run.nullshift.sh` 200
- [x] iOS device build đổi `API_BASE_URL` → `https://api.nullshift.sh`, rebuild + cài lên iPhone — **app chạy mọi nơi, không cần chung wifi với Mac nữa**

### 2026-07-10 (Guild "Hội" live — backend + quest ngày/tuần + màn hình polish)

- [x] **Backend guilds (migration 0009):** `guilds` (tên unique không phân hoa thường, emblem, mã mời 6 ký tự, link Zalo, XP) + `guild_members` (1 hội/người — unique index, role leader/member) + `guild_quest_defs` (**6 quest seed trong DB**: 3 daily + 3 weekly, chỉnh không cần code) + `guild_xp_ledger` (append-only, idempotent). Endpoints: `POST /v1/guilds`, `join` (code hoặc id từ discovery), `GET mine`, `PATCH mine/settings` (leader), `leave`, `discover`
- [x] **Quest engine hội:** cửa sổ ngày/tuần VN, target scale theo sĩ số (`per_member`), metric `members_active` theo tỷ lệ (ceil); **chỉ session SẠCH ghi sau khi join mới tính** (`GREATEST(window, joined_at)` — chống mang km cũ vào hội); XP mint idempotent theo (hội, quest, ngày VN/tuần ISO) qua UUIDv5; settle hook trong `on_clean_session` (best-effort) + lazy khi GET mine
- [x] **Lối chơi xã hội đúng spec:** leader rời hội → chuyển quyền cho thành viên lâu nhất; hội trống tự giải tán (tên được giải phóng); discovery **chỉ hiện hội còn hoạt động 7 ngày** (hội mới có grace 7 ngày), hội đầy bị ẩn
- [x] **GuildView rebuild toàn bộ:** chưa có hội = hero + join mã + **khám phá hội đang hoạt động** + 3 nguyên tắc; có hội = hero tím (emblem popIn, XP bar vàng lên cấp hội, **mã mời bấm-để-copy**, đếm người vận động hôm nay với dot pulse), card **Chat hội trên Zalo** (mở link — app không xây chat, đúng do-NOT list), quest ngày/tuần với progress bar + pill XP + confetti khi quest hoàn thành ngay trên màn, danh sách thành viên với **ring đóng góp = % mục tiêu tuần CÁ NHÂN** (nguyên tắc không bêu km) + crown leader + dot active; sheet tạo hội (emoji picker, autofocus tên) + sheet cài đặt leader; motion kit đầy đủ (riseIn/popIn/shineSweep/haptics)
- [x] **Bug bắt được:** Swift `convertFromSnakeCase` biến `active_7d` → `active7D` (số làm hoa chữ sau) → decode fail lặng lẽ → discovery luôn rỗng. Fix: đổi tên field `active_week`. Bài học: tránh chữ số ngay sau `_` trong JSON field
- [x] Smoke 12/12 (tạo/join/discover/quest XP idempotent/firewall/chuyển leader/giải tán); cargo 29 tests + clippy sạch; screenshot verify cả 3 state (lobby + hero&quest ngày + tuần&thành viên)

### 2026-07-10 (ULTIMATE animation pass — theo dd6 motion spec + m01)

- [x] **Motion kit (`Design/Motion.swift`) đúng dd6:** count-up 600ms với haptic tick dồn mỗi ~40ms, confetti 900ms + haptic success, badge pop 350ms overshoot + ring 500ms + haptic light, shine sweep, rise-in stagger, ConfettiRain loop cho nghi lễ; **Reduce Motion → mọi spring/confetti thành fade 150ms** (đúng spec); màn số đo cơ thể giữ tĩnh tuyệt đối ("cơ thể không phải trò chơi")
- [x] **3 nghi lễ ăn mừng data-driven** (`CelebrationViews.swift`): thăng hạng mùa = **nghi lễ vàng m01** (sân khấu tím #1D1830, khiên vàng shine, mascot, spring 800ms + haptic heavy, hiện đúng 1 lần), lên cấp = badge pop + mascot cheer, mốc chuỗi (3/7/14/21/30/50/100) = lửa bùng. Phát hiện qua delta tier/level/streak giữa các refresh (baseline per-user, clear khi logout — không ăn mừng nhầm khi đổi user)
- [x] **Rắc động toàn app:** Home stagger 8 card + đốm sáng bay quanh ring tuần; Summary shine sweep + pop + haptic success; Wheel tick haptic giảm dần theo 4.2s + heavy lúc ra giải; Run hold-để-kết-thúc chuẩn 3s + thả sớm tháo lui 250ms + haptic mốc km; Duel haptic heavy khi trận kết thúc; tab bar bounce + haptic; ProgressRing fill 500ms khi mở màn
- [x] **Admin adjust endpoint** (`POST /v1/admin/users/{phone}/adjust`) — công cụ ops đền bù/điều chỉnh điểm, ledger `admin_adjust` auditable (test harness cũng dùng để top-up user demo)
- [x] UI tests 3/3 pass (2 lần fail trước = balance user demo cạn + cửa sổ GPS-sim của harness, không phải bug app); backend clippy + 29 tests xanh

### 2026-07-10 (games từ xlsx + PvP duel + audit hardcode lần 2)

- [x] **15 wellness games từ `NullShift - Games.xlsx` vào DB** (migration 0008, bảng `games`): 3 tier Easy/Medium/Hard, 3 lớp xác minh — `auto_*` (GPS distance/duration/streak, server tự verify), `sensor_steps` (pedometer + thiết bị attested), `self` (tự khai, thưởng nhỏ, **cap 3 lượt/ngày, chỉ lượt thành công mới trừ cap** — bug đốt cap bởi claim fail đã bắt qua smoke). Reward scale 1/10 token sheet (5/15/30/100) để khớp economy — chỉnh từng dòng trong DB được. Ledger kind mới `game_reward`
- [x] **PvP duel 1v1** (bảng `duels` + `activity_sessions.duel_id`): tạo trận nhận mã 6 ký tự → đối thủ join → mỗi người chạy 1 session gắn trận → **người thắng = người có track GPS (đã lọc) cán mốc 500m sớm nhất theo timestamp**, không phải ai poll trước; settle idempotent, mint `duel_win` +25. Smoke 13/13: "Tốc Độ" 3.4m/s thắng "Bền Bỉ" 2.8m/s đúng kịch bản
- [x] **Audit hardcode lần 2:** quest defs → bảng `quest_defs`; wheel segments+weights → bảng `wheel_segments`; level/XP formula → server trả `level`/`xp_in_level`/`xp_per_level`; league title header còn sót → tier-driven. iOS: GamesView (claim + progress pedometer) + DuelView (lobby/mã/race 2 làn poll 3s/kết quả) + entry từ Home & League
- [x] UI tests 3/3 pass (fail đầu của runLoop = GPS-sim harness hết giờ, không phải app). Bản device đã build sẵn — iPhone đang rời cáp, cắm lại là cài

### 2026-07-10 (de-hardcode pass — mọi tính năng chạy data thật)

- [x] **Backend (migration 0007 + module quests/wheel):** daily quests server-verified (3 nhiệm vụ tính từ session sạch + ledger, mint +5/quest, idempotent theo ngày VN qua UUID v5); **lucky wheel server-side** (mở khi có buổi tập sạch trong ngày, 1 lượt/ngày, giải thưởng server chốt trước khi quay, mint `wheel_prize` — không đụng leaderboard); XP = `lifetime_earned` từ ledger (không cột mới); `weekly_goal_km` chỉnh được (PATCH /v1/me, 5–200) + `weekly_km` server tính (session sạch, tuần VN); voucher có `expires_at` thật (90 ngày). Ledger kinds mới: `quest_reward`, `wheel_prize`
- [x] **iOS:** quests card + wheel banner + WheelView chạy hoàn toàn bằng API (wheel quay tới đúng segment server trả về); level/XP từ lifetime_earned; ring mục tiêu tuần server-side + chạm để đổi goal; HSD voucher thật; greeting dùng display_name; league title theo tier (Đồng/Bạc/Vàng/Bạch Kim); **scan bỏ số demo** → nhập số đo thước dây, lưu on-device (đúng privacy story), delta so lần trước, tự tính WHR
- [x] **Verified:** curl smoke (quests progress đúng, wheel spin mint 50 + chặn lượt 2, goal 30km, lifetime 96); **3/3 UI tests pass** (run loop 175s với quests settle trong finish; redeem voucher 10K mới tạo qua admin API; login flow với DEV_FORCE_LOGOUT hook). Phát hiện sống: user chạm daily cap 300 → run mới +0 điểm (đúng luật, không phải bug)
- [x] Hardcode còn lại (có chủ đích, đã đánh dấu trong app): Zalo/Apple OAuth "sắp ra mắt", Hội teaser (backend guild = v1.5), máy quét Core ML (v1.5) — số đo giờ là thật, nhập tay

### 2026-07-10 (design implementation, phần 2)

- [x] **4 màn còn thiếu** từ file design thứ hai (`docs/design/null-run-full-screens.html`, import qua DesignSync — bị cap 256KB nên s20–s22 Hội cụt): **Splash** (brand block, không có trong design — tối giản từ s02), **Login s02** (logo run-path, Zalo/Apple đúng visual nhưng "Sắp ra mắt" chờ OAuth — phone/OTP là đường chạy thật, restyle theo design system), **Giải đấu s11** (vùng thăng hạng/xuống hạng có hatch đỏ, me-row viền gạch, data thật từ `/v1/league`, empty-state có mascot), **Hội teaser** (hero + 3 nguyên tắc từ section Hội nhóm; CTA khoá — guardrail "no empty guilds"). Cả 5 tab đã enable
- [x] Screenshot-verified trên simulator với league seed 5 user chạy sạch (điểm thật 77/61/46/35/23); dev hook mới `DEV_SCREEN=league|guild|rewards|wheel` (DEBUG) để QA từng màn

### 2026-07-10 (design implementation)

- [x] **iOS APP TỪ DESIGN — VERIFIED END-TO-END TRÊN SIMULATOR.** Founder's Claude Design prototype imported via DesignSync (`docs/design/null-run-prototype.html`) and implemented as 12 SwiftUI screens: Home (mascot, streak pill, weekly-goal ring, quests, level XP, league card, wheel banner), Prerun (GPS map + ripple), Run + Locked (dark, mono 104pt distance, hold-to-finish ring, slide-unlock), Summary (confetti, count-up, verified badge, splits), Rewards (ticket vouchers, redeem sheet), Voucher (barcode), Wheel, Scan ×4. Design system: Be Vietnam Pro + IBM Plex Mono bundled, exact prototype hex palette, hedgehog mascot drawn in SwiftUI paths
- [x] **XCUITest suite (2 tests) PASSED against live backend:** simulated GPS run (~2.5 min, jittered 3 m/s) → server verdict **clean, fraud_score 0.0**, distance 439 m server-computed; redeem flow → 20K voucher **fulfilled `GRD-SCWS-NHR5`**, balance 300→100. Dev auto-login via `DEV_AUTOLOGIN_PHONE` env (DEBUG-only, uses sms_mode=log debug code)
- [x] Backend: `/v1/me/points` now returns `today_earned` (home screen "Điểm hôm nay")
- [x] Gotcha fixed: `CODE_SIGNING_ALLOWED=NO` breaks simulator Keychain (all authed calls 401) — build with default ad-hoc signing

### 2026-07-10

- [x] **M6 VERIFIED** — backend: 10-case smoke green (bad token 401; two moped-walk sessions quarantined → queue lists both with flags+phone; **approve → clean + 39 pts minted through the normal pipeline, reject → buried 0 pts**; re-review 404; stats sane; lookup by phone incl. devices/attest; challenge+reward CRUD with deactivate hiding from catalog; partner stats). Web: Next.js 15 builds clean, all 3 pages serve 200 with content on :3100 (3000 occupied by another local app)
- [x] **M6** Admin APIs (`src/admin/`): AdminAuth/PartnerAuth extractors (static tokens), stats, review-queue, session review, user lookup, challenge/reward CRUD, partner stats; CORS permissive for local dashboard
- [x] **M6** `web/`: hand-rolled Next.js 15 scaffold (no create-next-app), landing (VN copy), /admin console (stats grid, review queue approve/reject, user lookup), /partner dashboard (redemptions, actives, challenge performance); tokens via localStorage
- [x] **M5 backend VERIFIED — FULL v1 LOOP CLOSES: run → points → Guardian voucher.** 12-case smoke green: catalog; redeem blocked without link (400); invalid member id (400); insufficient balance (400); clean run 44 pts → sticker redeemed (voucher `GRD-…`, balance 19); **idempotency replay returns same redemption, no double spend**; stock=1 reward sells once then 400; my-vouchers list; member-id unique across accounts; reconciliation totals correct + bad token 401
- [x] **M5** Migration 0006 (rewards, redemptions + idem index, guardian link cols, `redemption_refund` ledger kind, balance ≥ 0 constraint, 4 seed rewards); partner adapter layer with GuardianMock; endpoints `/v1/rewards[/{id}/redeem]`, `/v1/redemptions`, `/v1/guardian/link`, `/v1/partner/reconciliation`
- [x] **M4 backend VERIFIED** — 10-case smoke suite green: clean 3 km run → 44 pts + 50 challenge bonus, balance/tier/streak correct; **GPS-spoof bot → rejected → 0 points (core guardrail holds end-to-end)**; 25 km run capped at 300/day (base 374); weekly leaderboard ranks G(300) > E(44) with fraudster unranked; league bucket 0 holds both clean users; challenge auto-completed in-transaction
- [x] **M4** Gamification: migration 0005 (points_ledger append-only + idempotent mint index, streak cols, challenges), `rules.rs` (versioned formula, tiers, VN season/week/day keys), `on_clean_session` (transactional mint+streak+challenges, best-effort Redis leaderboards), 5 endpoints; finish returns `points_earned`/`challenge_bonus`
- [x] **M3→M4 guardrail wired:** `finish` calls the mint ONLY when `verdict='clean'` — genuine-only earning is now enforced at the ledger, closing M3's open checkbox

### 2026-07-09

- [x] **M3 VERIFIED** — 6-persona smoke suite green: realistic jittered run + attested device → `clean` (score 0); scripted GPS-spoof (uniform motion, zero cadence, no device) → `rejected` (score 1.0, 3 flags); "walk" at moped speed → `suspicious`; rapid session creation → 429; attest-key reuse on 2nd account → 400; foreign device_id → 400
- [x] **M3** Fraud engine (`activities/fraud.rs`): 7 weighted signals (unattested device, teleport ratio, implausible avg speed per type, no-cadence-while-moving, uniform motion profile, junk accuracy, absurd totals) → verdict at finish; 8 unit tests. Weights sum >1 by design so stacked medium flags reach quarantine
- [x] **M3** Rate caps on create: 30 s cooldown + 20 sessions/day (Redis); caps enforced AFTER cheap validation so a failed request doesn't burn the cooldown
- [x] **M3** Migration 0004: fraud_score, fraud_flags[], verdict + partial index as the M6 review queue
- [x] **M3** Smoke test caught a real bug: duplicate attest_key_id returned 500 → now 400 (reuse across accounts is exactly the attack the unique index blocks)
- [x] **M2 backend VERIFIED** — 14-case smoke suite green: simulated 1.8 km run through the full pipeline (create → 123 points in 3 batches via Redis stream → worker → Timescale → finish) computed exactly 1800 m / 600 s moving / 333 s/km with a teleport fix and a 900 m-accuracy fix filtered out; lifecycle transitions, one-open-session rule, cross-user isolation (404), batch validation all correct
- [x] **M2** Activity engine: migration 0003 (activity_sessions + gps_points hypertable), ingestion worker (XREAD → UNNEST insert → cursor → XTRIM), stats computation with 7 unit tests, endpoints create/list/detail/points/pause/resume/finish/discard
- [x] **M1 iOS VERIFIED** — Xcode 16.2 landed: `xcodegen generate` + build succeeded FIRST TRY (zero errors/warnings), app launched on iPhone 16 Pro sim (iOS 18.3), onboarding screen renders with VN copy; screenshot confirmed
- [x] **M1 backend VERIFIED** — 17-case curl smoke suite green: OTP request/one-time/rate-limit(429)/wrong-code(401), token issue, /me auth+validation, attest challenge→register (dev mode), refresh rotation + old-token rejection, logout revocation
- [x] **M1** iOS scaffold (UNBUILT — no Xcode here): `ios/project.yml` (XcodeGen, background-location mode, App Attest entitlement, VN permission copy), onboarding phone→OTP, permission priming (When-In-Use→Always two-step), `APIClient`/`AuthStore`/`Keychain`
- [x] **M1** Devices: attest challenge nonce (Redis 5-min TTL) + register endpoint; `ATTEST_MODE=dev` accepts unverified (real Apple verification blocked on physical-device build)
- [x] **M1** Profile: `GET/PATCH /v1/me` with `AuthUser` JWT extractor + validator
- [x] **M1** Auth: VN phone normalization (unit-tested), OTP via Redis (hashed, 5-min TTL, 3 req/15 min, 5 attempts), JWT access (15 min) + rotating hashed refresh tokens (30 days), logout
- [x] **M1** Migration 0002: users, devices (attest fields), refresh_tokens
- [x] **M0 COMPLETE** — verified end-to-end: containers healthy, migrations applied, `/health` → `{"db":true,"redis":true,"status":"ok"}`, JSON 404 fallback, fmt/clippy/test all green
- [x] **M0** CI workflow (`.github/workflows/ci.yml`): fmt --check, clippy -D warnings, test; runs without services
- [x] **M0** Backend data layer wired: sqlx (lazy→fail-fast pool) + migrate-on-startup (`0001_extensions.sql`: timescaledb, pgcrypto), fred Redis client with reconnect policy, validator
- [x] **M0** Backend structure: `config.rs` (env + defaults), `error.rs` (`AppError` → JSON responses), `state.rs` (`AppState`), `routes/` (health with real db+redis probes), tower-http TraceLayer
- [x] **M0** `docker-compose.yml`: timescale/timescaledb:latest-pg16 + redis:7-alpine, healthchecks, persistent volumes. Host ports **5433/6380** (this machine runs its own Postgres/Redis on 5432/6379 — hit this exact conflict during smoke test)
- [x] **M0** Repo initialized (`main` branch), monorepo layout: `backend/` `ios/` `web/` `docs/`
- [x] **M0** `CLAUDE.md` written from spec (`docs/init-prompt.md`): locked decisions, guardrails, sequencing, do-NOT list
- [x] **M0** Backend scaffold: Rust + Axum + tokio + tracing; `GET /health` verified running on `:8080`
- [x] **M0** `plan.md` (this v1 plan) + `progress.md` created
- [x] **M0** README, .gitignore

## Blockers / open items

- ❗ **Guardian (Hội Cam) API / BD access** — gates M5 product shape. Mitigation in plan: partner-adapter interface + mock adapter. Owner: founder/BD. Status: open since project start.

## Decisions made along the way

- 2026-07-10 — **Dark mode = kẻ thù số 1 của design light-only:** chữ mặc định (.primary) thành trắng trên nền kem → vô hình. Fix tận gốc: `foregroundStyle(Theme.ink)` cascade ở RootView (+ darkInk cho màn dark trong MainView), sheet là presentation riêng phải set lại `preferredColorScheme(.light)` + ink. Mọi Text mới không set màu sẽ tự ăn ink — an toàn mặc định.
- 2026-07-10 — **OTP cố định `123456` khi `sms_mode=log`** — test trên iPhone thật khỏi đọc server log; SMS provider thật sẽ trả về random.
- 2026-07-10 — **App Attest entitlement tạm gỡ khỏi project.yml** — free Personal Team (chưa có Apple Developer trả phí) không provision được DeviceCheck entitlement; `ATTEST_MODE=dev` không cần nó. Khôi phục khi có tài khoản trả phí (bắt buộc cho attest thật). Device builds gọi backend qua `API_BASE_URL` trong Info.plist (IP LAN của Mac, hiện 192.168.3.93) + ATS `NSAllowsLocalNetworking`.

_(Record deviations from `docs/init-prompt.md` here, with date + why.)_

- 2026-07-09 — **Redis client: `fred` (over `redis`)** — spec allowed either; fred's typed interfaces suit the sorted-set-heavy leaderboard work in M4.
- 2026-07-09 — **Migrations run on startup** (embedded via `sqlx::migrate!`) instead of a separate sqlx-cli step — one less tool for dev loop; revisit for prod deploy strategy in M7.
- 2026-07-09 — **Docker host ports 5433/6380** instead of defaults — dev machine already runs Postgres/Redis on 5432/6379.
- 2026-07-09 — **Phone/OTP over Sign in with Apple** for v1 auth — VN mass market is phone-first; SIWA can come later as an alternate method.
- 2026-07-09 — **`ATTEST_MODE=dev` + `sms_mode=log`** — both are explicit dev stubs (attestation accepted unverified; OTP echoed in response). Both MUST be replaced before any external user: real SMS provider, full App Attest verification. Tracked as open M1 checkboxes in plan.md.
- 2026-07-09 — **Refresh-token reuse → plain 401** (no revoke-all-sessions on reuse detection yet) — acceptable pre-beta; harden in M7.
- 2026-07-09 — **GPS ingestion: single-consumer XREAD + cursor** (not consumer groups) — backend deploys as one instance; at-least-once via cursor-after-insert + PK dedup. Move to consumer groups when horizontally scaled.
- 2026-07-09 — **Finish flush-wait**: `finish` polls the ingest cursor (max 5 s) before computing stats so trailing points land; on timeout it proceeds and logs — stats can be marginally low, never inflated.
- 2026-07-09 — **Routing quirk**: axum `nest("/v1/activities")` + inner `"/"` matches `/v1/activities` (NO trailing slash); `/v1/activities/` 404s. Clients must use no-slash paths.
- 2026-07-09 — **Fraud verdicts are advisory until M4** — sessions store `clean|suspicious|rejected` but nothing consumes them yet; the points ledger (M4) is the enforcement point (mint only from `clean`). Suspicious ≠ deleted: quarantined for M6 review.
- 2026-07-09 — **Fraud thresholds are launch guesses** (suspicious ≥0.30, rejected ≥0.70; walk cap 2.5 m/s, run cap 6.0 m/s sustained) — tune against real beta data in M7; false-positive rate on genuine users is the metric to watch.
- 2026-07-10 — **Streaks are strict** (one VN-calendar-day credit, no freeze/grace in v1) — freezes become a v1.x shop item; simpler to launch strict and loosen than the reverse.
- 2026-07-10 — **Leaderboard/league rank on activity points only** — challenge bonuses pay balance but not rank, so time-boxed challenge stacking can't buy leaderboard position.
- 2026-07-10 — **Economy numbers are launch guesses** (10/15 pts per km, 300/day cap, tier thresholds 1k/5k/15k per quarter) — revisit when Guardian reward economics (M5) fix the real-money value of a point; faucet must stay below reward budget.
- 2026-07-10 — **League buckets are naive fill-order (50/bucket, first-earn-of-week)** — real matchmaking on true activity level is required BEFORE any league reward pays out (guardrail #3); fine while leagues are cosmetic.
- 2026-07-10 — **Redemption = reserve-then-fulfill**: points+stock reserved in a tx, partner call outside it, refund path on failure. With the mock this never fires; the real Guardian adapter must keep this shape (network calls don't belong in DB transactions).
- 2026-07-10 — **Guardian member-id format is a guess** (6–16 digits) until BD access; linking is required before redeeming — that link is the B2B2C data story.
- 2026-07-10 — **Reconciliation endpoint uses a static token** (`PARTNER_API_TOKEN`) — placeholder until real partner auth.
- 2026-07-10 — **Admin/partner auth = static tokens, CORS = permissive** — acceptable while only founders operate it locally; MUST harden before deploy (M7 checklist). Admin approve mints via the same idempotent `on_clean_session` pipeline, so a double-click can't double-mint.
- 2026-07-10 — **Web dev server runs on :3100** — this machine already has another Next.js app on :3000.
- 2026-07-10 — **Prototype mechanics without backends run client-local, marked as such:** quests (+5 labels), XP/levels, lucky wheel (always lands +50 like the prototype), body-scan results (demo numbers). They render exactly per design; their real backends are v1.x (wheel/quests) and v1.5 (scan). Wheel points do NOT touch the real balance — only local XP.
- 2026-07-10 — **Live in-run points are a client-side estimate** mirroring rules v1; the summary and balance always show server-minted numbers. Run < 500 m mints 0 (min-distance rule) — expected.
- 2026-07-10 — **Deploy lên Hostinger VPS dùng chung thay vì Hetzner+Coolify** (spec M7 ghi Hetzner) — founder chỉ định VPS có sẵn qua config.txt; hạ tầng dùng chung với ~50 app khác nên quy tắc số 1: không build trên box, image chỉ COPY artifact build sẵn từ Mac. Đây là staging: sms_mode=log (OTP lộ trong response!) + ATTEST_MODE=dev + CORS permissive — KHÔNG mời user thật cho tới khi có SMS provider + App Attest.
- 2026-07-10 — **Guild kéo lên sớm từ v1.5 nhưng CHỈ với XP cosmetic** — spec cấm guild reward trước anti-sybil đầy đủ, nên quest hội mint **guild XP** (cấp hội, vinh quang) chứ tuyệt đối không mint điểm cá nhân/quà Guardian (economy firewall — guardrail #5 giữ nguyên). Anti-sybil-lite đang có: 1 hội/người, 1 lượt tạo/ngày, chỉ session sạch sau khi join mới tính. Khi nào guild XP đổi được thứ có giá trị thật thì anti-sybil đầy đủ (trust-weight, anomaly detection) là điều kiện chặn — guardrail #2.
- 2026-07-10 — **iOS simulator dev flow:** build with normal ad-hoc signing (NEVER `CODE_SIGNING_ALLOWED=NO` — breaks Keychain → 401s), grant `simctl privacy … location-always`, drive GPS with `scratchpad gps_sim`-style `simctl location set` loops (jittered — uniform tracks trip the fraud engine, correctly).
- 2026-07-11 — **Body-scan 3D "hologram" nâng cấp theo ảnh reference của founder** (v1.5 scan vẫn client-local, đây là card kết quả demo): thân wireframe phát sáng + da gradient teal→tím, bệ holo tròn 2 vòng sáng, tia quét dọc, hạt bụi bay, nhím tím đồng hành. Bài học SceneKit: `.constant` lighting KHÔNG chiếu diffuse texture (chiếu từ ambient → ảnh gradient ra trắng bệt); phải đưa gradient qua `emission`. Và wireframe phải THƯA (loft 22×14) — mesh dày 64×36 khiến các đường additive gộp thành mảng cyan + bloom clip cả thân thành trắng. Không có số cân nặng tuyệt đối nào (guardrail #4), số đo chỉ lưu trên máy (guardrail #7).
- 2026-07-11 — **Pitch deck + demo script cho track VETC** (`docs/pitch/null-run-deck.html` + `docs/demo-script.md`, deck cũng publish thành claude.ai artifact): deck self-contained, on-brand (Be Vietnam Pro subset + palette Theme, cả 2 theme sáng/tối, không phụ thuộc external), nội dung visible không cần JS (reveal chỉ là enhancement); demo script 3 phút bám màn hình/endpoint thật + checklist + fallback.
- 2026-07-11 — **AI coach hiện trong app tiêu dùng** (deviation có chủ đích: spec ghi "v1 ZERO AI", nhưng track là "AI-Powered Gamification" và founder yêu cầu): `GET /v1/me/insight` dùng lại `ai.rs` (kiến trúc khoá) — model CHỈ diễn đạt số liệu THẬT (km tuần/mục tiêu/chuỗi/tier), KHÔNG bịa số; system prompt cấm nhắc cân nặng/hình thể/"ít hơn là tốt hơn" (guardrail #4); fallback template khi không có AI key (demo không chết vì thiếu key); **KHÔNG mint gì** (economy firewall — chỉ là copy). iOS: card "AI coach" tím trên Home, badge "AI" khi server tạo, chạm để tạo lại. Prod (qwen-flash) trả `ai:true`. Đã deploy.
- 2026-07-11 — **Polish/bug audit đa-agent trên code mới** (body scan/pets/races/mobility/AI): 0 critical/high, 2 medium, 6 low, KHÔNG có lỗi economy-firewall/idempotency/privacy. Đã fix: (1) guardrail #4 — delta số đo cơ thể KHÔNG còn tô xanh khi số đo GIẢM (đừng gamify "nhỏ hơn = tốt"); màu trung tính, số có dấu tự nói lên thay đổi. (2) Dex grid decode ảnh full-res đồng bộ trên main thread → thumbnail downsample off-main + cache (`CritterStore.thumbnail`/`CritterThumb`). (3) encode+ghi ảnh lúc bắt được thú chuyển off main actor. (4) mobility `unmatched` stat hết double-count. (5) sửa comment race milestone bị nói quá. Defer (low): mobility cap TOCTOU (xác suất thấp, ingest tuần tự) + camera orientation (cần test trên máy thật).
- 2026-07-11 — **Chatbox sức khoẻ "Nhím Coach"** (bấm mascot trên Home mở): AI tư vấn CHẠY BỘ + ĂN UỐNG lành mạnh, đi qua backend `POST /v1/me/coach/chat` (DeepSeek, đa lượt, client giữ history). **Guardrail nhúng thẳng vào system prompt** (#4 rối loạn ăn uống + #6 tư vấn y tế): không calo cực đoan, không cổ vũ nhịn ăn/giảm cân cấp tốc, không "ăn ít hơn = tốt hơn", không chẩn đoán/kê thuốc, có disclaimer, và **soft-stop**: gặp dấu hiệu rối loạn ăn uống → khuyên gặp chuyên gia. Verified prod: hỏi "nhịn ăn tối giảm cân nhanh?" → AI từ chối nhẹ nhàng + gợi ý cân bằng + đẩy tới chuyên gia dinh dưỡng. Rate cap 40/giờ/user (AI tốn tiền). Template fallback keyword-routed khi không có key. **KHÔNG mint điểm** (economy firewall). iOS: `HealthChatView` (sheet), bong bóng coach/user, chip gợi ý, typing dots, disclaimer. Đã deploy prod.
- 2026-07-11 — **Nút tương tác trong chat coach**: mỗi câu trả lời kèm (1) tối đa 3 **chip gợi ý câu hỏi tiếp** do AI tự sinh (bấm = hỏi tiếp) và (2) một **nút hành động** từ whitelist an toàn (`start_run`→màn chạy, `set_goal`→sửa mục tiêu, `none`). AI chỉ chọn KEY (json_mode), client sở hữu label + hành vi → không chế được nút bậy; server sanitise chips (≤3, ≤60 ký tự) + clamp action. Verified prod: hỏi "mới tập chạy" → DeepSeek trả `action:set_goal` + 3 chips hợp ngữ cảnh. `chat_messages` thêm cờ json_mode; `set_goal` đi qua `AppModel.requestGoalEdit`.
