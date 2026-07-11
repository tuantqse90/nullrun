import SwiftUI

/// Per-partner branding for the rewards catalog. Guardian (health/beauty) is
/// the anchor; the Tasco/VETC mobility ecosystem plugs into the same engine.
struct RewardBrand: Hashable {
    let code: String      // partner code
    let mark: String      // short badge text on the voucher ticket
    let name: String      // display name
    let tagline: String   // section subtitle
    let color: Color      // brand accent

    static func of(_ partner: String) -> RewardBrand {
        switch partner {
        case "vetc":
            return .init(code: "vetc", mark: "VETC", name: "VETC",
                         tagline: "Thu phí không dừng", color: Color(hex: 0x0E9E93))
        case "vetcgo":
            return .init(code: "vetcgo", mark: "VGO", name: "VETC GO",
                         tagline: "Di chuyển & thuê xe", color: Color(hex: 0x1E8A5B))
        case "tasco":
            return .init(code: "tasco", mark: "TASCO", name: "Tasco",
                         tagline: "Hệ sinh thái Tasco", color: Color(hex: 0xD2493D))
        default:
            return .init(code: "guardian", mark: "G", name: "Guardian",
                         tagline: "Sức khoẻ & Làm đẹp", color: Color(hex: 0xF26522))
        }
    }

    /// Catalog section order — mobility ecosystem first (the track story),
    /// Guardian anchor last.
    static let order = ["vetc", "vetcgo", "tasco", "guardian"]
}

extension Reward {
    var brand: RewardBrand { RewardBrand.of(partner) }
}

/// Rewards catalog: dark balance card, ticket-style vouchers, product cards,
/// redeem bottom sheet, toast — per the prototype.
struct RewardsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var redeeming: Reward?
    @State private var linkPrompt = false
    @State private var memberId = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Đổi thưởng").font(.viet(23, .bold)).padding(.bottom, 12)
                    balanceCard
                    ForEach(partnerSections, id: \.brand.code) { section in
                        sectionHeader(section.brand).padding(.top, 18)
                        grid(section.rewards).padding(.top, 10)
                    }
                    Text("Điểm đổi từ vận động thật — giá cố định, không giảm giá giờ vàng")
                        .font(.viet(12.5)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            AppTabBar(active: .rewards) { tab in
                switch tab {
                case .today: app.screen = .home
                case .league: app.screen = .league
                case .guild: app.screen = .guild
                case .body: app.screen = .scanIntro
                default: break
                }
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) { toastView.padding(.bottom, 104) }
        .sheet(item: $redeeming) { reward in
            RedeemSheet(reward: reward) { redemption in
                redeeming = nil
                if reward.isVoucher, let redemption {
                    app.screen = .voucher(redemption)
                } else if redemption != nil {
                    app.showToast("Đã thêm vào ví — đưa mã khi nhận tại \(reward.brand.name)")
                }
                Task { await app.refresh() }
            } needsLink: {
                redeeming = nil
                linkPrompt = true
            }
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
            // Sheets are separate presentations — the app's forced-light
            // scheme does NOT flow in; set it again or dark mode turns
            // unstyled text white on the light sheet.
            .preferredColorScheme(.light)
            .foregroundStyle(Theme.ink)
        }
        .alert("Liên kết Hội Cam Guardian", isPresented: $linkPrompt) {
            TextField("Số thẻ thành viên (6–16 số)", text: $memberId)
                .keyboardType(.numberPad)
            Button("Liên kết") {
                Task {
                    do { try await app.linkGuardian(memberId: memberId) }
                    catch { self.error = error.localizedDescription }
                }
            }
            Button("Để sau", role: .cancel) {}
        } message: {
            Text("Cần liên kết thẻ Hội Cam để đổi quà Guardian.")
        }
        // Surface link failures — previously written to `error` but never shown.
        .alert("Không liên kết được", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await app.refresh() }
    }

    private var balanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Điểm của bạn").font(.viet(13)).foregroundStyle(Theme.faint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.int(app.balance)).font(.mono(32)).foregroundStyle(Theme.darkInk)
                    Text("điểm").font(.viet(14)).foregroundStyle(Theme.faint)
                }
            }
            Spacer()
            if let voucher = app.wallet.first {
                Button {
                    app.screen = .voucher(voucher)
                } label: {
                    Text("Ví voucher (\(app.wallet.count))")
                        .font(.viet(13.5, .bold)).foregroundStyle(Color(hex: 0x0E2A1D))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.greenBright)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressScale())
            } else {
                Text("Ví trống")
                    .font(.viet(13.5, .semibold)).foregroundStyle(Theme.faint)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.darkLine)
                    .clipShape(Capsule())
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .background {
            ZStack(alignment: .bottomTrailing) {
                Theme.ink
                Mascot(mood: .happy, bobbing: false)
                    .frame(width: 46, height: 40)
                    .padding(.trailing, 14).padding(.bottom, 4)
                    .opacity(0.9)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Catalog grouped by partner (mobility ecosystem first, Guardian last),
    /// each preserving the server's cost-ascending order.
    private var partnerSections: [(brand: RewardBrand, rewards: [Reward])] {
        RewardBrand.order.compactMap { code in
            let items = app.catalog.filter { $0.partner == code }
            return items.isEmpty ? nil : (RewardBrand.of(code), items)
        }
    }

    private func sectionHeader(_ brand: RewardBrand) -> some View {
        HStack(spacing: 9) {
            Text(brand.mark)
                .font(.viet(11, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(brand.color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(brand.name).font(.viet(15, .bold))
                Text(brand.tagline).font(.viet(11.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    private func grid(_ rewards: [Reward]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(rewards) { reward in
                RewardCard(reward: reward, affordable: app.balance >= reward.costPoints) {
                    redeeming = reward
                }
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = app.toast {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.greenBright)
                Text(toast).font(.viet(13)).foregroundStyle(Theme.darkInk)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct RewardCard: View {
    let reward: Reward
    let affordable: Bool
    let onRedeem: () -> Void

    private var available: Bool { affordable && reward.stock != 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            Text(reward.title).font(.viet(14, .bold)).lineLimit(1).padding(.top, 10)
            Text(reward.description ?? " ").font(.viet(12)).foregroundStyle(Theme.muted).lineLimit(1)
            HStack {
                Text(Fmt.int(reward.costPoints)).font(.mono(15)).foregroundStyle(Theme.greenDeep)
                Spacer()
                Button(action: onRedeem) {
                    Text(reward.stock == 0 ? "Hết" : "Đổi")
                        .font(.viet(12.5, .bold))
                        .foregroundStyle(available ? .white : Theme.muted)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(available ? Theme.green : Theme.track)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressScale())
                .disabled(!available)
                .accessibilityIdentifier("redeem_\(reward.title)")
            }
            .padding(.top, 10)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 5, y: 2)
    }

    @ViewBuilder
    private var artwork: some View {
        if reward.isVoucher {
            TicketArt(reward: reward)
        } else {
            let brand = reward.brand
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(brand.color.opacity(0.14))
                Image(systemName: Self.icon(for: reward))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(brand.color)
            }
            .frame(height: 70)
        }
    }

    /// Pick a fitting SF Symbol from the reward title/description. Order
    /// matters — check the specific "what it is" cues before incidental
    /// keywords (e.g. "ăn Tết" in a VETC top-up must not read as food).
    private static func icon(for reward: Reward) -> String {
        let t = reward.title.lowercased()
        let d = (t + " " + (reward.description ?? "")).lowercased()
        // Wallet / account top-ups (decided by TITLE, not the blurb).
        if t.contains("nạp ví") || t.contains("t-money") { return "creditcard.fill" }
        if t.contains("vé tháng") || t.contains("vé năm") || t.contains("qua trạm")
            || t.contains("làn ưu tiên") { return "road.lanes" }
        if t.contains("thuê xe") || t.contains("tự lái") || t.contains("tài xế")
            || t.contains("đưa đón") || t.contains("đặt xe") { return "car.fill" }
        if d.contains("sạc") { return "bolt.car.fill" }
        if t.contains("xăng") { return "fuelpump.fill" }
        if t.contains("rửa xe") { return "sparkles" }
        if t.contains("dầu") || t.contains("bảo dưỡng") || t.contains("lốp")
            || t.contains("khám xe") { return "wrench.and.screwdriver.fill" }
        if t.contains("đỗ xe") || t.contains("bãi đỗ") || t.contains("parking") { return "parkingsign" }
        if t.contains("cà phê") || t.contains("đồ ăn") || t.contains("suất ăn")
            || t.contains("combo") || t.contains("nghỉ chân") { return "cup.and.saucer.fill" }
        if t.contains("bảo hiểm") { return "checkmark.shield.fill" }
        if t.contains("cây") || t.contains("trồng") { return "leaf.fill" }
        if t.contains("sticker") || t.contains("bình") || t.contains("áo") { return "bag.fill" }
        return "gift.fill"
    }
}

/// Perforated voucher-ticket artwork, coloured + marked by the partner brand.
struct TicketArt: View {
    let reward: Reward

    private var brand: RewardBrand { reward.brand }

    /// Denomination pulled from the title ("…50.000đ" → "50K"), else the mark.
    private var denomination: String {
        if let range = reward.title.range(of: #"(\d+)[.,]000"#, options: .regularExpression) {
            let digits = reward.title[range].prefix(while: { $0.isNumber })
            return "\(digits)K"
        }
        return "★"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(brand.color.opacity(0.15))
            GeometryReader { geo in
                let x = geo.size.width * 0.56
                Circle().fill(Theme.card).frame(width: 16, height: 16).position(x: x, y: 0)
                Circle().fill(Theme.card).frame(width: 16, height: 16).position(x: x, y: geo.size.height)
                Path { p in
                    p.move(to: .init(x: x, y: 10))
                    p.addLine(to: .init(x: x, y: geo.size.height - 10))
                }
                .stroke(brand.color.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                Text(denomination)
                    .font(.viet(21, .heavy))
                    .foregroundStyle(brand.color)
                    .position(x: geo.size.width * 0.27, y: geo.size.height / 2)
                Text(brand.mark)
                    .font(.viet(10, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(brand.color)
                    .clipShape(Capsule())
                    .position(x: geo.size.width * 0.79, y: geo.size.height / 2)
            }
        }
        .frame(height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Confirm-redeem bottom sheet: balance / cost / remainder + warning note.
struct RedeemSheet: View {
    @EnvironmentObject private var app: AppModel
    let reward: Reward
    let done: (Redemption?) -> Void
    let needsLink: () -> Void

    @State private var busy = false
    @State private var error: String?
    // Stable per-presentation key: retrying after an ambiguous network
    // failure must reuse the SAME idempotency key so the backend returns the
    // existing redemption instead of double-spending the user's points.
    @State private var idempotencyKey = "ios-\(UUID().uuidString.prefix(24))"

    var body: some View {
        VStack(spacing: 0) {
            Text("Đổi \(reward.title)?")
                .font(.viet(20, .heavy))
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            VStack(spacing: 0) {
                row("Điểm hiện có", Fmt.int(app.balance), color: Theme.ink)
                Divider().overlay(Theme.divider)
                row("Đổi quà", "−\(Fmt.int(reward.costPoints))", color: Theme.danger)
                Divider().overlay(Theme.divider)
                row("Còn lại", Fmt.int(app.balance - reward.costPoints), color: Theme.ink, bold: true)
            }
            .padding(.horizontal, 18)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
            .padding(.top, 16)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 15)).foregroundStyle(Theme.orangeDeep).padding(.top, 1)
                Text(note).font(.viet(13)).foregroundStyle(Theme.orangeInk)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.orangeBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 12)

            if let error {
                Text(error).font(.viet(13)).foregroundStyle(Theme.danger).padding(.top, 8)
            }

            PrimaryButton(title: busy ? "Đang đổi…" : "Xác nhận đổi \(Fmt.int(reward.costPoints)) điểm") {
                Task { await confirm() }
            }
            .disabled(busy)
            .padding(.top, 16)

            Button("Để sau") { done(nil) }
                .font(.viet(15, .semibold)).foregroundStyle(Theme.muted)
                .padding(.top, 14)

            Spacer()
        }
        .padding(.horizontal, 22)
        .background(Theme.sheetBg)
    }

    private var note: String {
        let at = reward.brand.name
        return reward.isVoucher
            ? "Không thể hoàn tác. Voucher giá trị 90 ngày, dùng một lần qua \(at)."
            : "Nhận tại \(at) — đưa mã trong ví. Không hoàn tác sau khi đổi."
    }

    private func row(_ label: String, _ value: String, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.viet(14.5, bold ? .bold : .regular)).foregroundStyle(bold ? Theme.ink : Theme.muted)
            Spacer()
            Text(value).font(.mono(15, bold ? .bold : .semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 13)
    }

    private func confirm() async {
        busy = true
        error = nil
        do {
            let redemption = try await APIClient.shared.redeem(
                reward: reward.id,
                idempotencyKey: idempotencyKey
            )
            done(redemption)
        } catch let e as APIClient.APIError where e.localizedDescription.contains("Guardian") {
            needsLink()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
