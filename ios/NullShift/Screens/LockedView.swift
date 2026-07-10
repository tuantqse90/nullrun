import SwiftUI

/// Locked tracking screen — anti-pocket-touch, slide to unlock.
struct LockedView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var tracker: RunTracker
    @State private var breathe = false
    @State private var slideOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock").font(.system(size: 13, weight: .semibold))
                Text("Màn hình đã khoá").font(.viet(13.5, .semibold))
            }
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Theme.darkCard)
            .clipShape(Capsule())
            .scaleEffect(breathe ? 1.05 : 1)
            .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: breathe)
            .padding(.top, 10)

            Spacer()

            Text(Fmt.dist(tracker.distanceKm))
                .font(.mono(96)).kerning(-3).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text("km").font(.viet(16)).foregroundStyle(Theme.faint)

            HStack(spacing: 28) {
                VStack(spacing: 0) {
                    Text(Fmt.time(tracker.seconds)).font(.mono(27)).foregroundStyle(.white)
                    Text("Thời gian").font(.viet(12.5)).foregroundStyle(Theme.faint)
                }
                VStack(spacing: 0) {
                    Text("+\(tracker.livePoints)").font(.mono(27)).foregroundStyle(Theme.greenBright)
                    Text("Điểm").font(.viet(12.5)).foregroundStyle(Theme.faint)
                }
            }
            .padding(.top, 22)

            HStack(alignment: .bottom, spacing: 4) {
                Mascot(mood: .sleeping, bobbing: false).frame(width: 58, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    FloatingZ(delay: 0, size: 13, color: Theme.purpleMid)
                    FloatingZ(delay: 1.1, size: 10, color: Theme.darkDim)
                }
                .frame(height: 30)
            }
            .padding(.top, 30)
            .scaleEffect(breathe ? 1.04 : 1)
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: breathe)

            Spacer()

            VStack(spacing: 12) {
                slideToUnlock
                Text("Tự khoá để chống chạm nhầm khi chạy")
                    .font(.viet(12.5)).foregroundStyle(Theme.darkDim)
            }
            .padding(.bottom, 60)
        }
        .padding(.horizontal, 24)
        .background(Theme.darkBg)
        .overlay(sparkles)
        .onAppear { breathe = true }
    }

    private var slideToUnlock: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - 64
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.darkCard)
                    .overlay(Capsule().strokeBorder(Theme.darkLine, lineWidth: 1))
                Text("Trượt để mở khoá")
                    .font(.viet(15)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                Circle()
                    .fill(Theme.darkInk)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.darkBg)
                    }
                    .offset(x: 6 + slideOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                slideOffset = min(max(0, v.translation.width), maxOffset - 12)
                            }
                            .onEnded { _ in
                                if slideOffset > maxOffset * 0.6 {
                                    app.screen = .run
                                }
                                withAnimation(.spring(duration: 0.3)) { slideOffset = 0 }
                            }
                    )
            }
        }
        .frame(height: 64)
    }

    private var sparkles: some View {
        ZStack {
            Twinkle(size: 12, color: Theme.darkDim, duration: 2.6).offset(x: -130, y: -220)
            Twinkle(size: 9, color: Theme.purpleMid, duration: 3.2).offset(x: 110, y: -170)
            Twinkle(size: 8, color: Theme.darkDim, duration: 2.2).offset(x: -80, y: -130)
            Image(systemName: "moon.fill")
                .font(.system(size: 26)).foregroundStyle(Theme.purpleMid.opacity(0.55))
                .offset(x: 130, y: -260)
        }
        .allowsHitTesting(false)
    }
}

struct FloatingZ: View {
    let delay: Double
    let size: CGFloat
    let color: Color
    @State private var rise = false

    var body: some View {
        Text("z")
            .font(.viet(size, .bold)).foregroundStyle(color)
            .offset(y: rise ? -11 : 3)
            .opacity(rise ? 0 : 0.9)
            .animation(.easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(delay), value: rise)
            .onAppear { rise = true }
    }
}

struct Twinkle: View {
    let size: CGFloat
    let color: Color
    let duration: Double
    @State private var on = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size))
            .foregroundStyle(color)
            .scaleEffect(on ? 1.15 : 0.55)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
