import SwiftUI

// Body flow — REAL scan edition. Two photos (front + side) captured with
// the actual front camera, measured on-device by ScanEngine (Vision person
// segmentation → silhouette math). Photos never leave RAM. Manual
// tape-measure entry remains a first-class alternative, and every scan
// number is editable — the scan is an estimate, honestly labelled.

struct ScanIntroView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Đóng") { app.screen = .home }
                    .font(.viet(15)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 6)
            Spacer()
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.blueBg)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "lock").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.blue)
                }
            Text("Quét trong 1 phút,\nriêng tư tuyệt đối")
                .font(.viet(24, .heavy)).lineSpacing(4).padding(.top, 16)
            Text("Hai tư thế đứng, đo bằng hình bóng ngay trên iPhone. Ước tính có sai số vài cm — chạm vào kết quả để chỉnh lại bất cứ lúc nào.")
                .font(.viet(14.5)).foregroundStyle(Theme.muted).padding(.top, 8)

            VStack(spacing: 0) {
                bullet("Phân tích **ngay trên iPhone** — không tải lên đâu cả")
                Divider().overlay(Theme.divider)
                bullet("Ảnh chỉ nằm trong bộ nhớ tạm — **không bao giờ lưu**")
                Divider().overlay(Theme.divider)
                bullet("Không ai thấy kết quả — **kể cả chúng tôi**")
            }
            .padding(.horizontal, 18)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
            .padding(.top, 16)
            Spacer()
            PrimaryButton(title: "Bắt đầu quét (2 tư thế)") { app.screen = .scanCam }
            Button {
                app.screen = .scanRes
            } label: {
                Text("Nhập số đo bằng thước dây")
                    .font(.viet(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.green)
            Text(.init(markdown)).font(.viet(14))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - capture

struct ScanCamView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var camera = ScanCamera()

    @State private var pose = 1
    @State private var countdown: Double = 0
    @State private var capturing = false
    @State private var flash = false
    @State private var needsHeight = false
    @State private var heightInput = ""

    private var heightCm: Double? {
        let stored = UserDefaults.standard.double(forKey: "body.height")
        return stored > 0 ? stored : nil
    }

    var body: some View {
        ZStack {
            switch camera.state {
            case .ready:
                CameraPreview(session: camera.session).ignoresSafeArea()
            case .starting:
                Color(hex: 0x1C1A17).ignoresSafeArea()
                ProgressView().tint(.white)
            case .denied, .unavailable:
                Color(hex: 0x1C1A17).ignoresSafeArea()
                fallbackNotice
            }

            if camera.state == .ready {
                overlayUI
            }
            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .task {
            await camera.start()
            // Height only matters once a scan can actually happen.
            if camera.state == .ready, heightCm == nil { needsHeight = true }
        }
        .onDisappear { camera.stop() }
        .alert("Chiều cao của bạn", isPresented: $needsHeight) {
            TextField("cm, ví dụ 168", text: $heightInput).keyboardType(.numberPad)
            Button("Lưu") {
                if let value = Double(heightInput.replacingOccurrences(of: ",", with: ".")),
                   (100...220).contains(value) {
                    UserDefaults.standard.set(value, forKey: "body.height")
                } else {
                    needsHeight = true
                }
            }
            Button("Huỷ", role: .cancel) { app.screen = .scanIntro }
        } message: {
            Text("Dùng để quy đổi hình bóng ra cm — chỉ lưu trên máy.")
        }
    }

    private var overlayUI: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock").font(.system(size: 12, weight: .semibold))
                Text("Xử lý trên máy — ảnh không được lưu").font(.viet(13, .semibold))
            }
            .foregroundStyle(Theme.bluePale)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Theme.blue.opacity(0.35))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.bluePale.opacity(0.4), lineWidth: 1))
            .padding(.top, 10)

            Spacer()
            PoseSilhouette()
                .stroke(Theme.greenBright.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 7]))
                .frame(width: 190, height: 390)
                .opacity(pose == 1 ? 1 : 0.45)
            Spacer()

            HStack {
                Button("Huỷ") {
                    app.scanFront = nil
                    app.scanSide = nil
                    app.screen = .home
                }
                .font(.viet(14, .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                shutter
                Spacer()
                Text("Huỷ").font(.viet(14, .semibold)).opacity(0)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 26)

            Text(pose == 1
                 ? "Tư thế 1/2 — chính diện, hai tay dang ngang vai"
                 : "Tư thế 2/2 — xoay ngang người, tay khoanh trước ngực")
                .font(.viet(13.5, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(.bottom, 8)
            Text("Dựng máy cách 2–3 m, thấy đủ từ đầu tới chân")
                .font(.viet(12.5)).foregroundStyle(.white.opacity(0.75))
                .padding(.bottom, 14)
        }
    }

    private var shutter: some View {
        Button {
            guard countdown == 0, !capturing else { return }
            Task { await captureFlow() }
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.35), lineWidth: 5)
                if countdown > 0 {
                    Circle()
                        .trim(from: 0, to: countdown / 10)
                        .stroke(Theme.greenBright, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: countdown)
                    Text("\(Int(countdown.rounded(.up)))")
                        .font(.mono(31)).foregroundStyle(.white)
                } else {
                    Circle().fill(.white).padding(10)
                }
            }
            .frame(width: 88, height: 88)
        }
        .disabled(countdown > 0 || capturing)
    }

    /// Tap → 10 s to get into position → capture. Twice, then measure.
    private func captureFlow() async {
        capturing = true
        Haptics.light()
        countdown = 10
        while countdown > 0 {
            try? await Task.sleep(for: .milliseconds(250))
            countdown = max(0, countdown - 0.25)
            // The last three seconds tick audibly in the hand.
            if countdown <= 3, countdown.truncatingRemainder(dividingBy: 1) == 0 { Haptics.tick() }
        }
        guard let image = try? await camera.capture() else {
            capturing = false
            return
        }
        // Let the flash actually paint: setting true then false in the same
        // MainActor turn coalesces to nothing, so yield between them.
        withAnimation(.easeOut(duration: 0.1)) { flash = true }
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeIn(duration: 0.25)) { flash = false }

        if pose == 1 {
            app.scanFront = image
            withAnimation { pose = 2 }
        } else {
            app.scanSide = image
            camera.stop()
            app.screen = .scanProc
        }
        capturing = false
    }

    private var fallbackNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 30)).foregroundStyle(Theme.darkDim)
            Text(camera.state == .denied
                 ? "NullShift cần quyền camera để quét — bật trong Cài đặt."
                 : "Camera không khả dụng trên thiết bị này.")
                .font(.viet(14.5)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if camera.state == .denied {
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.viet(14, .bold)).foregroundStyle(Theme.greenBright)
            }
            Button("Nhập số đo bằng thước dây") { app.screen = .scanRes }
                .font(.viet(14, .semibold)).foregroundStyle(Theme.bluePale)
            Button("Đóng") { app.screen = .home }
                .font(.viet(13)).foregroundStyle(Theme.darkDim)
        }
        .padding(.horizontal, 40)
    }
}

struct PoseSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = rect.width / 210
        // head
        p.addEllipse(in: CGRect(x: 71 * s, y: 18 * s, width: 68 * s, height: 68 * s))
        // torso + legs (traced approximation of the design path)
        p.move(to: .init(x: 105 * s, y: 90 * s))
        p.addCurve(to: .init(x: 44 * s, y: 170 * s), control1: .init(x: 60 * s, y: 90 * s), control2: .init(x: 44 * s, y: 130 * s))
        p.addCurve(to: .init(x: 60 * s, y: 258 * s), control1: .init(x: 44 * s, y: 210 * s), control2: .init(x: 58 * s, y: 232 * s))
        p.addCurve(to: .init(x: 54 * s, y: 356 * s), control1: .init(x: 62 * s, y: 286 * s), control2: .init(x: 56 * s, y: 320 * s))
        p.addCurve(to: .init(x: 66 * s, y: 420 * s), control1: .init(x: 53 * s, y: 382 * s), control2: .init(x: 60 * s, y: 408 * s))
        p.move(to: .init(x: 105 * s, y: 90 * s))
        p.addCurve(to: .init(x: 166 * s, y: 170 * s), control1: .init(x: 150 * s, y: 90 * s), control2: .init(x: 166 * s, y: 130 * s))
        p.addCurve(to: .init(x: 150 * s, y: 258 * s), control1: .init(x: 166 * s, y: 210 * s), control2: .init(x: 152 * s, y: 232 * s))
        p.addCurve(to: .init(x: 156 * s, y: 356 * s), control1: .init(x: 148 * s, y: 286 * s), control2: .init(x: 154 * s, y: 320 * s))
        p.addCurve(to: .init(x: 144 * s, y: 420 * s), control1: .init(x: 157 * s, y: 382 * s), control2: .init(x: 150 * s, y: 408 * s))
        // arms
        p.move(to: .init(x: 44 * s, y: 150 * s))
        p.addCurve(to: .init(x: 14 * s, y: 224 * s), control1: .init(x: 24 * s, y: 168 * s), control2: .init(x: 16 * s, y: 200 * s))
        p.move(to: .init(x: 166 * s, y: 150 * s))
        p.addCurve(to: .init(x: 196 * s, y: 224 * s), control1: .init(x: 186 * s, y: 168 * s), control2: .init(x: 194 * s, y: 200 * s))
        return p
    }
}

// MARK: - measuring (real work)

struct ScanProcView: View {
    @EnvironmentObject private var app: AppModel
    @State private var progress = 0.0
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if let error {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34)).foregroundStyle(Theme.orange)
                Text("Chưa đo được").font(.viet(21, .heavy)).padding(.top, 18)
                Text(error)
                    .font(.viet(14)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                PrimaryButton(title: "Quét lại", height: 54) { app.screen = .scanCam }
                    .padding(.top, 22)
                Button("Nhập số đo bằng thước dây") { app.screen = .scanRes }
                    .font(.viet(14, .semibold)).foregroundStyle(Theme.muted)
                    .padding(.top, 14)
            } else {
                ZStack {
                    ProgressRing(progress: progress / 100, lineWidth: 9, gradient: [Theme.green, Theme.green])
                        .frame(width: 120, height: 120)
                    Text("\(Int(progress))%").font(.mono(26))
                }
                Text("Đang đo trên iPhone của bạn").font(.viet(21, .heavy)).padding(.top, 22)
                Text("Không có gì rời khỏi máy — kể cả khi tắt mạng.")
                    .font(.viet(14)).foregroundStyle(Theme.muted).padding(.top, 4)

                VStack(spacing: 0) {
                    procRow("Tách hình bóng khỏi nền (2 ảnh)", done: progress >= 75, spinning: progress < 75)
                    Divider().overlay(Theme.divider)
                    procRow("Đo bề ngang eo & hông", done: progress >= 90, spinning: progress >= 75 && progress < 90, visible: progress >= 75)
                    Divider().overlay(Theme.divider)
                    procRow("Bỏ ảnh khỏi bộ nhớ", done: progress >= 100, spinning: progress >= 90 && progress < 100, visible: progress >= 90)
                }
                .padding(.horizontal, 18)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Theme.cardShadow, radius: 5, y: 2)
                .padding(.top, 22)
            }
            Spacer()
            if error == nil {
                Text("Ước tính từ hình bóng — sai số vài cm, chỉnh tay được.")
                    .font(.viet(13)).foregroundStyle(Theme.faint)
                    .padding(.bottom, 34)
            }
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
        .task { await measure() }
    }

    private func measure() async {
        guard let front = app.scanFront, let side = app.scanSide else {
            app.screen = .scanCam
            return
        }
        let heightCm = UserDefaults.standard.double(forKey: "body.height")
        guard heightCm > 0 else {
            app.screen = .scanCam
            return
        }
        do {
            progress = 8
            let frontSil = try await ScanEngine.silhouette(of: front)
            progress = 45
            let sideSil = try await ScanEngine.silhouette(of: side)
            progress = 75
            let result = try ScanEngine.measurements(front: frontSil, side: sideSil, heightCm: heightCm)
            progress = 90
            var store = BodyMeasureStore.load()
            store.record(metric: .waist, value: result.waistCm, source: "scan")
            store.record(metric: .hip, value: result.hipCm, source: "scan")
            store.save()
            // The promise made on the capture screen, kept:
            app.scanFront = nil
            app.scanSide = nil
            progress = 100
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(500))
            app.screen = .scanRes
        } catch {
            app.scanFront = nil
            app.scanSide = nil
            withAnimation { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func procRow(_ text: String, done: Bool, spinning: Bool = false, visible: Bool = true) -> some View {
        if visible {
            HStack(spacing: 12) {
                if spinning {
                    ProgressView().controlSize(.small).tint(Theme.green)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.green)
                }
                Text(text).font(.viet(14, spinning ? .semibold : .regular))
                    .foregroundStyle(spinning ? Theme.ink : Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
        }
    }
}

// MARK: - results (manual + scan estimates, both editable)

struct ScanResView: View {
    @EnvironmentObject private var app: AppModel
    @State private var store = BodyMeasureStore.load()
    @State private var editing: BodyMetric?
    @State private var editValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Số đo cơ thể").font(.viet(23, .bold))
                    Text("Hôm nay · \(Self.clock())").font(.viet(14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    app.screen = .home
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 40, height: 40)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
                }
            }
            .padding(.top, 6).padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "lock").font(.system(size: 15)).foregroundStyle(Theme.blue)
                Text("Số đo chỉ lưu trên máy — không ai khác nhìn thấy, kể cả chúng tôi.")
                    .font(.viet(13)).foregroundStyle(Theme.blue)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.blueBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // The cool part: a 3D hologram driven by the real numbers.
                    if let waist = store.latest(.waist)?.value,
                       let hip = store.latest(.hip)?.value {
                        BodyModelCard(
                            waistCm: waist,
                            hipCm: hip,
                            heightCm: storedHeight ?? 165,
                            level: app.levelNum,
                            streak: petStreak
                        )
                        .popIn()
                    }

                    Text("Chạm vào chỉ số để nhập/sửa. Số từ máy quét là ước tính hình bóng (±vài cm).")
                        .font(.viet(12.5)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    metricCard(.waist)
                    metricCard(.hip)
                    whrCard

                    Text("Số đo dao động tự nhiên theo ngày — xu hướng nhiều tuần mới có ý nghĩa.")
                        .font(.viet(12)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4).padding(.horizontal, 4)
                }
                .padding(.bottom, 8)
            }

            Button {
                app.screen = .scanCam
            } label: {
                Text("Quét lại bằng camera")
                    .font(.viet(14, .semibold)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            PrimaryButton(title: "Xong", height: 56) { app.screen = .home }
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(Theme.bg)
        .alert(editing?.title ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("cm, ví dụ 74,5", text: $editValue).keyboardType(.decimalPad)
            Button("Lưu") {
                if let metric = editing,
                   let value = Double(editValue.replacingOccurrences(of: ",", with: ".")),
                   (30...200).contains(value) {
                    store.record(metric: metric, value: value, source: "manual")
                    store.save()
                }
                editing = nil
            }
            Button("Huỷ", role: .cancel) { editing = nil }
        } message: {
            Text("Đo bằng thước dây, sát da, không nín bụng.")
        }
    }

    private var storedHeight: Double? {
        let h = UserDefaults.standard.double(forKey: "body.height")
        return h > 0 ? h : nil
    }

    private var petStreak: Int {
        #if DEBUG
        // Design-QA: preview the hedgehog's full wardrobe without a
        // 50-day streak (simulator only).
        if let raw = ProcessInfo.processInfo.environment["DEV_PET_STREAK"],
           let value = Int(raw) {
            return value
        }
        #endif
        return app.points?.streakCurrent ?? 0
    }

    private static func clock() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// One-decimal cm, VN comma, trailing ",0" trimmed — matches the edit field.
    private static func cm(_ v: Double) -> String {
        let s = String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
        return (s.hasSuffix(",0") ? String(s.dropLast(2)) : s) + " cm"
    }

    @ViewBuilder
    private func metricCard(_ metric: BodyMetric) -> some View {
        let latest = store.latest(metric)
        Button {
            editValue = latest.map { String(format: "%.1f", $0.value) } ?? ""
            editing = metric
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(metric.title).font(.viet(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    if latest?.source == "scan" {
                        Text("từ máy quét")
                            .font(.viet(10.5, .bold)).foregroundStyle(Theme.blue)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.blueBg)
                            .clipShape(Capsule())
                    }
                    Image(systemName: "square.and.pencil").font(.system(size: 14)).foregroundStyle(Color(hex: 0xC6BEB0))
                }
                Text(latest.map { Self.cm($0.value) } ?? "— chạm để nhập")
                    .font(.mono(25))
                    .foregroundStyle(latest == nil ? Theme.faint : Theme.ink)
                if let delta = store.delta(metric) {
                    // Body surfaces carry NO thin/fat judgement (guardrail #4):
                    // the signed number states the change; the colour stays
                    // neutral so shrinking is never framed as "winning".
                    Text(String(format: "thay đổi %+.1f cm · so lần trước", delta).replacingOccurrences(of: ".", with: ","))
                        .font(.viet(12.5)).foregroundStyle(Theme.muted)
                }
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var whrCard: some View {
        if let waist = store.latest(.waist)?.value, let hip = store.latest(.hip)?.value, hip > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tỷ lệ eo–hông").font(.viet(13)).foregroundStyle(Theme.muted)
                Text(String(format: "%.2f", waist / hip).replacingOccurrences(of: ".", with: ","))
                    .font(.mono(25))
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
        }
    }
}

enum BodyMetric: String, Codable {
    case waist, hip

    var title: String {
        switch self {
        case .waist: "Vòng eo"
        case .hip: "Vòng hông"
        }
    }
}

/// On-device-only store for body measurements (the privacy story: nothing
/// leaves the phone). Keeps a small history per metric for deltas.
struct BodyMeasureStore: Codable {
    struct Entry: Codable {
        let value: Double
        let at: Date
        /// "scan" (silhouette estimate) or "manual" (tape measure).
        /// Optional so entries saved before this field decode fine.
        let source: String?
    }

    var entries: [String: [Entry]] = [:]

    static func load() -> BodyMeasureStore {
        guard let data = UserDefaults.standard.data(forKey: "body.measures"),
              let store = try? JSONDecoder().decode(BodyMeasureStore.self, from: data)
        else { return BodyMeasureStore() }
        return store
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "body.measures")
        }
    }

    func latest(_ metric: BodyMetric) -> Entry? {
        entries[metric.rawValue]?.last
    }

    func delta(_ metric: BodyMetric) -> Double? {
        guard let list = entries[metric.rawValue], list.count >= 2 else { return nil }
        return list[list.count - 1].value - list[list.count - 2].value
    }

    mutating func record(metric: BodyMetric, value: Double, source: String = "manual") {
        var list = entries[metric.rawValue] ?? []
        list.append(Entry(value: value, at: Date(), source: source))
        entries[metric.rawValue] = Array(list.suffix(24))
    }
}
