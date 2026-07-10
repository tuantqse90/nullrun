import SwiftUI

/// Weekly lucky wheel — fully server-driven: the backend decides the prize
/// BEFORE the animation (design: "kết quả chốt trước khi quay") and mints it
/// to the real ledger; the app only animates to the returned segment.
struct WheelView: View {
    @EnvironmentObject private var app: AppModel

    enum Phase { case idle, spinning, done }
    @State private var phase: Phase = .idle
    @State private var degrees: Double = 0
    @State private var prize: Int = 0
    @State private var error: String?

    private var segments: [Int] { app.wheel?.segments ?? [20, 50, 30, 100, 20, 30] }

    private let palette: [(bg: Color, text: Color)] = [
        (Theme.greenBgSoft, Theme.greenDeep),
        (Theme.orangeBg, Theme.orangeDeep),
        (Theme.blueBg, Theme.blue),
        (Theme.purpleBg, Theme.purpleDeep),
        (Theme.orangeBg, Theme.orangeDeep),
        (Theme.blueBg, Theme.blue),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 6)
            Spacer()
            wheelBody
            Spacer()
            footer.padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
        .overlay { resultOverlay }
        .task { await app.refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Vòng quay tuần").font(.viet(23, .bold))
                Text("Mọi ô đều có quà — kết quả chốt trước khi quay")
                    .font(.viet(13.5)).foregroundStyle(Theme.muted)
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
    }

    private var wheelBody: some View {
        ZStack {
            ZStack {
                ForEach(segments.indices, id: \.self) { i in
                    WheelSlice(index: i, total: segments.count)
                        .fill(palette[i % palette.count].bg)
                }
                Circle().strokeBorder(Theme.ink, lineWidth: 3)
                ForEach(segments.indices, id: \.self) { i in
                    let mid = (Double(i) + 0.5) / Double(segments.count) * 360 - 90
                    Text("+\(segments[i])")
                        .font(.mono(16))
                        .foregroundStyle(palette[i % palette.count].text)
                        .offset(
                            x: cos(mid * .pi / 180) * 105,
                            y: sin(mid * .pi / 180) * 105
                        )
                }
            }
            .frame(width: 300, height: 300)
            .rotationEffect(.degrees(degrees))
            .animation(.timingCurve(0.17, 0.67, 0.16, 0.99, duration: 4.2), value: degrees)

            Circle()
                .fill(Theme.ink)
                .frame(width: 76, height: 76)
                .overlay { Mascot(mood: .happy, bobbing: false).frame(width: 44, height: 38) }
                .shadow(color: .black.opacity(0.25), radius: 7, y: 4)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.ink)
                .overlay {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 15)).foregroundStyle(Theme.orangeSoft).offset(y: -3)
                }
                .offset(y: -160)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            switch phase {
            case .idle:
                if app.wheel?.available == true {
                    PrimaryButton(title: "Quay — 1 lượt", color: Theme.purpleDeep, glow: true) {
                        Task { await spin() }
                    }
                } else if app.wheel?.spunToday == true {
                    disabledPill("Hôm nay đã quay — mai quay tiếp nhé")
                } else {
                    disabledPill("Hoàn thành 1 buổi tập để mở vòng quay")
                }
            case .spinning:
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Đang quay…").font(.viet(17, .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color(hex: 0xB7A5E0))
                .clipShape(Capsule())
            case .done:
                EmptyView()
            }
            if let error {
                Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
            }
            Text("Lượt quay đến từ vận động — không mua được bằng tiền hay điểm")
                .font(.viet(12.5)).foregroundStyle(Theme.faint)
        }
    }

    private func disabledPill(_ label: String) -> some View {
        Text(label)
            .font(.viet(15, .semibold)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Theme.track)
            .clipShape(Capsule())
    }

    private func spin() async {
        guard phase == .idle else { return }
        error = nil
        do {
            let result = try await APIClient.shared.spinWheel()
            prize = result.prize
            phase = .spinning
            Haptics.light()
            // Land the winning segment's center under the top pointer.
            let landing = 360 - (Double(result.segmentIndex) + 0.5) / Double(segments.count) * 360
            degrees += 5 * 360 + (landing - degrees.truncatingRemainder(dividingBy: 360))
            // Decelerating tick track alongside the 4.2s spin curve.
            Task {
                var gap = 0.06
                let end = Date().addingTimeInterval(4.1)
                while Date() < end {
                    Haptics.tick()
                    try? await Task.sleep(for: .seconds(gap))
                    gap = min(0.42, gap * 1.14)
                }
            }
            try? await Task.sleep(for: .seconds(4.4))
            Haptics.heavy()
            withAnimation(.spring(duration: 0.45)) { phase = .done }
        } catch {
            self.error = error.localizedDescription
            await app.refresh()
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if phase == .done {
            ZStack {
                Theme.ink.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 0) {
                    Text("Tuần chăm chỉ có quà").font(.viet(15, .semibold)).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("+\(prize)").font(.mono(52, .bold)).foregroundStyle(Theme.orangeDeep)
                        Text("điểm").font(.viet(17, .bold)).foregroundStyle(Theme.orangeDeep)
                    }
                    .padding(.top, 6)
                    PrimaryButton(title: "Nhận \(prize) điểm", height: 56) {
                        Task {
                            await app.refresh()
                            app.screen = .home
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(EdgeInsets(top: 28, leading: 26, bottom: 28, trailing: 26))
                .background(Theme.sheetBg)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(alignment: .top) { ConfettiBurst().frame(height: 120).clipped() }
                .padding(.horizontal, 34)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }
}
