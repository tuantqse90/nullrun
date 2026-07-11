-- Tasco / VETC ecosystem rewards catalog (AABW 2026 mobility track).
-- Points earned from genuine activity redeem across the Tasco ecosystem:
--   vetc   = VETC toll account (top-ups, monthly/annual passes)
--   vetcgo = VETC GO mobility (self-drive & chauffeured rental, airport, rides)
--   tasco  = wider ecosystem (fuel/EV, rest-stop F&B, Carpla car care,
--            e-Parking, T-money, Tasco Insurance, Null Run x Tasco merch)
-- Adapter routing + the "guardian-link only for guardian rewards" gate live
-- in src/rewards/{partner.rs,mod.rs}. Voucher-code mock until Tasco BD lands.

INSERT INTO rewards (partner, title, description, cost_points, stock) VALUES
    ('vetc', 'Nạp Ví VETC 20.000đ', 'Nạp thẳng 20.000đ vào Ví VETC, tự động trừ khi qua trạm — đổi nhanh cho ngày chạy bộ lười.', 200, NULL),
    ('vetc', 'Nạp Ví VETC 50.000đ', 'Cộng 50.000đ vào tài khoản thu phí không dừng, dùng cho qua trạm, đỗ xe, xăng dầu và sạc xe — càng chạy càng đỡ tốn.', 480, NULL),
    ('vetc', 'Nạp Ví VETC 100.000đ', 'Nạp 100.000đ vào Ví VETC với giá ưu đãi hơn — quẹt Etag qua mọi trạm trên toàn quốc, không cần dừng lấy vé.', 900, NULL),
    ('vetc', 'Nạp Ví VETC 200.000đ', 'Gói nạp lớn 200.000đ cho tài khoản giao thông, đủ cho cả chuyến về quê ăn Tết — chi được cho phí đường và phí bảo trì đường bộ.', 1800, 30),
    ('vetc', 'Vé tháng VETC qua trạm', 'Tín dụng qua trạm trọn 1 tháng cho tuyến quen, kích hoạt qua app VETC — khỏi lo hết số dư giờ cao điểm.', 1500, 25),
    ('vetc', 'Vé năm VETC + Làn ưu tiên', 'Phần thưởng đỉnh: gói qua trạm cả năm cộng đặc quyền làn ưu tiên VETC Loyalty — vi vu Bắc Nam suốt 12 tháng không lo phí đường.', 9000, 5),
    ('vetcgo', 'Thuê xe tự lái VETC GO trọn 1 ngày (xe 4-5 chỗ)', 'Đổi trọn 24 giờ thuê xe tự lái 4-5 chỗ trên app VETC GO, giao nhận xe tận nơi — sẵn sàng cho chuyến đường dài ngày Tết.', 9500, 5),
    ('vetcgo', 'Thuê xe có tài xế VETC GO 4 giờ', '4 giờ thuê xe kèm tài xế chuyên nghiệp trên VETC GO — cứ ngồi ghế sau, đường sá để tài xế lo.', 6500, 10),
    ('vetcgo', 'Đưa đón sân bay VETC GO (Nội Bài / Tân Sơn Nhất)', 'Một chuyến đưa hoặc đón sân bay Nội Bài / Tân Sơn Nhất qua VETC GO — đặt trước, đón đúng giờ bay.', 3200, 20),
    ('vetcgo', 'Giảm 30% thuê xe tự lái cuối tuần VETC GO', 'Giảm 30% giá thuê xe tự lái cho chuyến cuối tuần trên VETC GO, áp dụng Thứ 7 - Chủ nhật.', 2600, 30),
    ('vetcgo', 'Tặng 2 giờ đầu thuê xe tự lái VETC GO', 'Miễn phí 2 giờ đầu khi thuê xe tự lái trên VETC GO — chạy thử một vòng không mất phí.', 1600, 50),
    ('vetcgo', 'Voucher đặt xe VETC GO 100.000đ', 'Voucher 100.000đ đặt xe di chuyển trên VETC GO, trừ thẳng vào cước chuyến đi.', 950, NULL),
    ('tasco', 'Voucher xăng 50.000đ', 'Giảm 50.000đ hóa đơn xăng dầu, quét mã trả qua Ví VETC tại các cây xăng đối tác trên toàn quốc.', 480, NULL),
    ('tasco', 'Voucher xăng 100.000đ', 'Đầy bình tiết kiệm hơn với 100.000đ off, dùng khi thanh toán xăng dầu bằng Ví VETC — lý tưởng cho cung đường dài.', 900, 30),
    ('tasco', 'Voucher xăng 200.000đ — Combo về quê ăn Tết', 'Ưu đãi lớn cho chuyến road-trip Tết: giảm 200.000đ tiền xăng, thanh toán qua Ví VETC. Số lượng có hạn.', 1800, 15),
    ('tasco', 'Voucher sạc xe điện 100.000đ', 'Trừ 100.000đ phí sạc tại trạm sạc VETC / Tasco Smart Charge, dùng được ở hơn 200 điểm sạc liên minh.', 900, 30),
    ('tasco', 'Voucher cà phê ''Tỉnh Táo Lái Xe'' 25.000đ', 'Ly cà phê nóng hoặc đá tại trạm dừng nghỉ, xua cơn buồn ngủ trước khi vào cung đường dài.', 250, NULL),
    ('tasco', 'Voucher đồ ăn & nước trạm dừng nghỉ 50.000đ', 'Trừ thẳng 50.000đ cho F&B tại trạm dừng nghỉ trên tuyến — tự chọn cà phê, đồ ăn nóng hoặc nước.', 450, NULL),
    ('tasco', 'Combo ''Nghỉ Chân Đường Dài'' dịp Tết', 'Set nghỉ chân cao cấp: cà phê + suất ăn nóng + khăn lạnh, tiếp sức cho chuyến về quê ăn Tết. Số lượng có hạn.', 850, 30),
    ('tasco', 'Khám xe miễn phí 20 hạng mục trước chuyến đi', 'Kiểm tra phanh, lốp, dầu nhớt, ắc-quy... 20 điểm an toàn tại Carpla Service trước khi lên đường về quê ăn Tết.', 150, NULL),
    ('tasco', 'Voucher thay dầu nhớt giảm 100.000đ', 'Giảm 100.000đ khi thay dầu nhớt chính hãng tại xưởng Carpla Service, đặt lịch nhanh ngay trong ứng dụng.', 900, 30),
    ('tasco', 'Voucher bảo dưỡng định kỳ giảm 200.000đ', 'Giảm 200.000đ cho gói bảo dưỡng định kỳ (dầu, lọc gió, kiểm tra tổng quát) tại hệ thống Tasco Auto / Carpla Service.', 1800, 20),
    ('tasco', 'Gói chăm xe toàn diện Tasco Auto (trị giá 1.000.000đ)', 'Đại tiệc chăm xe trước Tết: rửa xe cao cấp, thay dầu, đảo lốp và bảo dưỡng tổng quát tại showroom Tasco Auto. Số lượng có hạn.', 8000, 5),
    ('tasco', 'Đỗ xe thông minh miễn phí 2 giờ (e-Parking VETC)', 'Dùng tại bãi đỗ e-Parking không tiền mặt: quét biển số là vào, tặng 2 giờ đỗ trừ thẳng vào tài khoản giao thông.', 100, NULL),
    ('tasco', 'Voucher đỗ xe e-Parking 50.000đ', 'Tín dụng đỗ xe 50.000đ cho mọi bãi đỗ thông minh VETC, vào ra chỉ trong vài giây, thanh toán không dừng.', 450, NULL),
    ('tasco', 'Vé đỗ xe tháng e-Parking VETC', 'Vé tháng đỗ xe không giới hạn lượt tại một bãi e-Parking đăng ký, cực hợp dân văn phòng đi làm mỗi ngày. Số lượng có hạn.', 1600, 15),
    ('tasco', 'Ví T-money — Nạp 20.000đ', 'Nạp 20.000đ vào ví T-money, thanh toán nhanh phí đỗ xe và các dịch vụ trong hệ sinh thái.', 200, NULL),
    ('tasco', 'Voucher giảm 100.000đ bảo hiểm sức khoẻ', 'Ưu đãi 100.000đ cho gói bảo hiểm sức khoẻ Tasco Insurance — thưởng cho lối sống năng động.', 850, 30),
    ('tasco', 'Voucher giảm 10% bảo hiểm vật chất ô tô (tối đa 300.000đ)', 'Giảm 10%, tối đa 300.000đ, phí bảo hiểm vật chất xe Tasco Insurance khi mua qua Ví VETC.', 1400, 20),
    ('tasco', 'Bộ sticker phản quang Null Run x Tasco', 'Dán lên mũ bảo hiểm, cốp xe hay bình nước — phản quang giúp bạn an toàn hơn khi chạy tối; đổi online, giao kèm đơn merch.', 60, NULL),
    ('tasco', 'Bình giữ nhiệt Null Run x Tasco 500ml', 'Bình inox giữ nóng/lạnh 12 giờ, giảm rác nhựa cho mỗi buổi chạy; số lượng có hạn, giao tận nơi.', 700, 40),
    ('tasco', 'Áo thun chạy bộ Null Run x Tasco (bản giới hạn)', 'Áo thể thao thoáng mồ hôi phiên bản giới hạn Null Run x Tasco; chọn size khi nhận hàng, ship toàn quốc.', 1000, 25);
