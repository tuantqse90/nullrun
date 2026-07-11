import SwiftUI
import UIKit

// "Thú Cưng Đường Phố" — catch real street cats & dogs, Pokémon-GO style.
// Intro → camera catch game (slingshot a treat at the detected animal) →
// Sổ Bạn Nhỏ (the on-device Pokédex). All on-device; catching mints no
// activity points (economy firewall) — it's a delightful collection.

// MARK: - intro

struct CatchIntroView: View {
    @EnvironmentObject private var app: AppModel
    @State private var collection = CritterStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Đóng") { app.screen = .home }
                    .font(.viet(15)).foregroundStyle(Theme.muted)
                Spacer()
                if !collection.critters.isEmpty {
                    Button {
                        app.screen = .catchDex
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "book").font(.system(size: 12, weight: .bold))
                            Text("Sổ Bạn Nhỏ (\(collection.critters.count))").font(.viet(13, .bold))
                        }
                        .foregroundStyle(Theme.orangeDeep)
                    }
                }
            }
            .padding(.top, 6)

            Spacer()

            HStack(spacing: -18) {
                critterBubble("🐱", Theme.orangeBg)
                critterBubble("🐶", Theme.blueBg)
                critterBubble("🐟", Theme.greenBgSoft)
            }
            .popIn()

            Text("Thú Cưng\nĐường Phố")
                .font(.viet(30, .heavy)).lineSpacing(2).padding(.top, 18)
            Text("Gặp chó mèo ngoài đường? Đưa camera lên, ném \(Critter.dog.treat) xương hoặc \(Critter.cat.treat) cá để kết bạn — bắt được là lưu vào Sổ Bạn Nhỏ của bạn!")
                .font(.viet(14.5)).foregroundStyle(Theme.muted).padding(.top, 8)

            VStack(spacing: 0) {
                bullet("Nhận diện **ngay trên máy** — ảnh không tải lên đâu cả")
                Divider().overlay(Theme.divider)
                bullet("Chỉ để **sưu tầm cho vui** — không ăn điểm, không xếp hạng")
                Divider().overlay(Theme.divider)
                bullet("**Nhẹ nhàng thôi** — đừng đuổi hay dồn ép các bé nhé 🐾")
            }
            .padding(.horizontal, 18)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
            .padding(.top, 18)

            Spacer()

            PrimaryButton(title: "Bắt đầu săn bạn nhỏ", color: Theme.orange, glow: true) {
                app.screen = .catchCam
            }
            if !collection.critters.isEmpty {
                Button {
                    app.screen = .catchDex
                } label: {
                    Text("Xem \(collection.critters.count) bạn đã kết")
                        .font(.viet(14)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 12)
            }
            Color.clear.frame(height: 24)
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
    }

    private func critterBubble(_ emoji: String, _ bg: Color) -> some View {
        Text(emoji)
            .font(.system(size: 34))
            .frame(width: 66, height: 66)
            .background(bg)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill").font(.system(size: 13)).foregroundStyle(Theme.orange)
            Text(.init(markdown)).font(.viet(14))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - the catch game

struct CatchCamView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var camera = CritterCamera()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Detection with a little hysteresis so the reticle doesn't flicker.
    @State private var held: Detection?
    @State private var holdTask: Task<Void, Never>?

    // Slingshot state.
    @State private var pull: CGSize = .zero
    @State private var aiming = false
    @State private var flying = false
    @State private var throwProgress: Double = 0
    @State private var treatPos: CGPoint = .zero
    @State private var missesLeft = 3

    // Result.
    @State private var caught: CaughtCritter?
    @State private var caughtImage: UIImage?
    @State private var celebrate = false
    @State private var flashMiss = false
    @State private var cardShown = false

    private let aimGain: CGFloat = 1.9

    var body: some View {
        GeometryReader { geo in
            let cradle = CGPoint(x: geo.size.width / 2, y: geo.size.height - 130)
            ZStack {
                switch camera.state {
                case .ready:
                    CritterPreview(camera: camera).ignoresSafeArea()
                    gameOverlay(geo: geo, cradle: cradle)
                case .starting:
                    Color(hex: 0x1C1A17).ignoresSafeArea()
                    ProgressView().tint(.white)
                case .denied, .unavailable:
                    Color(hex: 0x1C1A17).ignoresSafeArea()
                    permissionNotice
                }

                if flashMiss {
                    Theme.orange.opacity(0.18).ignoresSafeArea().transition(.opacity)
                }
                if let caught {
                    caughtCard(caught).transition(.opacity.combined(with: .scale))
                }
            }
        }
        .task {
            await camera.start()
            treatPosReset()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.detection) { _, new in
            updateHeld(new)
        }
    }

    // MARK: overlay by phase

    @ViewBuilder
    private func gameOverlay(geo: GeometryProxy, cradle: CGPoint) -> some View {
        // Top status pill.
        VStack {
            HStack {
                statusPill
                Spacer()
                closeButton
            }
            .padding(.horizontal, 16).padding(.top, 8)
            Spacer()
        }

        // Reticle on the detected animal.
        if let held, let rect = camera.reticleRect(for: held.boundingBox), caught == nil {
            AnimalFrame(species: held.species)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .animation(.easeOut(duration: 0.18), value: rect)
        }

        // Slingshot + aiming, only when something is locked and not resolved.
        if held != nil, caught == nil {
            let reticle = reticlePoint(cradle: cradle, in: geo.size)

            // Aim preview: trajectory dots + landing reticle.
            if aiming {
                TrajectoryDots(from: cradle, to: reticle)
                LandingReticle(locked: lockedOn(reticle))
                    .position(reticle)
            }

            // The treat (draggable slingshot ammo, or in-flight).
            Text(species.treat)
                .font(.system(size: flying ? 40 : 46))
                .rotationEffect(.degrees(flying ? throwProgress * 520 : 0))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                .scaleEffect(aiming ? 1.15 : 1)
                .position(flying ? treatPos : cradle)
                .gesture(dragGesture(cradle: cradle, in: geo.size))
                .allowsHitTesting(!flying)

            // Aim hint.
            VStack {
                Spacer()
                Text(aiming ? "Thả ra để ném! 🎯" : "Kéo \(species.treat) xuống rồi thả để ném \(species.treatName)")
                    .font(.viet(13.5, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(.bottom, 26)
            }
        }

        if celebrate { ConfettiRain().ignoresSafeArea().allowsHitTesting(false) }
    }

    private var species: Critter { held?.species ?? .cat }

    private var statusPill: some View {
        HStack(spacing: 7) {
            if held != nil {
                Text(species == .cat ? "🐱" : "🐶").font(.system(size: 14))
                Text("Tìm thấy \(species.label)!").font(.viet(13.5, .bold)).foregroundStyle(.white)
            } else {
                PulsingDot()
                Text("Đang tìm bạn nhỏ quanh đây…").font(.viet(13, .semibold)).foregroundStyle(.white)
            }
            if held != nil {
                Text("· còn \(missesLeft) lần").font(.viet(12)).foregroundStyle(Theme.orangePale)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.black.opacity(0.42))
        .clipShape(Capsule())
    }

    private var closeButton: some View {
        Button {
            app.screen = .catchIntro
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.42))
                .clipShape(Circle())
        }
    }

    // MARK: slingshot maths

    private func reticlePoint(cradle: CGPoint, in size: CGSize) -> CGPoint {
        // Reachable over the whole playfield — a tight bottom margin here
        // would make animals in the lower third permanently un-lockable.
        let x = (cradle.x - pull.width * aimGain).clamped(24, size.width - 24)
        let y = (cradle.y - pull.height * aimGain).clamped(60, size.height - 40)
        return CGPoint(x: x, y: y)
    }

    private func lockedOn(_ reticle: CGPoint) -> Bool {
        guard let held, let rect = camera.reticleRect(for: held.boundingBox) else { return false }
        // Kawaii-fair padding around the animal.
        return rect.insetBy(dx: -rect.width * 0.25 - 20, dy: -rect.height * 0.25 - 20).contains(reticle)
    }

    private func dragGesture(cradle: CGPoint, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !flying, caught == nil else { return }
                if !aiming { aiming = true; Haptics.light() }
                let was = pull
                pull = value.translation
                // Laddered tension haptics as the pull deepens.
                if magnitude(pull) - magnitude(was) > 22 { Haptics.tick() }
            }
            .onEnded { _ in
                guard aiming, !flying else { return }
                aiming = false
                launch(cradle: cradle, in: size)
            }
    }

    private func launch(cradle: CGPoint, in size: CGSize) {
        let reticle = reticlePoint(cradle: cradle, in: size)
        let hit = lockedOn(reticle)
        // Snapshot the species NOW — the detection may flicker to nil during
        // the flight, but the catch we're resolving is for this animal.
        let species = held?.species ?? .cat
        Haptics.heavy()
        flying = true
        throwProgress = 0
        treatPos = cradle

        if reduceMotion {
            treatPos = reticle
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                await resolve(hit: hit, species: species)
            }
            return
        }

        // Parabola cradle → reticle with a lifted control point.
        let control = CGPoint(
            x: (cradle.x + reticle.x) / 2,
            y: min(cradle.y, reticle.y) - 140
        )
        Task { @MainActor in
            let start = Date()
            let dur = 0.5
            while true {
                let t = min(1, Date().timeIntervalSince(start) / dur)
                throwProgress = t
                treatPos = quadBezier(cradle, control, reticle, t)
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            await resolve(hit: hit, species: species)
        }
    }

    private func resolve(hit: Bool, species: Critter) async {
        flying = false
        pull = .zero
        if hit {
            await catchSuccess(species: species)
        } else {
            Haptics.tick()
            withAnimation(.easeOut(duration: 0.12)) { flashMiss = true }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation { flashMiss = false }
            missesLeft -= 1
            if missesLeft <= 0 {
                // The pet wanders off — no punishment, just look again.
                missesLeft = 3
                clearHeld()
            }
        }
    }

    private func catchSuccess(species: Critter) async {
        let image = (try? await camera.capture()) ?? UIImage()
        let entry = CritterStore.add(image, species: species)
        caughtImage = image
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            caught = entry
            celebrate = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { celebrate = false }
        }
    }

    // MARK: detection hysteresis

    private func updateHeld(_ new: Detection?) {
        if let new {
            held = new
            holdTask?.cancel()
        } else if held != nil, !flying {
            // Keep the last lock briefly so a one-frame miss doesn't drop it.
            // Never while a throw is in flight — clearing held mid-flight
            // would vanish the treat and swallow a valid catch.
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, !flying, camera.detection == nil else { return }
                clearHeld()
            }
        }
    }

    private func clearHeld() {
        held = nil
        aiming = false
        pull = .zero
    }

    private func treatPosReset() { treatPos = .zero }

    // MARK: result card

    private func caughtCard(_ c: CaughtCritter) -> some View {
        let r = c.rarityValue
        return ZStack {
            RadialGradient(
                colors: [r.glow.opacity(0.55), .black.opacity(0.78)],
                center: .center, startRadius: 30, endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 3) {
                    Text(rarityHeadline(r))
                        .font(.viet(15, .heavy))
                        .foregroundStyle(r.frame.first ?? .white)
                    Text("Bắt được rồi!")
                        .font(.viet(26, .heavy)).foregroundStyle(.white)
                }
                .popIn()

                HolographicCard(critter: c, image: caughtImage, width: 270)
                    .scaleEffect(cardShown ? 1 : 0.35)
                    .rotationEffect(.degrees(cardShown ? 0 : -14))
                    .opacity(cardShown ? 1 : 0)

                Text("Đã thêm vào Sổ Bạn Nhỏ · +\(r.xpReward) điểm sưu tầm")
                    .font(.viet(13, .semibold)).foregroundStyle(Color(hex: 0xE3D8F7))

                HStack(spacing: 12) {
                    Button {
                        cardShown = false
                        caught = nil
                        caughtImage = nil
                        missesLeft = 3
                        clearHeld()
                    } label: {
                        Text("Bắt tiếp").font(.viet(15, .bold)).foregroundStyle(Theme.orangeDeep)
                            .padding(.horizontal, 22).padding(.vertical, 13)
                            .background(.white).clipShape(Capsule())
                    }
                    Button {
                        app.screen = .catchDex
                    } label: {
                        Text("Xem Sổ").font(.viet(15, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 13)
                            .background(.white.opacity(0.2)).clipShape(Capsule())
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.15)) {
                cardShown = true
            }
        }
    }

    private func rarityHeadline(_ r: CritterRarity) -> String {
        switch r {
        case .common: "⭐ Đã kết bạn"
        case .rare: "✨ HIẾM ✨"
        case .epic: "💎 CỰC HIẾM 💎"
        case .legendary: "👑 HUYỀN THOẠI 👑"
        }
    }

    private var permissionNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.slash").font(.system(size: 30)).foregroundStyle(Theme.darkDim)
            Text(camera.state == .denied
                 ? "Cần quyền camera để săn bạn nhỏ — bật trong Cài đặt."
                 : "Camera không khả dụng trên thiết bị này.")
                .font(.viet(14.5)).foregroundStyle(.white).multilineTextAlignment(.center)
            if camera.state == .denied {
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.viet(14, .bold)).foregroundStyle(Theme.orangeSoft)
            }
            Button("Đóng") { app.screen = .catchIntro }
                .font(.viet(13)).foregroundStyle(Theme.darkDim)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - game bits

/// Rounded "paw-tab" frame that pops around the detected animal.
private struct AnimalFrame: View {
    let species: Critter
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.greenBright, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [10, 8]))
            .overlay(alignment: .topLeading) {
                Text(species == .cat ? "🐱" : "🐶")
                    .font(.system(size: 18))
                    .padding(6)
                    .background(Theme.greenBright)
                    .clipShape(Circle())
                    .offset(x: -8, y: -8)
            }
            .scaleEffect(pulse ? 1.03 : 0.97)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

private struct TrajectoryDots: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 140)
        ForEach(1..<12, id: \.self) { i in
            let t = Double(i) / 12
            let p = quadBezier(from, control, to, t)
            Circle()
                .fill(.white.opacity(0.85 - t * 0.5))
                .frame(width: 7 - CGFloat(t) * 3, height: 7 - CGFloat(t) * 3)
                .position(p)
        }
    }
}

private struct LandingReticle: View {
    let locked: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(locked ? Theme.greenBright : .white, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: spin)
            Circle().fill(locked ? Theme.greenBright : .white).frame(width: 8, height: 8)
        }
        .onAppear { spin = true }
    }
}

// MARK: - Sổ Bạn Nhỏ (Pokédex)

struct CritterDexView: View {
    @EnvironmentObject private var app: AppModel
    @State private var collection = CritterStore.load()
    @State private var selected: CaughtCritter?

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            dexBody
            if let selected {
                cardDetail(selected)
            }
        }
        #if DEBUG
        .onAppear {
            // Design-QA: auto-open the first card's detail.
            if ProcessInfo.processInfo.environment["DEV_CARD"] != nil {
                selected = collection.critters.first
            }
        }
        #endif
    }

    private var dexBody: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sổ Bạn Nhỏ").font(.viet(23, .bold))
                    Text("\(collection.critters.count) bạn · \(collection.catCount) 🐱 · \(collection.dogCount) 🐶")
                        .font(.viet(13.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    app.screen = .catchIntro
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 40, height: 40)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
                }
            }
            .padding(.horizontal, 20).padding(.top, 6)

            ScrollView {
                VStack(spacing: 14) {
                    collectorCard.padding(.horizontal, 20).padding(.top, 12)
                    if collection.critters.isEmpty {
                        emptyState.padding(.top, 40)
                    } else {
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(Array(collection.critters.enumerated()), id: \.element.id) { i, c in
                                GeometryReader { geo in
                                    CritterCard(critter: c, image: CritterStore.image(c), width: geo.size.width, animateHolo: false)
                                }
                                .aspectRatio(1 / 1.42, contentMode: .fit)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Haptics.light()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { selected = c }
                                }
                                .riseIn(min(i, 6))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
            }

            PrimaryButton(title: "Săn thêm bạn nhỏ", color: Theme.orange, glow: true) {
                app.screen = .catchCam
            }
            .padding(.horizontal, 20).padding(.bottom, 22)
        }
        .background(Theme.bg)
    }

    private var collectorCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nhà sưu tầm cấp \(collection.collectorLevel)")
                        .font(.viet(17, .heavy)).foregroundStyle(.white)
                    Text("Sưu tầm cho vui — không đổi được quà, chỉ để khoe 🐾")
                        .font(.viet(12)).foregroundStyle(Color(hex: 0xFFE3AC))
                }
                Spacer()
                Text("🏅").font(.system(size: 34))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * Double(collection.xpInLevel) / 100.0)
                }
            }
            .frame(height: 8)
            if !collection.badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(collection.badges, id: \.self) { b in
                            Text(b).font(.viet(11.5, .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .background(LinearGradient(colors: [Theme.orangeDeep, Theme.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Full-screen holographic card viewer — drag to tilt it in 3D.
    private func cardDetail(_ c: CaughtCritter) -> some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
                .onTapGesture { withAnimation { selected = nil } }
            VStack(spacing: 18) {
                HolographicCard(critter: c, image: CritterStore.image(c), width: 300)
                Text("Nghiêng thẻ để xem hiệu ứng ✨")
                    .font(.viet(12.5)).foregroundStyle(.white.opacity(0.7))
                Button {
                    withAnimation { selected = nil }
                } label: {
                    Text("Đóng").font(.viet(15, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(.white.opacity(0.2)).clipShape(Capsule())
                }
            }
        }
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🐾").font(.system(size: 56))
            Text("Chưa có bạn nào cả").font(.viet(18, .bold))
            Text("Ra đường gặp chó mèo là bắt được liền!")
                .font(.viet(14)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: - helpers

private func quadBezier(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: Double) -> CGPoint {
    let u = 1 - t
    let x = u * u * a.x + 2 * u * t * b.x + t * t * c.x
    let y = u * u * a.y + 2 * u * t * b.y + t * t * c.y
    return CGPoint(x: x, y: y)
}

private func magnitude(_ s: CGSize) -> CGFloat { sqrt(s.width * s.width + s.height * s.height) }

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(hi, Swift.max(lo, self)) }
}
