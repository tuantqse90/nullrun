import SwiftUI
import UIKit

// A Pokémon-TCG-style collectible card for a caught street pet: rarity-tinted
// frame, photo window, type badge, collector number, flavour line, and a
// holographic shine for rare+ cards. HolographicCard adds drag-to-tilt 3D so
// the holo shifts as you move it — the "wow" moment on catch and in the dex.

enum CritterRarity: String, Codable, CaseIterable {
    case common, rare, epic, legendary

    var label: String {
        switch self {
        case .common: "Thường"
        case .rare: "Hiếm"
        case .epic: "Cực hiếm"
        case .legendary: "Huyền thoại"
        }
    }

    var stars: Int {
        switch self {
        case .common: 1
        case .rare: 2
        case .epic: 3
        case .legendary: 4
        }
    }

    var holo: Bool { self != .common }

    /// Frame gradient.
    var frame: [Color] {
        switch self {
        case .common: [Color(hex: 0xBFD8C8), Color(hex: 0xE9E3D7)]
        case .rare: [Color(hex: 0x6FA8DC), Color(hex: 0xB6D2F0)]
        case .epic: [Theme.purpleMid, Color(hex: 0xC8B3EE)]
        case .legendary: [Color(hex: 0xF5C97B), Color(hex: 0xFFE9BE)]
        }
    }

    var glow: Color {
        switch self {
        case .common: Color(hex: 0x9BB6A6).opacity(0.4)
        case .rare: Color(hex: 0x6FA8DC).opacity(0.55)
        case .epic: Theme.purpleMid.opacity(0.6)
        case .legendary: Color(hex: 0xF5C97B).opacity(0.75)
        }
    }

    var accent: Color {
        switch self {
        case .common: Theme.greenDeep
        case .rare: Color(hex: 0x2E6DB4)
        case .epic: Theme.purpleDeep
        case .legendary: Color(hex: 0xB8860B)
        }
    }

    /// Weighted roll — legendary is a genuine thrill.
    static func roll() -> CritterRarity {
        let r = Double.random(in: 0..<1)
        switch r {
        case ..<0.60: return .common
        case ..<0.85: return .rare
        case ..<0.97: return .epic
        default: return .legendary
        }
    }

    var xpReward: Int {
        switch self {
        case .common: 10
        case .rare: 15
        case .epic: 25
        case .legendary: 50
        }
    }
}

private let catFlavors = [
    "Chuyên gia nằm phơi nắng ☀️", "Ngủ 16 tiếng một ngày là chuyện nhỏ 😴",
    "Đòi ăn lúc 3 giờ sáng 🌙", "Kêu meo meo đòi vuốt ve 🫶",
    "Chúa tể của những chiếc hộp 📦", "Săn tia laser bất bại 🔴",
]
private let dogFlavors = [
    "Vẫy đuôi hết công suất 🌀", "Bạn thân của mọi shipper 📦",
    "Đi dạo là niềm vui lớn nhất 🦮", "Nhặt bóng chuyên nghiệp 🎾",
    "Canh nhà 24/7 không lương 🏠", "Cười tít mắt khi được xoa đầu 😄",
]

extension CaughtCritter {
    var rarityValue: CritterRarity { CritterRarity(rawValue: rarity ?? "common") ?? .common }
    var displayNumber: Int { number ?? 0 }
    var flavor: String {
        let pool = species == "cat" ? catFlavors : dogFlavors
        return pool[Int(id.uuid.0) % pool.count]
    }
    var typeLabel: String { species == "cat" ? "Mèo phố" : "Cún phố" }
}

/// The static card face. `width` drives the whole layout so the same card
/// works small (dex grid) and large (catch reveal).
struct CritterCard: View {
    let critter: CaughtCritter
    let image: UIImage?
    var width: CGFloat = 300
    var animateHolo = true

    private var r: CritterRarity { critter.rarityValue }
    private var s: CGFloat { width / 300 }

    var body: some View {
        VStack(spacing: 8 * s) {
            header
            photoWindow
            infoRow
            Text("“\(critter.flavor)”")
                .font(.viet(11.5 * s)).foregroundStyle(Theme.muted)
                .italic()
                .lineLimit(2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .padding(EdgeInsets(top: 11 * s, leading: 12 * s, bottom: 11 * s, trailing: 12 * s))
        .frame(width: width, height: width * 1.42)
        .background(
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .fill(LinearGradient(colors: [Theme.sheetBg, .white], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: r.frame, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 5 * s
                )
        )
        .overlay {
            if r.holo {
                HoloSheen(rarity: r, animate: animateHolo)
                    .clipShape(RoundedRectangle(cornerRadius: 22 * s, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: r.glow, radius: 18 * s, y: 8 * s)
    }

    private var header: some View {
        HStack(spacing: 6 * s) {
            Text(critter.nickname)
                .font(.viet(17 * s, .heavy)).foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { i in
                    Image(systemName: i < r.stars ? "star.fill" : "star")
                        .font(.system(size: 11 * s, weight: .bold))
                        .foregroundStyle(i < r.stars ? r.accent : Theme.hairline)
                }
            }
        }
    }

    private var photoWindow: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: r.frame, startPoint: .top, endPoint: .bottom)
                        .overlay { Text(critter.critter.treat).font(.system(size: 54 * s)) }
                }
            }
            .frame(width: width - 24 * s, height: width * 0.78)
            .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .strokeBorder(.white, lineWidth: 2.5 * s)
            )

            // species emblem
            Text(critter.species == "cat" ? "🐱" : "🐶")
                .font(.system(size: 16 * s))
                .padding(6 * s)
                .background(.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .offset(x: 8 * s, y: 8 * s)

            // rarity ribbon
            VStack {
                HStack {
                    Spacer()
                    Text(r.label.uppercased())
                        .font(.viet(9.5 * s, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8 * s).padding(.vertical, 4 * s)
                        .background(r.accent)
                        .clipShape(Capsule())
                        .offset(x: -8 * s, y: 8 * s)
                }
                Spacer()
            }
        }
        .frame(height: width * 0.78)
    }

    private var infoRow: some View {
        HStack {
            HStack(spacing: 5 * s) {
                Text(critter.critter.treat).font(.system(size: 13 * s))
                Text(critter.typeLabel).font(.viet(12.5 * s, .bold)).foregroundStyle(r.accent)
            }
            .padding(.horizontal, 9 * s).padding(.vertical, 5 * s)
            .background(r.frame.first?.opacity(0.28) ?? Theme.dimBg)
            .clipShape(Capsule())
            Spacer()
            Text(String(format: "#%03d", critter.displayNumber))
                .font(.mono(13 * s, .bold)).foregroundStyle(Theme.faint)
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: "pawprint.fill").font(.system(size: 10 * s)).foregroundStyle(Theme.faint)
            Text("Bắt ngày \(Self.date(critter.caughtAt))")
                .font(.viet(10.5 * s)).foregroundStyle(Theme.faint)
            Spacer()
            Text("Sổ Bạn Nhỏ").font(.viet(9.5 * s, .bold)).foregroundStyle(Theme.faint)
        }
    }

    private static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "d/M/yyyy"
        return f.string(from: d)
    }
}

/// Dex-grid cell: renders a CritterCard sized to its slot, loading a
/// downsampled thumbnail off the main thread (full-res decode per cell janks
/// the scroll). Shows the card's built-in gradient placeholder until ready.
struct CritterThumb: View {
    let critter: CaughtCritter
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            CritterCard(critter: critter, image: image, width: geo.size.width, animateHolo: false)
        }
        .task(id: critter.id) {
            guard image == nil else { return }
            let c = critter
            let img = await Task.detached(priority: .utility) { CritterStore.thumbnail(c) }.value
            if !Task.isCancelled { image = img }
        }
    }
}

/// A big, interactive card: drag to tilt it in 3D and the holo highlight
/// tracks your finger. Used for the catch reveal and the dex detail view.
struct HolographicCard: View {
    let critter: CaughtCritter
    let image: UIImage?
    var width: CGFloat = 300

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var idle = false

    private var r: CritterRarity { critter.rarityValue }

    var body: some View {
        ZStack {
            CritterCard(critter: critter, image: image, width: width, animateHolo: drag == .zero)
            if r.holo {
                HoloSheen(rarity: r, animate: false, tilt: drag)
                    .clipShape(RoundedRectangle(cornerRadius: 22 * (width / 300), style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .rotation3DEffect(.degrees(Double(drag.width / 14)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(-drag.height / 18)), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(idle ? 2.5 : -2.5), axis: (x: 0, y: 1, z: 0))
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { drag = .zero } }
        )
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: idle)
        .onAppear { if !reduceMotion { idle = true } }
    }
}

/// Holographic sheen — a moving diagonal light band, plus a rainbow shimmer
/// for legendary. `tilt` lets the parent shift the highlight with device/drag.
struct HoloSheen: View {
    let rarity: CritterRarity
    var animate = true
    var tilt: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // rainbow shimmer for legendary (and a hint on epic)
                if rarity == .legendary || rarity == .epic {
                    AngularGradient(
                        colors: [.pink.opacity(0.25), .blue.opacity(0.25), .green.opacity(0.25),
                                 .yellow.opacity(0.25), .pink.opacity(0.25)],
                        center: .center
                    )
                    .blendMode(.plusLighter)
                    .opacity(rarity == .legendary ? 0.5 : 0.28)
                    .offset(x: tilt.width * 0.4, y: tilt.height * 0.4)
                }

                // moving light band
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 0.5)
                .rotationEffect(.degrees(24))
                .offset(x: bandX(geo.size.width))
                .blendMode(.plusLighter)
                .animation(
                    tilt == .zero && animate && !reduceMotion
                        ? .easeInOut(duration: 2.4).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.1),
                    value: sweep
                )
            }
        }
        .onAppear { if animate && !reduceMotion { sweep = true } }
    }

    private func bandX(_ w: CGFloat) -> CGFloat {
        // Driven by tilt if present, else an auto sweep.
        if tilt != .zero {
            return (tilt.width / 40) * w * 0.4
        }
        return sweep ? w * 0.9 : -w * 0.9
    }
}
