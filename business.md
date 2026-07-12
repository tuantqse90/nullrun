# Null Run — Business Overview

> Bản mô tả mảng kinh doanh & sản phẩm đang xây. Cập nhật 2026-07-12.
> Tài liệu kỹ thuật: [tech.md](tech.md). Kế hoạch milestone: [plan.md](plan.md).

---

## 1. Một câu

**Null Run** là app chạy bộ / vận động cho thị trường Việt Nam, biến **vận động thật** thành **điểm thưởng** đổi ra **quà thật** — với một lớp **chống gian lận + xác thực** nằm dưới để đối tác dám trả tiền cho hành vi đó.

Định vị: **lớp "activity + verification" trung lập**. Chúng tôi không phải chương trình loyalty của riêng ai — chúng tôi chứng minh "người này vận động thật", còn các đối tác (bán lẻ, mobility, bảo hiểm, thương hiệu) cắm vào và tài trợ phần thưởng.

---

## 2. Mô hình kinh doanh — "Vitality-nhưng-retailer" (B2B2C)

Vòng lặp giá trị:

```
Vận động thật  →  Xác thực (anti-cheat)  →  Điểm (soulbound)  →  Hạng/tier  →  Đổi quà đối tác
```

- **Người dùng (C):** chạy/đi bộ thật → tích điểm → đổi quà thật, miễn phí. Không mua điểm, không nạp tiền.
- **Đối tác (B):** tài trợ phần thưởng để đổi lấy **engagement + dữ liệu sức khoẻ first-party + lưu lượng khách tới cửa hàng**.
- **Null Run (B ở giữa):** vận hành engine hoạt động + xác thực trung lập; bán "hành vi khoẻ mạnh đã được chứng minh" cho nhiều đối tác dùng chung một engine.

Điểm khác Vitality kinh điển: đối tác neo (anchor) là **nhà bán lẻ sức khoẻ/làm đẹp** (Guardian) thay vì hãng bảo hiểm → mass-market, ít rào cản, dữ liệu foot-traffic có giá trị ngay.

**Vì sao mô hình này thắng:**
- Nhu cầu đã được chứng minh (Vitality chạy ở hàng chục thị trường; AIA đã đưa về VN) — nhưng đó là chương trình đóng của **một** hãng bảo hiểm. Bán lẻ / ngân hàng / mobility **chưa có lớp trung lập** để cắm vào.
- Điểm yếu chí mạng của đối thủ: **đếm bước chân giả được trong 5 phút** (lắc điện thoại). StepN trả token theo bước → bot farm → sập kinh tế. Chúng tôi xây đúng vào khoảng trống "bằng chứng".

---

## 3. Hệ sinh thái đối tác

### 3.1 Guardian (Hội Cam) — anchor sức khoẻ/làm đẹp
- Nhà bán lẻ ~3.5M thành viên Hội Cam. Người dùng **liên kết thẻ Hội Cam** rồi đổi điểm lấy voucher/sản phẩm Guardian.
- Liên kết đó **chính là câu chuyện B2B2C** (first-party data + foot-traffic).
- *Trạng thái:* BD/API access vẫn là **ẩn số #1** — hiện dùng adapter mock (voucher-code), swap sang API thật khi có access.

### 3.2 Hệ sinh thái Tasco / VETC — mobility (trọng tâm hackathon AABW 2026)
Engine "earning" **source-agnostic**: không chỉ chạy bộ mới ra điểm/quà, mà cả hành vi di chuyển. Catalog đổi thưởng Tasco/VETC gồm 3 nhóm đối tác:
- **VETC** (thu phí không dừng): nạp Ví VETC, vé tháng/năm qua trạm, làn ưu tiên.
- **VETC GO** (mobility super-app): thuê xe tự lái / có tài xế, đưa đón sân bay, voucher đặt xe.
- **Tasco** (rộng): voucher xăng/EV, trạm dừng nghỉ (cà phê/đồ ăn), Carpla (thay dầu/bảo dưỡng/khám xe), e-Parking, T-money, Tasco Insurance, merch Null Run × Tasco.
- **Nguyên tắc incentive:** nhiệm vụ mobility thưởng cho việc **đi off-peak** (tránh giờ cao điểm 6-9h/16-19h) — **không bao giờ** trả tiền để lái nhiều hơn/nhanh hơn. Khớp mục tiêu giảm kẹt xe của Tasco.

### 3.3 Tương lai
Cùng một engine + lớp xác thực → **bảo hiểm** (tier theo vận động), **thương hiệu** (branded challenge) cắm vào sau. Mỗi đối tác mới chỉ là một "input" mới, engine xây một lần.

---

## 4. Sản phẩm đang xây (toàn bộ)

### 4.1 Lõi (v1 — kiểm chứng vòng lặp)
- **Activity engine:** đi bộ + chạy, auto-capture bằng GPS/sensor native. Không tính hoạt động nhập tay.
- **Anti-cheat / integrity (moat):** device attestation (App Attest), fraud scoring 7 tín hiệu, rate cap, sensor fusion — **chỉ session "sạch" mới ra điểm**. Đây là thứ khiến đối tác dám trả tiền.
- **Gamification:** điểm, hạng/tier theo mùa, chuỗi ngày (streak), bảng xếp hạng tuần, league (bucket 50 người), thử thách (challenge), nhiệm vụ ngày (quest).
- **Đổi thưởng + Guardian linking:** catalog quà, redeem reserve-then-fulfill, ví voucher.

### 4.2 Mở rộng engagement (v1.x)
- **Vòng quay may mắn** (lucky wheel), **mini-games**, **đấu 1v1** (duel — đua tới mốc, xử thắng theo thời điểm cán mốc GPS).
- **Guild / Hội** (crew chia sẻ nhiệm vụ ngày/tuần) — chỉ trao **guild XP cosmetic**, tuyệt đối không mint điểm cá nhân (economy firewall) cho tới khi có anti-sybil đầy đủ.
- **Giải theo khung giờ:** Giải Bình Minh (5-9h) + Giải Hoàng Hôn (18-22h) — mở theo giờ VN, cộng dồn cự ly trong khung, mốc thưởng guild XP.

### 4.3 "Thú Cưng Đường Phố" — bắt chó mèo (retention loop)
Tính năng **bắt chó/mèo ngoài đường kiểu Pokémon GO**:
- Đưa camera lên gặp chó/mèo → **ném xương cho chó / ném cá cho mèo** (cơ chế ná/slingshot) → bắt được thì lưu vào **Sổ Bạn Nhỏ** (Pokédex trên máy).
- Mỗi con bắt được có **thẻ TCG đẹp** (độ hiếm Thường/Hiếm/Cực hiếm/Huyền thoại, holographic, kéo nghiêng 3D). Bắt được huyền thoại có **hiệu ứng nổ hoành tráng** (tia sáng, vòng sốc, hạt bay, rung haptic).
- **Vai trò kinh doanh:** đây là **retention + delight loop**, lý do quay lại app hằng ngày, chất "kute/ngầu" để lan truyền/viral. Nhẹ nhàng, thân thiện động vật ("đừng đuổi các bé").
- **Firewall kinh tế (quan trọng):** bắt thú **KHÔNG mint điểm** hoạt động — vuốt mèo không phải tập thể dục. Nó là bộ sưu tập **cosmetic, lưu 100% trên máy** (ảnh không upload). Không phá cân bằng faucet/sink của nền kinh tế điểm.

### 4.4 Body scan 3D — câu chuyện riêng tư (privacy = moat)
- Quét cơ thể **on-device** (Apple Vision) ra ước tính số đo (vòng eo/hông) + **mô hình 3D** stylized (nhân vật anime cute + bạn đồng hành nhím tím lớn theo level, đổi skin theo streak).
- **Ảnh không rời khỏi máy**, không có số cân nặng tuyệt đối, không phán xét hình thể. Quyền riêng tư health data chính là con hào cạnh tranh.

### 4.5 AI coach — sức khoẻ (xem chi tiết ở tech.md)
- **Gợi ý ngắn ("insight")** trên Home + **chatbox "Nhím Coach"** tư vấn chạy bộ + ăn uống lành mạnh, cá nhân hoá theo số liệu thật, có nút hành động (bắt đầu chạy / đặt mục tiêu) + chip gợi ý.
- Ràng buộc an toàn nghiêm ngặt (không giảm cân cực đoan, không chẩn đoán bệnh, đẩy tới chuyên gia khi cần).

### 4.6 Lớp mobility/VETC (demo track)
- Adapter nhận sự kiện đối tác (toll/topup/fuel/parking) → nhiệm vụ mobility → thưởng. Console đối tác + AI cá nhân hoá/win-back.

---

## 5. Guardrails = hàng rào bảo vệ kinh doanh

| Guardrail | Rủi ro kinh doanh nếu bỏ | Trạng thái |
|---|---|---|
| **Anti-cheat từ ngày 1** | Quà = tiền thật → gian lận công nghiệp làm sập kinh tế (bài học StepN) | Đang có: 7 tín hiệu fraud, rate cap, attestation |
| **Anti-sybil trước guild reward** | Bot tạo hàng loạt hội để farm | Guild XP **cosmetic** cho tới khi đủ anti-sybil |
| **Economy firewall** | Guild/pet/scan feed ngược vào điểm cá nhân → farm→power→cash-out | Bắt thú/guild/scan **không mint điểm** |
| **Chống rối loạn ăn uống** | Gamify giảm cân → nguy hiểm sức khoẻ + trách nhiệm pháp lý | Không mục tiêu calo cực đoan; coach có soft-stop |
| **Health-advice liability** | Dinh dưỡng/clinical chạm lãnh địa tư vấn y tế | Disclaimer; clinical để cuối cùng |
| **Privacy** | Health/body data là loại nhạy cảm nhất | On-device + không upload ảnh |

---

## 6. Doanh thu (định hướng)

- **B2B licensing / rev-share:** đối tác trả để tiếp cận engagement + hành vi khoẻ mạnh đã xác thực.
- **First-party health data** (theo consent, selective disclosure): tài sản dữ liệu là moat, không bán thô.
- **Foot-traffic tới cửa hàng** (Guardian, trạm dừng nghỉ Tasco…).
- Điểm là **loyalty soulbound** — không tradeable, không cash-out → **không phải tiền ảo đầu cơ** (tránh sập kiểu StepN).

---

## 7. Roadmap (sequencing)

- **v1** — kiểm chứng vòng lặp: onboarding, activity engine, anti-cheat, gamification lõi, rewards + Guardian, dashboard đối tác. ZERO AI (đã lệch có chủ đích cho track — xem tech.md).
- **v1.x** — virtual race, cycling, multi-activity, lucky wheel, Health Connect, finisher-medal NFT, win-back.
- **v1.5** — body scan 3D thật (MediaPipe+SMPL), ZK/privacy + soulbound on-chain, guild (khi đủ mật độ user + anti-sybil).
- **v2** — AI (training plan, nutrition, insight), corporate guild, branded challenge.
- **v2.x** — clinical (labs), guild season/war/shop, insurer tier, live-ops.

---

## 8. Bối cảnh hackathon & ẩn số

- **AABW 2026 — Tasco VETC Mobility Track — "AI-Powered Gamification".** Sản phẩm đã live prod (`api.nullshift.sh` / `run.nullshift.sh`) với lớp VETC + AI + console đối tác.
- **Ẩn số lớn nhất:** Guardian (Hội Cam) BD/API access — quyết định hình dạng tích hợp reward. Trong lúc chờ, kiến trúc adapter cho phép cắm đối tác nào cũng được (đã chứng minh với Tasco/VETC).
