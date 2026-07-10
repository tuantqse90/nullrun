import SwiftUI
import UIKit

/// Hội (guild) tab — live v1. Principles from the design (s20–s22): only
/// active guilds surface in discovery, contribution shows as % of each
/// member's own weekly goal (never absolute km), chat lives on Zalo.
/// Guild quests pay GUILD XP (shared glory) — never personal points.
struct GuildView: View {
    @EnvironmentObject private var app: AppModel

    @State private var joinCode = ""
    @State private var busy = false
    @State private var error: String?
    @State private var discovered: [GuildDiscoverRow] = []
    @State private var showCreate = false
    @State private var showSettings = false
    @State private var confirmLeave = false
    @State private var celebratedKeys: Set<String>?

    private var guild: GuildState? { app.guild?.exists == true ? app.guild : nil }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 6)

            ScrollView {
                VStack(spacing: 13) {
                    if let error {
                        Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let guild {
                        memberHome(guild)
                    } else {
                        lobby
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            }
            .refreshable { await reload() }

            AppTabBar(active: .guild) { tab in
                switch tab {
                case .today: app.screen = .home
                case .league: app.screen = .league
                case .rewards: app.screen = .rewards
                case .body: app.screen = .scanIntro
                default: break
                }
            }
        }
        .background(Theme.bg)
        .task { await reload() }
        .sheet(isPresented: $showCreate) {
            GuildCreateSheet { name, emblem, zalo in
                await createGuild(name: name, emblem: emblem, zalo: zalo)
            }
        }
        .sheet(isPresented: $showSettings) {
            GuildSettingsSheet(
                emblem: guild?.emblem ?? "🦔",
                zaloLink: guild?.zaloLink ?? ""
            ) { emblem, zalo in
                await saveSettings(emblem: emblem, zalo: zalo)
            }
        }
        .confirmationDialog("Rời hội?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Rời hội", role: .destructive) { Task { await leave() } }
            Button("Ở lại", role: .cancel) {}
        } message: {
            Text("Tiến độ nhiệm vụ chung vẫn thuộc về hội. Bạn có thể quay lại bất cứ lúc nào.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Hội nhóm").font(.viet(23, .bold))
                Text(guild == nil ? "Chạy có hội, vui gấp đôi" : "Vinh quang gom từ chân thật")
                    .font(.viet(13.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let guild {
                Text("Hội cấp \(guild.level ?? 1)")
                    .font(.viet(12.5, .bold)).foregroundStyle(Theme.purpleDeep)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.purpleBg)
                    .clipShape(Capsule())
                    .popIn()
            }
        }
    }

    // MARK: - no guild yet: hero + join + discovery

    private var lobby: some View {
        VStack(spacing: 13) {
            heroCard.riseIn(0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Có mã mời từ bạn bè?").font(.viet(14, .bold))
                HStack(spacing: 10) {
                    TextField("Nhập mã 6 ký tự", text: $joinCode)
                        .font(.mono(19))
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                        .background(Theme.dimBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Button {
                        Task { await joinByCode() }
                    } label: {
                        Text("Vào hội").font(.viet(14, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 13)
                            .background(joinCode.count == 6 ? Theme.purpleDeep : Theme.track)
                            .clipShape(Capsule())
                    }
                    .disabled(joinCode.count != 6 || busy)
                }
            }
            .card()
            .riseIn(1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hội đang hoạt động").font(.viet(15, .bold))
                    Spacer()
                    Text("chỉ hiện hội còn chạy thật")
                        .font(.viet(11.5)).foregroundStyle(Theme.faint)
                }
                if discovered.isEmpty {
                    HStack(spacing: 12) {
                        Mascot(mood: .happy).frame(width: 44, height: 37)
                        Text("Chưa có hội nào quanh đây — làm người mở đường nhé!")
                            .font(.viet(13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(Array(discovered.enumerated()), id: \.element.id) { i, row in
                        discoverRow(row).riseIn(i + 2)
                        if row.id != discovered.last?.id {
                            Divider().overlay(Theme.divider)
                        }
                    }
                }
            }
            .card(radius: 20, padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            .riseIn(2)

            principlesFooter.riseIn(3)
        }
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: -14) {
                ForEach(0..<3, id: \.self) { i in
                    ZStack {
                        Circle().fill(Theme.purpleBg)
                        Mascot(mood: .happy, bobbing: i == 1)
                            .frame(width: 38, height: 32)
                            .offset(y: 5)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                }
            }
            Text("Chạy có hội, vui gấp đôi").font(.viet(19, .bold)).foregroundStyle(.white)
            Text("Lập hội với đồng nghiệp, bạn chạy, gia đình — gom XP chung bằng vận động thật, nhiệm vụ mới mỗi ngày.")
                .font(.viet(13.5)).foregroundStyle(Color(hex: 0xD9CCF2))
                .multilineTextAlignment(.center)
            Button {
                showCreate = true
            } label: {
                Text("Tạo hội cùng bạn bè")
                    .font(.viet(16, .bold)).foregroundStyle(Theme.purpleDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 20, trailing: 20))
        .background(LinearGradient(colors: [Theme.purpleDeep, Theme.purpleMid], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shineSweep(opacity: 0.18)
    }

    private func discoverRow(_ row: GuildDiscoverRow) -> some View {
        HStack(spacing: 12) {
            Text(row.emblem)
                .font(.system(size: 24))
                .frame(width: 46, height: 46)
                .background(Theme.purpleBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.viet(15, .bold))
                Text("\(row.memberCount) thành viên · \(row.activeWeek) chạy tuần này")
                    .font(.viet(12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button {
                Task { await joinById(row.id) }
            } label: {
                Text("Vào").font(.viet(13.5, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.purpleDeep)
                    .clipShape(Capsule())
            }
            .disabled(busy)
        }
    }

    private var principlesFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            principleLine(icon: "figure.run.circle", text: "Khám phá chỉ gợi ý hội đang chạy thật — không bao giờ đưa bạn vào hội đã nguội.")
            principleLine(icon: "percent", text: "Đóng góp tính theo % mục tiêu cá nhân — người mới và người chạy lâu đều có giá trị.")
            principleLine(icon: "message", text: "Trò chuyện nằm bên Zalo — app lo thi đua, chat ở nơi mọi người vốn đã ở đó.")
        }
        .card()
    }

    private func principleLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(Theme.purpleDeep)
                .frame(width: 22)
            Text(text).font(.viet(12.5)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - in a guild

    private func memberHome(_ guild: GuildState) -> some View {
        let daily = (guild.quests ?? []).filter { $0.cadence == "daily" }
        let weekly = (guild.quests ?? []).filter { $0.cadence == "weekly" }
        return VStack(spacing: 13) {
            guildHero(guild).riseIn(0)
            zaloCard(guild).riseIn(1)
            questSection(title: "Nhiệm vụ hôm nay", subtitle: "reset mỗi ngày", quests: daily)
                .riseIn(2)
            questSection(title: "Thử thách tuần", subtitle: "cả hội gom chung", quests: weekly)
                .riseIn(3)
            membersCard(guild).riseIn(4)

            Text("XP hội là vinh quang chung để lên cấp hội — không đổi được quà, không cộng vào điểm cá nhân.")
                .font(.viet(11.5)).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button("Rời hội") { confirmLeave = true }
                .font(.viet(13.5, .semibold)).foregroundStyle(Theme.danger)
                .padding(.bottom, 4)
        }
        .overlay(alignment: .top) {
            if celebrating { ConfettiBurst().frame(height: 140).clipped().allowsHitTesting(false) }
        }
    }

    @State private var celebrating = false

    private func guildHero(_ guild: GuildState) -> some View {
        let xpIn = guild.xpInLevel ?? 0
        let xpPer = max(1, guild.xpPerLevel ?? 200)
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text(guild.emblem ?? "🦔")
                    .font(.system(size: 34))
                    .frame(width: 62, height: 62)
                    .background(.white)
                    .clipShape(Circle())
                    .popIn()
                VStack(alignment: .leading, spacing: 3) {
                    Text(guild.name ?? "").font(.viet(19, .heavy)).foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Circle().fill(Theme.greenBright).frame(width: 7, height: 7)
                            .modifier(PulseDot())
                        Text("\(guild.activeToday ?? 0)/\(guild.memberCount ?? 0) vận động hôm nay")
                            .font(.viet(12.5, .semibold)).foregroundStyle(Color(hex: 0xD9CCF2))
                    }
                }
                Spacer()
                if guild.isLeader == true {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                }
            }

            VStack(spacing: 5) {
                HStack {
                    Text("Hội cấp \(guild.level ?? 1)")
                        .font(.viet(12.5, .bold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(Fmt.int(xpIn))/\(Fmt.int(xpPer)) XP")
                        .font(.mono(12)).foregroundStyle(Color(hex: 0xD9CCF2))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: 0xF5C97B), Color(hex: 0xFFE3AC)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (Double(xpIn) / Double(xpPer)))
                            .animation(.easeInOut(duration: 0.5), value: xpIn)
                    }
                }
                .frame(height: 9)
            }

            Button {
                UIPasteboard.general.string = guild.code
                Haptics.light()
                app.showToast("Đã chép mã mời \(guild.code ?? "")")
            } label: {
                HStack(spacing: 8) {
                    Text("Mã mời:").font(.viet(12.5)).foregroundStyle(Color(hex: 0xD9CCF2))
                    Text(guild.code ?? "—").font(.mono(15, .bold)).kerning(3).foregroundStyle(.white)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0xD9CCF2))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white.opacity(0.14))
                .clipShape(Capsule())
            }
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .background(LinearGradient(colors: [Theme.purpleDeep, Theme.purpleMid], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shineSweep(opacity: 0.15)
    }

    @ViewBuilder
    private func zaloCard(_ guild: GuildState) -> some View {
        if let link = guild.zaloLink, let url = URL(string: link) {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Chat hội trên Zalo").font(.viet(14.5, .bold)).foregroundStyle(Theme.ink)
                        Text("Thi đua ở đây — tám chuyện ở nơi cả hội vốn đã ở")
                            .font(.viet(12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.faint)
                }
                .card()
            }
        } else if guild.isLeader == true {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 18)).foregroundStyle(Theme.blue)
                        .frame(width: 40, height: 40)
                        .background(Theme.blueBg)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    Text("Gắn link nhóm Zalo để cả hội tám chuyện")
                        .font(.viet(13.5, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.faint)
                }
                .card()
            }
        }
    }

    private func questSection(title: String, subtitle: String, quests: [GuildQuestItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.viet(15, .bold))
                Spacer()
                Text(subtitle).font(.viet(11.5)).foregroundStyle(Theme.faint)
            }
            ForEach(quests) { quest in
                questRow(quest)
            }
        }
        .card(radius: 20, padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    private func questRow(_ quest: GuildQuestItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(quest.completed ? Theme.greenBgSoft : Theme.purpleBg)
                        .frame(width: 34, height: 34)
                    Image(systemName: quest.completed ? "checkmark" : questIcon(quest.key))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(quest.completed ? Theme.greenDeep : Theme.purpleDeep)
                }
                .popIn(delay: 0.05)
                VStack(alignment: .leading, spacing: 1) {
                    Text(quest.title).font(.viet(14, .bold))
                    Text(quest.description).font(.viet(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("+\(quest.xpReward) XP")
                    .font(.mono(12, .bold))
                    .foregroundStyle(quest.completed ? .white : Theme.purpleDeep)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(quest.completed ? Theme.green : Theme.purpleBg)
                    .clipShape(Capsule())
            }
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(quest.completed
                                  ? AnyShapeStyle(Theme.green)
                                  : AnyShapeStyle(LinearGradient(colors: [Theme.purpleMid, Theme.purpleDeep], startPoint: .leading, endPoint: .trailing)))
                            .frame(width: geo.size.width * min(1, quest.progress / max(1, quest.target)))
                            .animation(.easeInOut(duration: 0.5), value: quest.progress)
                    }
                }
                .frame(height: 8)
                Text(questProgressLabel(quest))
                    .font(.mono(11.5)).foregroundStyle(Theme.muted)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private func questIcon(_ key: String) -> String {
        switch key {
        case let k where k.contains("distance"): "point.topleft.down.curvedto.point.bottomright.up"
        case let k where k.contains("sessions"): "figure.run"
        default: "person.2.fill"
        }
    }

    private func questProgressLabel(_ quest: GuildQuestItem) -> String {
        // Overshoot reads as a glitch — cap the label at the target.
        let shown = min(quest.progress, quest.target)
        if quest.key.contains("distance") {
            let p = String(format: "%.1f", shown / 1000).replacingOccurrences(of: ".", with: ",")
            let t = String(format: "%.0f", quest.target / 1000)
            return "\(p)/\(t) km"
        }
        let unit = quest.key.contains("active") ? "người" : "buổi"
        return "\(Int(shown))/\(Int(quest.target)) \(unit)"
    }

    private func membersCard(_ guild: GuildState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Thành viên").font(.viet(15, .bold))
                Spacer()
                Text("\(guild.memberCount ?? 0)/\(guild.maxMembers ?? 30)")
                    .font(.mono(12.5)).foregroundStyle(Theme.faint)
            }
            ForEach(Array((guild.members ?? []).enumerated()), id: \.element.id) { i, member in
                memberRow(member, index: i)
            }
            Text("Đóng góp = % mục tiêu tuần của từng người — không ai bị so km.")
                .font(.viet(11.5)).foregroundStyle(Theme.faint)
        }
        .card(radius: 20, padding: EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
    }

    private let avatarColors: [Color] = [Theme.purpleMid, Theme.green, Theme.orange, Theme.blue, Theme.orangeDeep, Theme.greenDeep]

    private func memberRow(_ member: GuildMember, index: Int) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Text(String(member.displayName.prefix(1)).uppercased())
                    .font(.viet(15, .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(avatarColors[index % avatarColors.count])
                    .clipShape(Circle())
                if member.activeToday {
                    Circle().fill(Theme.greenBright)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(member.isMe ? "\(member.displayName) (bạn)" : member.displayName)
                        .font(.viet(14, member.isMe ? .bold : .semibold))
                    if member.role == "leader" {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10)).foregroundStyle(Color(hex: 0xD4A94E))
                    }
                }
                Text(member.activeToday ? "đã vận động hôm nay" : "chưa vận động hôm nay")
                    .font(.viet(11.5))
                    .foregroundStyle(member.activeToday ? Theme.greenDeep : Theme.faint)
            }
            Spacer()
            ZStack {
                ProgressRing(progress: member.contributionPct, lineWidth: 4.5)
                    .frame(width: 38, height: 38)
                Text("\(Int(member.contributionPct * 100))%")
                    .font(.mono(9.5, .bold)).foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: - actions

    private func reload() async {
        await app.refresh()
        if app.guild?.exists != true {
            discovered = (try? await APIClient.shared.discoverGuilds()) ?? []
        }
        detectQuestCelebration()
    }

    /// Confetti + success haptic when a guild quest completes while the
    /// user is around to see it (baseline on first load, per screen visit).
    private func detectQuestCelebration() {
        let done = Set((guild?.quests ?? []).filter(\.completed).map(\.key))
        defer { celebratedKeys = done }
        guard let seen = celebratedKeys else { return }
        if !done.subtracting(seen).isEmpty {
            Haptics.success()
            withAnimation { celebrating = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { celebrating = false }
            }
        }
    }

    /// Returns an error message to show inside the sheet, or nil on success.
    private func createGuild(name: String, emblem: String, zalo: String) async -> String? {
        do {
            app.guild = try await APIClient.shared.createGuild(
                name: name, emblem: emblem, zaloLink: zalo.isEmpty ? nil : zalo
            )
            showCreate = false
            Haptics.success()
            app.showToast("Hội đã lập — gửi mã mời cho đồng bọn!")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func joinByCode() async {
        busy = true
        error = nil
        do {
            app.guild = try await APIClient.shared.joinGuild(code: joinCode)
            joinCode = ""
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func joinById(_ id: UUID) async {
        busy = true
        error = nil
        do {
            app.guild = try await APIClient.shared.joinGuild(id: id)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    /// Returns an error message to show inside the sheet, or nil on success.
    private func saveSettings(emblem: String, zalo: String) async -> String? {
        do {
            app.guild = try await APIClient.shared.updateGuildSettings(emblem: emblem, zaloLink: zalo)
            showSettings = false
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func leave() async {
        do {
            try await APIClient.shared.leaveGuild()
            app.guild = nil
            celebratedKeys = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Soft repeating pulse for the "active now" dot.
private struct PulseDot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - create sheet

private let emblemChoices = ["🦔", "🌙", "🔥", "⚡", "🌿", "🏃", "💪", "🌸", "🚀", "🐢"]

struct GuildCreateSheet: View {
    let onCreate: (String, String, String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emblem = "🦔"
    @State private var zalo = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private var validName: Bool { (3...30).contains(name.trimmingCharacters(in: .whitespaces).count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Lập hội mới").font(.viet(20, .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 34, height: 34)
                        .background(Theme.dimBg)
                        .clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Tên hội").font(.viet(13, .bold)).foregroundStyle(Theme.muted)
                TextField("VD: Hội Chạy Đêm Q7", text: $name)
                    .font(.viet(17, .semibold))
                    .foregroundStyle(Theme.ink)
                    .focused($nameFocused)
                    .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
                    .background(Theme.dimBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Biểu tượng").font(.viet(13, .bold)).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(emblemChoices, id: \.self) { choice in
                            Button {
                                emblem = choice
                                Haptics.tick()
                            } label: {
                                Text(choice)
                                    .font(.system(size: 24))
                                    .frame(width: 48, height: 48)
                                    .background(emblem == choice ? Theme.purpleBg : Theme.dimBg)
                                    .clipShape(Circle())
                                    .overlay {
                                        if emblem == choice {
                                            Circle().strokeBorder(Theme.purpleDeep, lineWidth: 2)
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Link nhóm Zalo (tuỳ chọn)").font(.viet(13, .bold)).foregroundStyle(Theme.muted)
                TextField("https://zalo.me/g/…", text: $zalo)
                    .font(.viet(15))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                    .background(Theme.dimBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Chat của hội sống bên Zalo — app chỉ lo thi đua.")
                    .font(.viet(11.5)).foregroundStyle(Theme.faint)
            }

            if let error {
                Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            PrimaryButton(title: busy ? "Đang lập hội…" : "Lập hội", height: 56, color: Theme.purpleDeep, glow: true) {
                busy = true
                error = nil
                Task {
                    error = await onCreate(name.trimmingCharacters(in: .whitespaces), emblem, zalo.trimmingCharacters(in: .whitespaces))
                    busy = false
                }
            }
            .disabled(!validName || busy)
            .opacity(validName ? 1 : 0.5)
        }
        .padding(20)
        .background(Theme.sheetBg)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
        .onAppear { nameFocused = true }
    }
}

// MARK: - settings sheet (leader only)

struct GuildSettingsSheet: View {
    @State var emblem: String
    @State var zaloLink: String
    let onSave: (String, String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Cài đặt hội").font(.viet(20, .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 34, height: 34)
                        .background(Theme.dimBg)
                        .clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Biểu tượng").font(.viet(13, .bold)).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(emblemChoices, id: \.self) { choice in
                            Button {
                                emblem = choice
                                Haptics.tick()
                            } label: {
                                Text(choice)
                                    .font(.system(size: 24))
                                    .frame(width: 48, height: 48)
                                    .background(emblem == choice ? Theme.purpleBg : Theme.dimBg)
                                    .clipShape(Circle())
                                    .overlay {
                                        if emblem == choice {
                                            Circle().strokeBorder(Theme.purpleDeep, lineWidth: 2)
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Link nhóm Zalo").font(.viet(13, .bold)).foregroundStyle(Theme.muted)
                TextField("https://zalo.me/g/…", text: $zaloLink)
                    .font(.viet(15))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                    .background(Theme.dimBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let error {
                Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            PrimaryButton(title: busy ? "Đang lưu…" : "Lưu", height: 54, color: Theme.purpleDeep) {
                busy = true
                error = nil
                Task {
                    error = await onSave(emblem, zaloLink.trimmingCharacters(in: .whitespaces))
                    busy = false
                }
            }
            .disabled(busy)
        }
        .padding(20)
        .background(Theme.sheetBg)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}
