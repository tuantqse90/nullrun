import SwiftUI

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
                    voucherGrid.padding(.top, 14)
                    productHeader.padding(.top, 16)
                    productGrid.padding(.top, 10)
                    Text("Giá điểm cố định — không giảm giá giờ vàng")
                        .font(.viet(12.5)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
                    app.showToast("Đã thêm vào ví — đưa mã cho thu ngân Guardian")
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
                    do { try await app.linkGuardian(memberId: memberId) } catch { self.error = error.localizedDescription }
                }
            }
            Button("Để sau", role: .cancel) {}
        } message: {
            Text("Cần liên kết thẻ Hội Cam để đổi quà Guardian.")
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

    private var vouchers: [Reward] { app.catalog.filter(\.isVoucher) }
    private var products: [Reward] { app.catalog.filter { !$0.isVoucher } }

    private var voucherGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(vouchers) { reward in
                RewardCard(reward: reward, affordable: app.balance >= reward.costPoints) {
                    redeeming = reward
                }
            }
        }
    }

    private var productHeader: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "gift").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.purpleDeep)
                Text("Sản phẩm Guardian").font(.viet(15, .bold))
            }
            Spacer()
            Text("Nhận tại quầy").font(.viet(12)).foregroundStyle(Theme.muted)
        }
    }

    private var productGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            ForEach(products) { reward in
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
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.purpleBg)
                Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(Theme.purpleMid)
            }
            .frame(height: 70)
        }
    }
}

/// Perforated voucher-ticket artwork with the Guardian mark.
struct TicketArt: View {
    let reward: Reward

    private var denomination: String {
        if let range = reward.title.range(of: #"(\d+)[.,]000"#, options: .regularExpression) {
            let digits = reward.title[range].prefix(while: { $0.isNumber })
            return "\(digits)K"
        }
        return "★"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(denomination == "50K" ? Theme.orangeBg : Theme.greenBgSoft)
            GeometryReader { geo in
                let x = geo.size.width * 0.58
                Circle().fill(Theme.card).frame(width: 16, height: 16).position(x: x, y: 0)
                Circle().fill(Theme.card).frame(width: 16, height: 16).position(x: x, y: geo.size.height)
                Path { p in
                    p.move(to: .init(x: x, y: 10))
                    p.addLine(to: .init(x: x, y: geo.size.height - 10))
                }
                .stroke(Theme.orangeDeep.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                Text(denomination)
                    .font(.viet(21, .heavy))
                    .foregroundStyle(denomination == "50K" ? Theme.orangeDeep : Theme.greenDeep)
                    .position(x: geo.size.width * 0.28, y: geo.size.height / 2)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.guardian)
                    .frame(width: 26, height: 26)
                    .overlay { Text("G").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white) }
                    .position(x: geo.size.width * 0.82, y: geo.size.height / 2)
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
        reward.isVoucher
            ? "Không thể hoàn tác sau khi đổi. Voucher có giá trị 90 ngày, dùng một lần tại quầy Guardian."
            : "Nhận sản phẩm tại quầy Guardian — đưa mã trong ví cho thu ngân. Không hoàn tác sau khi đổi."
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
                idempotencyKey: "ios-\(UUID().uuidString.prefix(24))"
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
