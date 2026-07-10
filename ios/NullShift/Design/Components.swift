import SwiftUI

extension CGPoint {
    func scaled(_ s: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
}

/// White rounded card with the design's soft shadow.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 20
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
    }
}

extension View {
    func card(radius: CGFloat = 20, padding: EdgeInsets = EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }
}

/// Big green pill CTA — the design's primary button.
struct PrimaryButton: View {
    let title: String
    var height: CGFloat = 60
    var color: Color = Theme.green
    var icon: String? = nil
    var glow = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 17, weight: .bold)) }
                Text(title).font(.viet(height >= 64 ? 19 : 17, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(color)
            .clipShape(Capsule())
            .shadow(color: glow ? color.opacity(0.32) : .clear, radius: 9, y: 6)
        }
        .buttonStyle(PressScale())
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Circular progress ring (weekly goal, hold-to-stop, scan).
/// dd6: fills once over 500ms ease-in-out when the screen opens, no loop.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 11
    var trackColor: Color = Theme.track
    var gradient: [Color] = [Theme.greenBright, Theme.greenDeep]

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: appeared ? min(1, max(0, progress)) : 0)
                .stroke(
                    AngularGradient(colors: gradient, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: appeared)
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .onAppear { appeared = true }
    }
}

/// The little glowing dot orbiting the weekly ring (prototype ptSpin).
struct OrbitingSpark: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        if !reduceMotion {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.greenBright.opacity(0.65), radius: 4)
                .offset(y: -radius)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 5.5).repeatForever(autoreverses: false), value: spin)
                .onAppear { spin = true }
                .allowsHitTesting(false)
        }
    }
}

/// The streak flame pill from the home header.
struct StreakPill: View {
    let days: Int
    @State private var flame = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.orange)
                .scaleEffect(flame ? 1.16 : 1)
                .rotationEffect(.degrees(flame ? 3 : -2))
                .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: flame)
            Text("\(days)").font(.mono(14))
            Text("ngày").font(.viet(13.5, .semibold))
        }
        .foregroundStyle(Theme.orangeDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.orangeBg)
        .clipShape(Capsule())
        .onAppear { flame = true }
    }
}

/// Bottom tab bar: Hôm nay · Giải đấu · Thưởng · Hội · Cơ thể.
enum Tab: String, CaseIterable {
    case today, league, rewards, guild, body

    var label: String {
        switch self {
        case .today: "Hôm nay"
        case .league: "Giải đấu"
        case .rewards: "Thưởng"
        case .guild: "Hội"
        case .body: "Cơ thể"
        }
    }

    var icon: String {
        switch self {
        case .today: "house"
        case .league: "trophy"
        case .rewards: "gift"
        case .guild: "person.2"
        case .body: "person.crop.circle"
        }
    }

    var enabled: Bool { true }
}

struct AppTabBar: View {
    let active: Tab
    let onSelect: (Tab) -> Void
    @State private var bounced: Tab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                VStack(spacing: 4) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .regular))
                        .scaleEffect(bounced == tab ? 1.25 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: bounced)
                    Text(tab.label)
                        .font(.viet(10.5, tab == active ? .semibold : .medium))
                }
                .foregroundStyle(tab == active ? Theme.green : Theme.faint)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard tab.enabled else { return }
                    Haptics.light()
                    bounced = tab
                    onSelect(tab)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.white.opacity(0.92))
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }
}

/// Confetti burst used on summary + wheel result.
struct ConfettiBurst: View {
    @State private var fall = false
    private let pieces: [(x: CGFloat, size: CGFloat, color: Color, delay: Double, circle: Bool)] = [
        (0.12, 6, Theme.blue, 0.40, true), (0.22, 8, Theme.orange, 0.10, false),
        (0.30, 9, Theme.orangeSoft, 0.50, false), (0.38, 7, Theme.green, 0.25, true),
        (0.48, 6, Theme.orangeDeep, 0.60, true), (0.56, 8, Theme.blue, 0.05, false),
        (0.64, 8, Theme.green, 0.45, false), (0.72, 6, Theme.orange, 0.35, true),
        (0.86, 7, Theme.green, 0.18, false), (0.94, 6, Theme.orange, 0.30, true),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                Group {
                    if p.circle {
                        Circle().fill(p.color)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(p.color)
                    }
                }
                .frame(width: p.size, height: p.size)
                .position(x: geo.size.width * p.x, y: 0)
                .offset(y: fall ? 150 : -8)
                .rotationEffect(.degrees(fall ? 220 : 0))
                .opacity(fall ? 0 : 1)
                .animation(.easeIn(duration: 1.4).delay(p.delay), value: fall)
            }
        }
        .allowsHitTesting(false)
        .onAppear { fall = true }
    }
}
