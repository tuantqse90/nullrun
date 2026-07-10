import SwiftUI
import UIKit

// Motion kit per the design's dd6 spec:
// point count-up 600ms with soft haptic ticks · confetti 900ms + success
// haptic · promotion banner spring 800ms + heavy haptic · badge pop 350ms
// overshoot · progress rings 500ms ease-in-out on appear · Reduce Motion
// swaps every spring/confetti for a 150ms fade. Celebration lives ONLY on
// points/rank/badges — body-measurement surfaces stay static.

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func tick() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}

/// Staggered entrance: rise 24pt + fade, 300ms ease-out (ptRise).
struct RiseIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .onAppear {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .easeOut(duration: 0.3).delay(delay)
                ) { shown = true }
            }
    }
}

extension View {
    func riseIn(_ index: Int) -> some View {
        modifier(RiseIn(delay: Double(index) * 0.06))
    }
}

/// Looping white shine sweep (ptShine) — for reward/points cards.
struct ShineSweep: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = .white
    var opacity: Double = 0.5
    @State private var sweep = false

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, tint.opacity(opacity), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 52)
                    .rotationEffect(.degrees(14))
                    .offset(x: sweep ? geo.size.width + 60 : -80)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false), value: sweep)
                }
                .allowsHitTesting(false)
                .clipped()
                .onAppear { sweep = true }
            }
        }
    }
}

extension View {
    func shineSweep(tint: Color = .white, opacity: Double = 0.5) -> some View {
        modifier(ShineSweep(tint: tint, opacity: opacity))
    }
}

/// Badge pop: 350ms with overshoot (dd6 "huy hiệu mới").
struct PopIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : (reduceMotion ? 1 : 0.3))
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.35, dampingFraction: 0.55).delay(delay)
                ) { shown = true }
            }
    }
}

extension View {
    func popIn(delay: Double = 0) -> some View {
        modifier(PopIn(delay: delay))
    }
}

/// Count-up number: 600ms ease-out with a soft haptic tick every ~40ms.
struct CountUpText: View {
    let target: Int
    var prefix: String = "+"
    var font: Font = .mono(40)
    var color: Color = Theme.greenDeep
    var haptics = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text("\(prefix)\(shown)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .task { await run() }
    }

    private func run() async {
        guard target > 0 else { return }
        if reduceMotion {
            shown = target
            return
        }
        let start = Date()
        while !Task.isCancelled {
            let k = min(1, Date().timeIntervalSince(start) / 0.6)
            let eased = 1 - pow(1 - k, 3)
            let next = Int(Double(target) * eased)
            if next != shown, haptics { Haptics.tick() }
            shown = next
            if k >= 1 { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        shown = target
    }
}

/// Continuous falling confetti (m01 ceremony backdrop) — loops until removed.
struct ConfettiRain: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var colors: [Color] = [Color(hex: 0xF5C97B), Theme.purpleMid, Theme.greenBright, Theme.orangeSoft]
    @State private var t = false

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<14, id: \.self) { i in
                let x = CGFloat((i * 79) % 100) / 100
                let size = CGFloat(5 + (i * 37) % 5)
                let dur = 1.6 + Double((i * 53) % 60) / 100
                Group {
                    if i.isMultiple(of: 2) {
                        RoundedRectangle(cornerRadius: 2).fill(colors[i % colors.count])
                    } else {
                        Circle().fill(colors[i % colors.count])
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width * x, y: -10)
                .offset(y: t ? geo.size.height * 0.55 : 0)
                .rotationEffect(.degrees(t ? 260 : 0))
                .opacity(t ? 0 : 0.95)
                .animation(
                    reduceMotion ? nil
                        : .easeIn(duration: dur).repeatForever(autoreverses: false).delay(Double((i * 41) % 90) / 100),
                    value: t
                )
            }
        }
        .allowsHitTesting(false)
        .onAppear { t = true }
        .opacity(reduceMotion ? 0 : 1)
    }
}
