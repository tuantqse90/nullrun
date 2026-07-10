import SwiftUI

/// The purple hedgehog mascot ("Nhím Tím"), traced from the prototype SVG.
/// Coordinates live in a 64×52 design space and scale to the given frame.
struct Mascot: View {
    enum Mood {
        case happy      // home header — blinking, tail wiggle vibe
        case running    // prerun / run track
        case sleeping   // locked screen
        case cheering   // summary — arms up
    }

    var mood: Mood = .happy
    var bobbing = true

    @State private var bob = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 64, geo.size.height / 52)
            ZStack {
                spikes(scale: s)
                body_(scale: s)
            }
        }
        .aspectRatio(64 / 52, contentMode: .fit)
        .offset(y: bob ? -3 : 0)
        .animation(
            bobbing ? .easeInOut(duration: mood == .running ? 0.45 : 1.6).repeatForever(autoreverses: true) : nil,
            value: bob
        )
        .onAppear { if bobbing { bob = true } }
    }

    private func spikes(scale s: CGFloat) -> some View {
        let pts: [CGPoint] = [
            .init(x: 10, y: 38), .init(x: 4, y: 28), .init(x: 12, y: 28), .init(x: 8, y: 16),
            .init(x: 18, y: 20), .init(x: 16, y: 6), .init(x: 26, y: 14), .init(x: 30, y: 2),
            .init(x: 38, y: 12), .init(x: 46, y: 6), .init(x: 46, y: 16), .init(x: 56, y: 14),
            .init(x: 50, y: 26), .init(x: 58, y: 28), .init(x: 52, y: 38),
        ]
        return Path { p in
            p.move(to: pts[0].scaled(s))
            for pt in pts.dropFirst() { p.addLine(to: pt.scaled(s)) }
            p.closeSubpath()
        }
        .fill(mood == .sleeping ? Theme.purpleDeep : Theme.purple)
    }

    @ViewBuilder
    private func body_(scale s: CGFloat) -> some View {
        ZStack {
            // body
            Ellipse()
                .fill(mood == .sleeping ? Color(hex: 0x9B82CF) : Theme.purpleSoft)
                .frame(width: 32 * s, height: 24 * s)
                .position(x: 40 * s, y: 36 * s)
            // snout
            Ellipse()
                .fill(mood == .sleeping ? Color(hex: 0x9B82CF) : Theme.purpleSoft)
                .frame(width: 12 * s, height: 8 * s)
                .rotationEffect(.degrees(12))
                .position(x: 56 * s, y: 36.5 * s)
            // nose
            Circle()
                .fill(Theme.purpleDark)
                .frame(width: 4.8 * s, height: 4.8 * s)
                .position(x: 62 * s, y: 37.5 * s)
            // eye (closed arc when sleeping)
            if mood == .sleeping {
                Path { p in
                    p.move(to: CGPoint(x: 43 * s, y: 33 * s))
                    p.addQuadCurve(to: CGPoint(x: 48 * s, y: 33 * s), control: CGPoint(x: 45.5 * s, y: 35.5 * s))
                }
                .stroke(Theme.purpleInk, style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
            } else {
                BlinkingEye()
                    .frame(width: 4.6 * s, height: 4.6 * s)
                    .position(x: 46 * s, y: 33 * s)
            }
            // cheek blush
            Circle()
                .fill(Theme.orangeSoft.opacity(0.5))
                .frame(width: 5.2 * s, height: 5.2 * s)
                .position(x: 50 * s, y: 38 * s)
            // smile when cheering
            if mood == .cheering {
                Path { p in
                    p.move(to: CGPoint(x: 42 * s, y: 41 * s))
                    p.addQuadCurve(to: CGPoint(x: 50 * s, y: 41 * s), control: CGPoint(x: 46 * s, y: 45 * s))
                }
                .stroke(Theme.purpleInk, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            }
            // legs
            RunningLegs(scale: s, animated: mood == .running || mood == .cheering)
        }
    }
}

private struct BlinkingEye: View {
    @State private var blink = false
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Theme.purpleInk)
                .scaleEffect(y: blink ? 0.15 : 1)
            Circle()
                .fill(.white)
                .frame(width: 1.6, height: 1.6)
                .offset(x: 1, y: -1)
                .opacity(blink ? 0 : 1)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation(.easeInOut(duration: 0.1)) { blink = true }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.1)) { blink = false }
            }
        }
    }
}

private struct RunningLegs: View {
    let scale: CGFloat
    let animated: Bool
    @State private var step = false

    var body: some View {
        let s = scale
        ZStack {
            leg.rotationEffect(.degrees(animated ? (step ? 26 : -26) : 0), anchor: .top)
                .position(x: 35.5 * s, y: 44.5 * s)
            leg.rotationEffect(.degrees(animated ? (step ? -26 : 26) : 0), anchor: .top)
                .position(x: 46.5 * s, y: 44.5 * s)
        }
        .animation(
            animated ? .easeInOut(duration: 0.2).repeatForever(autoreverses: true) : nil,
            value: step
        )
        .onAppear { if animated { step = true } }
    }

    private var leg: some View {
        RoundedRectangle(cornerRadius: 2.5 * scale)
            .fill(Theme.purpleMid)
            .frame(width: 5 * scale, height: 9 * scale)
    }
}
