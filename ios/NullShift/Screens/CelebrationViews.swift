import SwiftUI

/// Server-data-driven celebration moments. Detection lives in AppModel
/// (tier/level/streak deltas across refreshes); this file only renders.
enum Celebration: Equatable {
    case tierUp(tier: String, seasonEarned: Int)
    case levelUp(level: Int)
    case streakMilestone(days: Int)
}

struct CelebrationHost: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        if let celebration = app.celebration {
            Group {
                switch celebration {
                case .tierUp(let tier, let earned):
                    TierCeremonyView(tier: tier, seasonEarned: earned)
                case .levelUp(let level):
                    LevelUpView(level: level)
                case .streakMilestone(let days):
                    StreakMilestoneView(days: days)
                }
            }
            .transition(.opacity)
            .zIndex(10)
        }
    }
}

/// m01 — the gold promotion ceremony: dark violet stage, gold shield with a
/// shine sweep, cheering mascot, spring entrance + heavy haptic, shown once.
struct TierCeremonyView: View {
    @EnvironmentObject private var app: AppModel
    let tier: String
    let seasonEarned: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = false
    @State private var bob = false

    private var tierLabel: String {
        switch tier {
        case "silver": "Hạng Bạc"
        case "gold": "Hạng Vàng"
        case "platinum": "Hạng Bạch Kim"
        default: "Hạng Đồng"
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x1D1830).ignoresSafeArea()
            ConfettiRain()

            VStack(spacing: 8) {
                Text("Cột mốc mùa · \(app.points?.season ?? "")")
                    .font(.viet(14)).foregroundStyle(Color(hex: 0xB7A5E0))
                    .padding(.top, 14)
                Spacer()

                ZStack(alignment: .top) {
                    GoldShield()
                        .frame(width: 170, height: 196)
                        .shineSweep(opacity: 0.55)
                    Mascot(mood: .cheering, bobbing: false)
                        .frame(width: 52, height: 46)
                        .offset(y: bob ? -44 : -38)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: bob
                        )
                }
                .scaleEffect(stage ? 1 : 0.6)
                .padding(.top, 26)

                Text("Lên \(tierLabel)!")
                    .font(.viet(31, .heavy)).foregroundStyle(Color(hex: 0xF5C97B))
                    .padding(.top, 10)
                Text("Tích luỹ mùa này: \(Fmt.int(seasonEarned)) điểm\nGiữ nhịp — hạng không tụt giữa mùa")
                    .font(.viet(15)).foregroundStyle(Color(hex: 0xB7A5E0))
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    ceremonyPill("Quyền lợi hạng mới đã mở")
                    ceremonyPill("Xem trong Giải đấu")
                }
                .padding(.top, 10)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { app.celebration = nil }
                } label: {
                    Text("Tuyệt vời!")
                        .font(.viet(18, .heavy)).foregroundStyle(Color(hex: 0x3A2C08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(Color(hex: 0xF5C97B))
                        .clipShape(Capsule())
                }
                .buttonStyle(PressScale())
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            Haptics.heavy()
            bob = true
            withAnimation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.8, dampingFraction: 0.65)
            ) { stage = true }
        }
    }

    private func ceremonyPill(_ text: String) -> some View {
        Text(text)
            .font(.viet(12.5, .semibold)).foregroundStyle(Theme.purpleSoft)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(hex: 0x2A2344))
            .clipShape(Capsule())
    }
}

/// The m01 gold shield with the white star.
struct GoldShield: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 120
            ZStack {
                ShieldShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF5C97B), Color(hex: 0xD4A94E)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(ShieldShape().stroke(Color(hex: 0xB8860B), lineWidth: 3))
                StarShape()
                    .fill(.white)
                    .frame(width: 48 * s, height: 48 * s)
                    .offset(y: -4 * s)
            }
        }
        .aspectRatio(120 / 138, contentMode: .fit)
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: .init(x: w * 0.5, y: h * 0.04))
        p.addLine(to: .init(x: w * 0.87, y: h * 0.16))
        p.addLine(to: .init(x: w * 0.87, y: h * 0.43))
        p.addCurve(
            to: .init(x: w * 0.5, y: h * 0.91),
            control1: .init(x: w * 0.87, y: h * 0.67),
            control2: .init(x: w * 0.7, y: h * 0.84)
        )
        p.addCurve(
            to: .init(x: w * 0.13, y: h * 0.43),
            control1: .init(x: w * 0.3, y: h * 0.84),
            control2: .init(x: w * 0.13, y: h * 0.67)
        )
        p.addLine(to: .init(x: w * 0.13, y: h * 0.16))
        p.closeSubpath()
        return p
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<10 {
            let angle = Double(i) * .pi / 5 - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : r * 0.42
            let pt = CGPoint(
                x: c.x + CGFloat(Foundation.cos(angle)) * radius,
                y: c.y + CGFloat(Foundation.sin(angle)) * radius
            )
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Level-up: badge-pop moment (350ms overshoot, ring 500ms, light haptic).
struct LevelUpView: View {
    @EnvironmentObject private var app: AppModel
    let level: Int
    @State private var ring = false

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.5).ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Theme.purpleMid.opacity(0.5), lineWidth: 3)
                        .frame(width: 116, height: 116)
                        .scaleEffect(ring ? 1.25 : 0.8)
                        .opacity(ring ? 0 : 1)
                        .animation(.easeOut(duration: 0.5), value: ring)
                    Circle().fill(Theme.purpleBg).frame(width: 104, height: 104)
                    Mascot(mood: .cheering).frame(width: 64, height: 54).offset(y: 8)
                }
                .popIn()
                Text("Lên cấp \(level)!").font(.viet(24, .heavy)).popIn(delay: 0.08)
                Text("Nhím Tím của bạn lớn thêm một chút 💜")
                    .font(.viet(14)).foregroundStyle(Theme.muted)
                PrimaryButton(title: "Chạy tiếp nào", height: 52) { dismiss() }
                    .padding(.top, 8)
            }
            .padding(EdgeInsets(top: 28, leading: 26, bottom: 24, trailing: 26))
            .background(Theme.sheetBg)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(alignment: .top) { ConfettiBurst().frame(height: 110).clipped() }
            .padding(.horizontal, 40)
        }
        .onAppear {
            Haptics.light()
            ring = true
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { app.celebration = nil }
    }
}

/// Streak milestone (3/7/14/30… days): the flame gets its moment.
struct StreakMilestoneView: View {
    @EnvironmentObject private var app: AppModel
    let days: Int
    @State private var flame = false

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.5).ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.orangeSoft, Theme.orangeDeep], startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(flame ? 1.12 : 1)
                    .rotationEffect(.degrees(flame ? 3 : -3))
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: flame)
                    .popIn()
                Text("Chuỗi \(days) ngày!").font(.viet(24, .heavy)).foregroundStyle(Theme.orangeDeep)
                Text("Đều đặn là siêu năng lực — giữ lửa nhé")
                    .font(.viet(14)).foregroundStyle(Theme.muted)
                PrimaryButton(title: "Giữ lửa 🔥", height: 52, color: Theme.orangeDeep) { dismiss() }
                    .padding(.top, 8)
            }
            .padding(EdgeInsets(top: 28, leading: 26, bottom: 24, trailing: 26))
            .background(Theme.sheetBg)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(alignment: .top) { ConfettiBurst().frame(height: 110).clipped() }
            .padding(.horizontal, 40)
        }
        .onAppear {
            Haptics.success()
            flame = true
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { app.celebration = nil }
    }
}
