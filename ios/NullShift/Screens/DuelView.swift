import SwiftUI

/// PvP duel: create/join by code, then a live 2-lane race to the target.
/// The server decides the winner from GPS crossing timestamps.
struct DuelView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var tracker: RunTracker

    @State private var joinCode = ""
    @State private var busy = false
    @State private var error: String?
    @State private var polling = false

    private var duel: DuelState? { app.duel?.exists == true ? app.duel : nil }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 6)
            ScrollView {
                VStack(spacing: 14) {
                    if let error {
                        Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
                    }
                    if let duel {
                        switch duel.status {
                        case "open": waitingCard(duel)
                        case "active": raceCard(duel)
                        case "finished": resultCard(duel)
                        default: lobby
                        }
                    } else {
                        lobby
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
        }
        .background(Theme.bg)
        .task {
            await app.refresh()
            await pollLoop()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Thách đấu 1v1").font(.viet(23, .bold))
                Text("Ai chạm mốc trước — người đó thắng")
                    .font(.viet(13.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                app.screen = .league
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 40, height: 40)
                    .background(.white)
                    .clipShape(Circle())
                    .shadow(color: Theme.cardShadow, radius: 4, y: 2)
            }
        }
    }

    // MARK: lobby — create or join

    private var lobby: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                HStack(spacing: -10) {
                    Mascot(mood: .running).frame(width: 56, height: 46)
                    Mascot(mood: .running).frame(width: 56, height: 46)
                        .scaleEffect(x: -1)
                }
                Text("Đua 500 m với một người bạn").font(.viet(17, .bold))
                Text("Tạo trận, gửi mã cho bạn, cả hai bấm chạy — GPS thật phân thắng bại.")
                    .font(.viet(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: busy ? "Đang tạo…" : "Tạo trận 500 m", height: 56, glow: true) {
                    Task { await create() }
                }
                .disabled(busy)
            }
            .card(radius: 22, padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))

            VStack(alignment: .leading, spacing: 8) {
                Text("Có mã từ bạn bè?").font(.viet(14, .bold))
                HStack(spacing: 10) {
                    TextField("Nhập mã 6 ký tự", text: $joinCode)
                        .font(.mono(19))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                        .background(Theme.dimBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Button {
                        Task { await join() }
                    } label: {
                        Text("Vào trận").font(.viet(14, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 13)
                            .background(joinCode.count == 6 ? Theme.purpleDeep : Theme.track)
                            .clipShape(Capsule())
                    }
                    .disabled(joinCode.count != 6 || busy)
                }
            }
            .card()
        }
    }

    // MARK: waiting for opponent

    private func waitingCard(_ duel: DuelState) -> some View {
        VStack(spacing: 12) {
            Text("Gửi mã này cho đối thủ").font(.viet(14)).foregroundStyle(Theme.muted)
            Text(duel.code ?? "—")
                .font(.mono(44, .bold)).kerning(8)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Theme.purpleBg)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang chờ người chơi thứ hai…").font(.viet(13)).foregroundStyle(Theme.faint)
            }
            Button("Huỷ trận") {
                Task {
                    if let id = duel.id { try? await APIClient.shared.cancelDuel(id: id) }
                    await app.refresh()
                }
            }
            .font(.viet(14, .semibold)).foregroundStyle(Theme.danger)
        }
        .frame(maxWidth: .infinity)
        .card(radius: 22, padding: EdgeInsets(top: 22, leading: 20, bottom: 18, trailing: 20))
    }

    // MARK: live race

    private func raceCard(_ duel: DuelState) -> some View {
        VStack(spacing: 16) {
            Text("Đích: \(Int(duel.targetM ?? 500)) m · thưởng +\(duel.rewardPoints ?? 25)")
                .font(.viet(13.5, .semibold)).foregroundStyle(Theme.muted)
            ForEach(duel.players ?? []) { player in
                lane(player, target: duel.targetM ?? 500)
            }
            if myPlayer(duel)?.hasSession != true {
                PrimaryButton(title: "Bắt đầu chạy!", height: 56, glow: true) {
                    app.pendingDuelId = duel.id
                    app.screen = .prerun
                }
            } else {
                Text("Trận đang diễn ra — cập nhật mỗi vài giây")
                    .font(.viet(12.5)).foregroundStyle(Theme.faint)
            }
        }
        .card(radius: 22, padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
    }

    private func myPlayer(_ duel: DuelState) -> DuelPlayer? {
        duel.players?.first(where: \.isMe)
    }

    private func lane(_ player: DuelPlayer, target: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(player.isMe ? "\(player.displayName) (bạn)" : player.displayName)
                    .font(.viet(13.5, player.isMe ? .bold : .semibold))
                Spacer()
                Text("\(Int(player.distanceM)) m").font(.mono(13.5))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(player.isMe ? Theme.green : Theme.purpleMid)
                        .frame(width: geo.size.width * min(1, player.distanceM / target))
                    Mascot(mood: .running, bobbing: false)
                        .frame(width: 26, height: 21)
                        .offset(x: max(0, geo.size.width * min(1, player.distanceM / target) - 22), y: -4)
                }
            }
            .frame(height: 14)
        }
    }

    // MARK: result

    private func resultCard(_ duel: DuelState) -> some View {
        let winner = duel.players?.first { $0.userId == duel.winnerId }
        let iWon = winner?.isMe == true
        return VStack(spacing: 12) {
            Mascot(mood: iWon ? .cheering : .sleeping).frame(width: 72, height: 60)
            Text(iWon ? "Bạn thắng! 🏆" : "\(winner?.displayName ?? "Đối thủ") thắng")
                .font(.viet(21, .heavy))
            if iWon {
                Text("+\(duel.rewardPoints ?? 25) điểm đã vào ví")
                    .font(.viet(14, .semibold)).foregroundStyle(Theme.greenDeep)
            } else {
                Text("Trận sau phục thù nhé — tạo trận mới liền tay!")
                    .font(.viet(13.5)).foregroundStyle(Theme.muted)
            }
            ForEach(duel.players ?? []) { player in
                lane(player, target: duel.targetM ?? 500)
            }
            PrimaryButton(title: "Trận mới", height: 52) {
                Task { await create() }
            }
        }
        .frame(maxWidth: .infinity)
        .card(radius: 22, padding: EdgeInsets(top: 20, leading: 18, bottom: 18, trailing: 18))
        .overlay(alignment: .top) {
            if iWon { ConfettiBurst().frame(height: 120).clipped() }
        }
    }

    // MARK: actions

    private func create() async {
        busy = true
        error = nil
        do {
            app.duel = try await APIClient.shared.createDuel()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func join() async {
        busy = true
        error = nil
        do {
            app.duel = try await APIClient.shared.joinDuel(code: joinCode)
            joinCode = ""
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    /// Polls the duel while it's open/active so the lanes move live.
    private func pollLoop() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        while !Task.isCancelled, app.screen == .duel {
            if let id = app.duel?.id, app.duel?.exists == true,
               app.duel?.status == "open" || app.duel?.status == "active" {
                if let updated = try? await APIClient.shared.duel(id: id) {
                    let wasActive = app.duel?.status == "active"
                    app.duel = updated
                    if wasActive && updated.status == "finished" {
                        Haptics.heavy()
                    }
                }
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
