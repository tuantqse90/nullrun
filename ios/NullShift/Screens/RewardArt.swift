import SwiftUI

// Hand-drawn (SwiftUI vector) artwork for reward cards — a small illustrated
// scene per reward kind on a brand-gradient backdrop. Crisp at any size, no
// image assets. Replaces the flat SF-Symbol tiles so the catalog feels
// designed. Colours come from the reward's partner brand.

enum RewardArtKind {
    case topup, toll, car, fuel, ev, coffee, service, parking, shield, merch, ticket, gift

    static func of(_ reward: Reward) -> RewardArtKind {
        let t = reward.title.lowercased()
        let d = (t + " " + (reward.description ?? "")).lowercased()
        if t.contains("nạp ví") || t.contains("t-money") { return .topup }
        if t.contains("vé tháng") || t.contains("vé năm") || t.contains("qua trạm")
            || t.contains("làn ưu tiên") || t.contains("thu phí") { return .toll }
        if t.contains("thuê xe") || t.contains("tự lái") || t.contains("tài xế")
            || t.contains("đưa đón") || t.contains("đặt xe") { return .car }
        if d.contains("sạc") { return .ev }
        if t.contains("xăng") { return .fuel }
        if t.contains("dầu") || t.contains("bảo dưỡng") || t.contains("lốp")
            || t.contains("khám xe") || t.contains("chăm xe") || t.contains("rửa xe") { return .service }
        if t.contains("đỗ xe") || t.contains("bãi đỗ") || t.contains("parking") { return .parking }
        if t.contains("cà phê") || t.contains("đồ ăn") || t.contains("suất ăn")
            || t.contains("combo") || t.contains("nghỉ chân") { return .coffee }
        if t.contains("bảo hiểm") { return .shield }
        if t.contains("sticker") || t.contains("bình") || t.contains("áo") { return .merch }
        if reward.isVoucher { return .ticket }
        return .gift
    }
}

/// Illustrated card artwork. Height matches the old tile (70).
struct RewardArt: View {
    let reward: Reward
    var height: CGFloat = 70

    private var brand: RewardBrand { reward.brand }
    private var kind: RewardArtKind { RewardArtKind.of(reward) }
    private var accent: Color { brand.color }
    private var deep: Color { brand.color.mix(with: .black, amount: 0.38) }

    var body: some View {
        ZStack {
            // brand-gradient sky + a soft light blob
            LinearGradient(
                colors: [accent.opacity(0.24), accent.opacity(0.09)],
                startPoint: .top, endPoint: .bottom
            )
            GeometryReader { g in
                Circle().fill(.white.opacity(0.35))
                    .frame(width: g.size.width * 0.5)
                    .blur(radius: 10)
                    .position(x: g.size.width * 0.82, y: g.size.height * 0.18)
            }
            GeometryReader { g in scene(in: g.size) }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private func scene(in s: CGSize) -> some View {
        switch kind {
        case .topup: topup(s)
        case .toll: toll(s)
        case .car: car(s)
        case .fuel: fuel(s)
        case .ev: ev(s)
        case .coffee: coffee(s)
        case .service: service(s)
        case .parking: parking(s)
        case .shield: shield(s)
        case .merch: merch(s)
        case .ticket: ticket(s)
        case .gift: gift(s)
        }
    }

    // ground line shared by "vehicle on a road" scenes
    private func ground(_ s: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(accent.opacity(0.22))
            .frame(width: s.width, height: 5)
            .position(x: s.width / 2, y: s.height * 0.9)
    }

    // MARK: scenes

    private func topup(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            // stacked card
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(deep.opacity(0.35))
                .frame(width: w * 0.52, height: h * 0.42)
                .rotationEffect(.degrees(-9))
                .position(x: w * 0.44, y: h * 0.56)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent)
                .frame(width: w * 0.52, height: h * 0.42)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.85)).frame(height: 5).padding(.top, 6)
                }
                .rotationEffect(.degrees(4))
                .position(x: w * 0.5, y: h * 0.52)
            // + coin (kept low-left so it clears the denomination badge)
            Circle().fill(.white)
                .frame(width: h * 0.32, height: h * 0.32)
                .overlay { Image(systemName: "plus").font(.system(size: h * 0.17, weight: .black)).foregroundStyle(accent) }
                .position(x: w * 0.24, y: h * 0.72)
        }
    }

    private func toll(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            // receding road
            Path { p in
                p.move(to: .init(x: w * 0.32, y: h))
                p.addLine(to: .init(x: w * 0.44, y: h * 0.28))
                p.addLine(to: .init(x: w * 0.56, y: h * 0.28))
                p.addLine(to: .init(x: w * 0.68, y: h))
            }.fill(deep.opacity(0.30))
            // dashes
            Path { p in
                for i in 0..<3 {
                    let t = 0.32 + Double(i) * 0.22
                    p.move(to: .init(x: w * 0.5, y: h * (t)))
                    p.addLine(to: .init(x: w * 0.5, y: h * (t + 0.09)))
                }
            }.stroke(.white.opacity(0.9), style: .init(lineWidth: 2.4, lineCap: .round))
            // ETC gantry
            RoundedRectangle(cornerRadius: 2).fill(accent)
                .frame(width: w * 0.5, height: 6).position(x: w * 0.5, y: h * 0.22)
            ForEach([0.28, 0.72], id: \.self) { fx in
                RoundedRectangle(cornerRadius: 2).fill(accent)
                    .frame(width: 5, height: h * 0.3).position(x: w * fx, y: h * 0.37)
            }
            // green pass light
            Circle().fill(Color(hex: 0x34B37D)).frame(width: 9, height: 9).position(x: w * 0.5, y: h * 0.22)
        }
    }

    private func car(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            ground(s)
            // body
            RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                .fill(accent)
                .frame(width: w * 0.72, height: h * 0.32)
                .position(x: w * 0.5, y: h * 0.62)
            // cabin
            Path { p in
                p.move(to: .init(x: w * 0.34, y: h * 0.47))
                p.addLine(to: .init(x: w * 0.42, y: h * 0.24))
                p.addLine(to: .init(x: w * 0.6, y: h * 0.24))
                p.addLine(to: .init(x: w * 0.68, y: h * 0.47))
            }.fill(accent)
            // windows
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9))
                .frame(width: w * 0.22, height: h * 0.16).position(x: w * 0.5, y: h * 0.37)
            // wheels
            ForEach([0.36, 0.64], id: \.self) { fx in
                Circle().fill(deep).frame(width: h * 0.2, height: h * 0.2)
                    .overlay { Circle().fill(.white.opacity(0.8)).frame(width: h * 0.07, height: h * 0.07) }
                    .position(x: w * fx, y: h * 0.78)
            }
            // headlight
            Capsule().fill(.white).frame(width: 6, height: 4).position(x: w * 0.83, y: h * 0.58)
        }
    }

    private func fuel(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            ground(s)
            // pump body
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(accent)
                .frame(width: w * 0.3, height: h * 0.56).position(x: w * 0.42, y: h * 0.52)
            // screen
            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.9))
                .frame(width: w * 0.18, height: h * 0.16).position(x: w * 0.42, y: h * 0.38)
            // nozzle + hose
            Path { p in
                p.move(to: .init(x: w * 0.57, y: h * 0.42))
                p.addQuadCurve(to: .init(x: w * 0.66, y: h * 0.62), control: .init(x: w * 0.72, y: h * 0.42))
            }.stroke(deep, style: .init(lineWidth: 4, lineCap: .round))
            RoundedRectangle(cornerRadius: 2).fill(deep)
                .frame(width: w * 0.06, height: h * 0.18).position(x: w * 0.66, y: h * 0.68)
            // drop
            Image(systemName: "drop.fill").font(.system(size: h * 0.18)).foregroundStyle(.white)
                .position(x: w * 0.66, y: h * 0.9)
        }
    }

    private func ev(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            car(s).opacity(0.001) // reserve layout; draw a simpler car
            ground(s)
            RoundedRectangle(cornerRadius: h * 0.18, style: .continuous).fill(accent)
                .frame(width: w * 0.6, height: h * 0.3).position(x: w * 0.46, y: h * 0.62)
            ForEach([0.34, 0.58], id: \.self) { fx in
                Circle().fill(deep).frame(width: h * 0.18, height: h * 0.18).position(x: w * fx, y: h * 0.78)
            }
            // charge bolt badge
            Circle().fill(.white).frame(width: h * 0.42, height: h * 0.42)
                .overlay { Image(systemName: "bolt.fill").font(.system(size: h * 0.22, weight: .black)).foregroundStyle(accent) }
                .position(x: w * 0.78, y: h * 0.34)
        }
    }

    private func coffee(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            // steam
            ForEach([0.42, 0.5, 0.58], id: \.self) { fx in
                Path { p in
                    p.move(to: .init(x: w * fx, y: h * 0.3))
                    p.addQuadCurve(to: .init(x: w * fx, y: h * 0.1), control: .init(x: w * (fx + 0.05), y: h * 0.2))
                }.stroke(.white.opacity(0.8), style: .init(lineWidth: 2.4, lineCap: .round))
            }
            // cup
            Path { p in
                p.move(to: .init(x: w * 0.36, y: h * 0.42))
                p.addLine(to: .init(x: w * 0.4, y: h * 0.82))
                p.addQuadCurve(to: .init(x: w * 0.6, y: h * 0.82), control: .init(x: w * 0.5, y: h * 0.9))
                p.addLine(to: .init(x: w * 0.64, y: h * 0.42))
            }.fill(accent)
            // rim
            Capsule().fill(.white.opacity(0.9)).frame(width: w * 0.3, height: 5).position(x: w * 0.5, y: h * 0.42)
            // handle
            Circle().strokeBorder(accent, lineWidth: 4).frame(width: h * 0.3, height: h * 0.3).position(x: w * 0.7, y: h * 0.58)
            // saucer
            Ellipse().fill(deep.opacity(0.5)).frame(width: w * 0.42, height: 7).position(x: w * 0.5, y: h * 0.9)
        }
    }

    private func service(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            // gear
            Image(systemName: "gearshape.fill").font(.system(size: h * 0.5)).foregroundStyle(accent)
                .position(x: w * 0.4, y: h * 0.5)
            Circle().fill(.white.opacity(0.9)).frame(width: h * 0.18, height: h * 0.18).position(x: w * 0.4, y: h * 0.5)
            // wrench
            Image(systemName: "wrench.adjustable.fill").font(.system(size: h * 0.34, weight: .semibold))
                .foregroundStyle(deep).rotationEffect(.degrees(20)).position(x: w * 0.66, y: h * 0.56)
        }
    }

    private func parking(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            RoundedRectangle(cornerRadius: h * 0.16, style: .continuous).fill(accent)
                .frame(width: h * 0.62, height: h * 0.62)
                .overlay { Text("P").font(.system(size: h * 0.4, weight: .black, design: .rounded)).foregroundStyle(.white) }
                .position(x: w * 0.4, y: h * 0.5)
            // car top-view chip
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.9))
                .frame(width: w * 0.16, height: h * 0.3).position(x: w * 0.72, y: h * 0.5)
            RoundedRectangle(cornerRadius: 2).fill(deep.opacity(0.4))
                .frame(width: w * 0.1, height: h * 0.1).position(x: w * 0.72, y: h * 0.5)
        }
    }

    private func shield(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            Image(systemName: "shield.fill").font(.system(size: h * 0.62)).foregroundStyle(accent)
                .position(x: w * 0.5, y: h * 0.5)
            Image(systemName: "checkmark").font(.system(size: h * 0.26, weight: .black)).foregroundStyle(.white)
                .position(x: w * 0.5, y: h * 0.46)
        }
    }

    private func merch(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            // t-shirt
            Path { p in
                p.move(to: .init(x: w * 0.38, y: h * 0.32))
                p.addLine(to: .init(x: w * 0.3, y: h * 0.42))
                p.addLine(to: .init(x: w * 0.36, y: h * 0.5))
                p.addLine(to: .init(x: w * 0.38, y: h * 0.82))
                p.addLine(to: .init(x: w * 0.62, y: h * 0.82))
                p.addLine(to: .init(x: w * 0.64, y: h * 0.5))
                p.addLine(to: .init(x: w * 0.7, y: h * 0.42))
                p.addLine(to: .init(x: w * 0.62, y: h * 0.32))
                p.addQuadCurve(to: .init(x: w * 0.38, y: h * 0.32), control: .init(x: w * 0.5, y: h * 0.46))
            }.fill(accent)
            Image(systemName: "figure.run").font(.system(size: h * 0.24, weight: .black)).foregroundStyle(.white)
                .position(x: w * 0.5, y: h * 0.6)
        }
    }

    private func ticket(_ s: CGSize) -> some View {
        let w = s.width, h = s.height
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent)
                .frame(width: w * 0.62, height: h * 0.5).position(x: w * 0.5, y: h * 0.5)
            Image(systemName: "ticket.fill").font(.system(size: h * 0.3)).foregroundStyle(.white)
                .position(x: w * 0.5, y: h * 0.5)
        }
    }

    private func gift(_ s: CGSize) -> some View {
        Image(systemName: "gift.fill").font(.system(size: s.height * 0.42)).foregroundStyle(accent)
            .position(x: s.width / 2, y: s.height / 2)
    }
}

private extension Color {
    /// Blend toward another colour (used for shadow/wheel tones).
    func mix(with other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let m = CGFloat(amount)
        return Color(
            red: Double(ar + (br - ar) * m),
            green: Double(ag + (bg - ag) * m),
            blue: Double(ab + (bb - ab) * m)
        )
    }
}
