import SwiftUI

/// Active tracking screen — dark mode, big mono distance, lock / pause /
/// hold-to-finish controls. Matches the prototype's run screen.
struct RunView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var tracker: RunTracker
    @State private var holdProgress: Double = 0
    @State private var holdTimer: Timer?
    @State private var finishing = false
    @State private var finishError: String?
    @State private var lastKmShown = 0

    var body: some View {
        VStack(spacing: 0) {
            statusRow.padding(.top, 6)
            Spacer()
            centerStats
            Spacer()
            VStack(spacing: 14) {
                if let finishError {
                    Text(finishError)
                        .font(.viet(12.5)).foregroundStyle(Theme.orangePale)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                controls
            }
            .padding(.bottom, 56)
        }
        .padding(.horizontal, 24)
        .background(Theme.darkBg)
        .overlay(alignment: .top) { kmFlag.padding(.top, 140) }
    }

    private var gpsLost: Bool { tracker.gpsState == .lost }

    private var statusRow: some View {
        HStack {
            if gpsLost {
                HStack(spacing: 7) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.orangeSoft)
                    Text("Mất tín hiệu GPS").font(.viet(14, .semibold)).foregroundStyle(Theme.orangePale)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(hex: 0x3A3126))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 7) {
                    PulsingDot()
                    Text("GPS tốt").font(.viet(14, .semibold)).foregroundStyle(Theme.greenPale)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.greenDarkPill)
                .clipShape(Capsule())
            }
            Spacer()
            Text("\(tracker.activityType == "walk" ? "Đi bộ" : "Chạy bộ") · \(Self.clock())")
                .font(.viet(14, .semibold)).foregroundStyle(Theme.faint)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.darkCard)
                .clipShape(Capsule())
        }
    }

    private static func clock() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private var centerStats: some View {
        VStack(spacing: 2) {
            Text("Quãng đường · km").font(.viet(17, .medium)).foregroundStyle(Theme.faint)
            Text(Fmt.dist(tracker.distanceKm))
                .font(.mono(104))
                .foregroundStyle(gpsLost ? Theme.darkDim : .white)
                .kerning(-4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy, value: tracker.distanceKm)
            trackDoodle

            if gpsLost {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.orangeSoft)
                    Text("Đang chờ tín hiệu — điểm được giữ nguyên, quãng đường sẽ tự nối.")
                        .font(.viet(12.5)).foregroundStyle(Theme.faint)
                }
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .background(Theme.darkCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                statCol(Fmt.time(tracker.seconds), "Thời gian", .white)
                if tracker.activityType == "walk" {
                    // Walking is about steps, not pace — hardware pedometer
                    // count (the same stream that feeds anti-cheat cadence).
                    statCol(Fmt.int(tracker.steps), "Bước chân", .white)
                } else {
                    statCol(gpsLost ? "—" : Fmt.pace(tracker.paceSecPerKm), "Nhịp độ /km", .white)
                }
                statCol("+\(tracker.livePoints)", "Điểm", Theme.greenBright, sparkle: true)
            }
            .padding(.top, 30)

            HStack(spacing: 7) {
                Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Theme.orangeSoft)
                Text("Chuỗi \(app.points?.streakCurrent ?? 0) ngày — giữ nhịp mỗi ngày")
                    .font(.viet(12.5, .semibold)).foregroundStyle(Theme.orangePale)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.streakDarkPill)
            .clipShape(Capsule())
            .padding(.top, 18)
        }
        .animation(.easeOut(duration: 0.3), value: gpsLost)
    }

    private func statCol(_ value: String, _ label: String, _ color: Color, sparkle: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                if sparkle {
                    Image(systemName: "sparkle").font(.system(size: 12)).foregroundStyle(Theme.greenBright)
                }
                Text(value).font(.mono(31)).foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            Text(label).font(.viet(13.5)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private var trackDoodle: some View {
        ZStack {
            WavyTrack()
                .stroke(Theme.darkLine, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            HStack {
                Circle().fill(Theme.darkDim).frame(width: 6, height: 6)
                Spacer()
                Circle().fill(Theme.darkDim).frame(width: 6, height: 6)
            }
            .padding(.horizontal, 2)
            Mascot(mood: .running).frame(width: 40, height: 33).offset(y: -14)
        }
        .frame(width: 250, height: 54)
        .padding(.top, 4)
    }

    /// Milestone flag: every km for runs, every 1.000 steps for walks —
    /// same slot, same celebration weight (haptic + 2s pill).
    @ViewBuilder
    private var kmFlag: some View {
        if tracker.activityType == "walk" {
            let block = tracker.steps / 1000
            if block >= 1, block != lastKmShown {
                milestonePill(icon: "shoeprints.fill", label: "\(Fmt.int(block * 1000)) bước")
                    .task {
                        Haptics.success()
                        try? await Task.sleep(for: .seconds(2.2))
                        lastKmShown = block
                    }
            }
        } else {
            let km = Int(tracker.distanceKm)
            if km >= 1, km != lastKmShown {
                milestonePill(icon: "flag.fill", label: "\(km) km")
                    .task {
                        Haptics.success()
                        try? await Task.sleep(for: .seconds(2.2))
                        lastKmShown = km
                    }
            }
        }
    }

    private func milestonePill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.mono(13))
        }
        .foregroundStyle(Theme.greenPale)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.greenDarkPill)
        .clipShape(Capsule())
        .transition(.scale.combined(with: .opacity))
    }

    private var controls: some View {
        // Buttons freeze while the finish is in flight (the hold gesture
        // guards itself on `finishing`).
        HStack(spacing: 34) {
            VStack(spacing: 8) {
                Button { app.screen = .locked } label: {
                    Image(systemName: "lock")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 64, height: 64)
                        .background(Theme.darkCard)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.darkLine, lineWidth: 1))
                }
                .buttonStyle(PressScale())
                Text("Khoá").font(.viet(12.5)).foregroundStyle(Theme.faint)
            }

            VStack(spacing: 8) {
                Button {
                    Task { await tracker.togglePause() }
                } label: {
                    Image(systemName: tracker.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.darkBg)
                        .frame(width: 100, height: 100)
                        .background(Theme.darkInk)
                        .clipShape(Circle())
                        .shadow(color: Theme.darkInk.opacity(0.15), radius: 12, y: 8)
                }
                .buttonStyle(PressScale())
                Text(tracker.paused ? "Tiếp tục" : "Tạm dừng")
                    .font(.viet(12.5, .semibold)).foregroundStyle(Theme.darkInk)
            }

            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Theme.darkLine, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: finishing ? 1 : holdProgress)
                        .stroke(Theme.orangeSoft, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(Theme.darkCard).padding(8)
                    if finishing {
                        ProgressView().tint(Theme.orangeSoft)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.orangeSoft).frame(width: 16, height: 16)
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
                .accessibilityIdentifier("finishHold")
                // Raw finger down/up. onLongPressGesture cancels when the
                // finger drifts >10pt — trivially easy with a shaky
                // post-run hand — so the hold never completed on device.
                // The timer owns the 3s completion, not the gesture.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if holdTimer == nil, !finishing { startHold() }
                        }
                        .onEnded { _ in endHold() }
                )
                Text(finishing ? "Đang chốt…" : holdProgress > 0 ? "Giữ tiếp…" : "Giữ để kết thúc")
                    .font(.viet(12.5)).foregroundStyle(Theme.faint)
            }
        }
        .disabled(finishing)
    }

    private func startHold() {
        Haptics.light()
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                holdProgress = min(1, holdProgress + 0.05 / 3.0)
                if holdProgress >= 1 {
                    holdTimer?.invalidate()
                    holdTimer = nil
                    Haptics.heavy()
                    await finishRun()
                }
            }
        }
    }

    private func endHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        guard !finishing, holdProgress < 1 else { return }
        // dd6: releasing early unwinds the ring in 250ms.
        withAnimation(.easeOut(duration: 0.25)) { holdProgress = 0 }
    }

    private func finishRun() async {
        guard !finishing else { return }
        finishing = true
        finishError = nil
        // Flaky network mid-park is normal; retry before giving up.
        var finished: ActivitySession?
        for attempt in 0..<3 {
            if let session = try? await tracker.finish() {
                finished = session
                break
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        }
        if let finished {
            app.screen = .summary(finished)
        } else {
            // The session is still open server-side — stay here so another
            // hold retries (tracker.finish() is re-entrant). Never drop to
            // home silently: that reads as a lost walk.
            withAnimation {
                finishError = "Mạng chập chờn — giữ nút lần nữa để thử lại."
            }
            withAnimation(.easeOut(duration: 0.25)) { holdProgress = 0 }
        }
        finishing = false
    }
}

struct PulsingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Theme.greenBright)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(Theme.greenBright.opacity(0.55), lineWidth: 3)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            .onAppear { pulse = true }
    }
}

struct WavyTrack: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY + 10
        p.move(to: .init(x: rect.minX + 6, y: y))
        p.addCurve(
            to: .init(x: rect.midX, y: y - 2),
            control1: .init(x: rect.width * 0.18, y: y - 10),
            control2: .init(x: rect.width * 0.3, y: y + 8)
        )
        p.addCurve(
            to: .init(x: rect.maxX - 6, y: y - 4),
            control1: .init(x: rect.width * 0.64, y: y - 12),
            control2: .init(x: rect.width * 0.76, y: y + 6)
        )
        return p
    }
}
