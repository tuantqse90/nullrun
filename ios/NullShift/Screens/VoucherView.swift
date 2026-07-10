import SwiftUI

/// Full-screen voucher: barcode + code for the cashier, expiry countdown.
struct VoucherView: View {
    @EnvironmentObject private var app: AppModel
    let redemption: Redemption


    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Đóng") { app.screen = .rewards }
                    .font(.viet(15, .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.orange)
                    Text(expiryLabel)
                        .font(.viet(13.5, .bold)).foregroundStyle(Theme.orangeDeep)
                }
            }
            .padding(.top, 6)

            Spacer()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.guardian)
                        .frame(width: 22, height: 22)
                        .overlay { Text("G").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white) }
                    Text("Guardian").font(.viet(14, .bold)).foregroundStyle(Theme.orangeDeep)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.orangeBg)
                .clipShape(Capsule())

                Text(redemption.title).font(.viet(26, .heavy)).padding(.top, 12)
                    .multilineTextAlignment(.center)
                Text("Đưa màn hình này cho thu ngân").font(.viet(14)).foregroundStyle(Theme.muted)
            }

            VStack(spacing: 14) {
                BarcodeArt(seed: redemption.voucherCode ?? redemption.id.uuidString)
                    .frame(height: 96)
                Text(redemption.voucherCode ?? "—")
                    .font(.mono(28, .bold))
                    .kerning(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(EdgeInsets(top: 24, leading: 18, bottom: 24, trailing: 18))
            .frame(maxWidth: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.ink, lineWidth: 2.5)
            }
            .padding(.top, 18)

            HStack(spacing: 8) {
                Image(systemName: "sun.max").font(.system(size: 14)).foregroundStyle(Theme.muted)
                Text("Độ sáng đã tăng tối đa").font(.viet(13.5, .semibold)).foregroundStyle(Color(hex: 0x5B5346))
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Color(hex: 0xF0EDE6))
            .clipShape(Capsule())
            .padding(.top, 14)

            Text("Mã không quét được? Thu ngân nhập tay dòng chữ trên.")
                .font(.viet(13)).foregroundStyle(Theme.faint)
                .padding(.top, 12)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(.white)
    }

    private var expiryLabel: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: redemption.expiresAt).day ?? 0)
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return "HSD \(f.string(from: redemption.expiresAt)) · còn \(days) ngày"
    }
}

/// Deterministic pseudo-barcode from the voucher code.
struct BarcodeArt: View {
    let seed: String

    var body: some View {
        GeometryReader { geo in
            let widths = bars()
            let total = widths.reduce(0, +) + CGFloat(widths.count - 1) * 3
            let scale = geo.size.width / total
            HStack(alignment: .top, spacing: 3 * scale) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                    Rectangle()
                        .fill(Color(hex: 0x101010))
                        .frame(width: w * scale)
                }
            }
            .frame(height: geo.size.height)
        }
    }

    private func bars() -> [CGFloat] {
        var h: UInt64 = 5381
        for b in seed.utf8 { h = h &* 33 &+ UInt64(b) }
        var rng = h
        return (0..<30).map { _ in
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(3 + (rng >> 33) % 8)
        }
    }
}
