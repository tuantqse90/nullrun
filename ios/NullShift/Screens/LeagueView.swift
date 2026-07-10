import SwiftUI

/// Weekly league per design s11: promotion zone (top 10, green), your row
/// highlighted, demotion zone (bottom 5, red hatch). Ranked by activity
/// points — never by weight (design principle, shown in the footer).
struct LeagueView: View {
    @EnvironmentObject private var app: AppModel

    private let promotionCut = 10
    private let demotionCount = 5

    private var standings: [LeaderboardEntry] { app.league?.standings ?? [] }
    private var joined: Bool { app.league?.joined ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 6)
            duelEntry.padding(.horizontal, 20).padding(.bottom, 8)
            raceEntries.padding(.horizontal, 20).padding(.bottom, 10)
            if joined && !standings.isEmpty {
                Text("\(standings.count) người cùng hạng điểm tuần này")
                    .font(.viet(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 12)
                board
                    .padding(.horizontal, 20)
                Text("Xếp hạng theo điểm vận động — không bao giờ theo cân nặng")
                    .font(.viet(12.5)).foregroundStyle(Theme.faint)
                    .padding(.vertical, 12)
            } else {
                emptyState
            }
            AppTabBar(active: .league) { tab in
                switch tab {
                case .today: app.screen = .home
                case .rewards: app.screen = .rewards
                case .guild: app.screen = .guild
                case .body: app.screen = .scanIntro
                default: break
                }
            }
        }
        .background(Theme.bg)
        .task { await app.refresh() }
    }

    /// Time-windowed daily races: a live card while a window is open, a
    /// compact countdown teaser while closed. Milestones feed guild XP.
    @ViewBuilder
    private var raceEntries: some View {
        VStack(spacing: 8) {
            ForEach(app.races) { race in
                if race.open {
                    openRaceCard(race)
                } else {
                    closedRaceRow(race)
                }
            }
        }
    }

    private func openRaceCard(_ race: RaceWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(race.icon).font(.system(size: 18))
                Text(race.title).font(.viet(15, .bold)).foregroundStyle(.white)
                HStack(spacing: 5) {
                    PulsingDot()
                    Text("ĐANG MỞ").font(.viet(10.5, .heavy)).foregroundStyle(Theme.greenPale)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.greenDarkPill)
                .clipShape(Capsule())
                Spacer()
                Text("đóng sau \(Self.countdown(race.closesInS))")
                    .font(.mono(11.5)).foregroundStyle(Color(hex: 0xFFE3AC))
            }

            // milestone chips — hit as many as you can inside the window
            HStack(spacing: 7) {
                ForEach(race.milestones) { m in
                    HStack(spacing: 4) {
                        Image(systemName: m.reached ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 11, weight: .bold))
                        Text(m.distanceM >= 1000
                             ? "\(Int(m.distanceM / 1000))km"
                             : "\(Int(m.distanceM))m")
                            .font(.mono(12, .bold))
                        Text("+\(m.guildXp)").font(.mono(10.5))
                    }
                    .foregroundStyle(m.reached ? Theme.greenDarkPill : .white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(m.reached ? AnyShapeStyle(Theme.greenPale) : AnyShapeStyle(.white.opacity(0.16)))
                    .clipShape(Capsule())
                }
                Spacer()
            }

            HStack {
                if race.myDistanceM > 0 {
                    Text("Bạn: \(Fmt.dist(race.myDistanceM / 1000)) km")
                        .font(.viet(12.5, .bold)).foregroundStyle(.white)
                }
                if let leader = race.standings.first {
                    Text("Dẫn đầu: \(leader.displayName) · \(Fmt.dist(leader.distanceM / 1000)) km")
                        .font(.viet(12)).foregroundStyle(Color(hex: 0xFFE3AC))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    app.screen = .prerun
                } label: {
                    Text("Vào đua")
                        .font(.viet(13, .bold)).foregroundStyle(Theme.orangeDeep)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white)
                        .clipShape(Capsule())
                }
            }

            Text("Mốc đạt được cộng XP cho hội của bạn")
                .font(.viet(10.5)).foregroundStyle(.white.opacity(0.75))
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 11, trailing: 15))
        .background(
            LinearGradient(
                colors: race.code == "dawn"
                    ? [Theme.orangeDeep, Theme.orange]
                    : [Theme.purpleDark, Theme.purpleDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shineSweep(opacity: 0.14)
    }

    private func closedRaceRow(_ race: RaceWindow) -> some View {
        HStack(spacing: 10) {
            Text(race.icon).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 0) {
                Text(race.title).font(.viet(13.5, .bold))
                Text("Khung \(race.startHour):00–\(race.endHour):00 · mốc 500m/2km/5km cộng XP hội")
                    .font(.viet(11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("mở sau").font(.viet(10)).foregroundStyle(Theme.faint)
                Text(Self.countdown(race.opensInS))
                    .font(.mono(13, .bold)).foregroundStyle(Theme.orangeDeep)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
    }

    private static func countdown(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))'" : "\(m)'"
    }

    private var duelEntry: some View {
        Button { app.screen = .duel } label: {
            HStack(spacing: 13) {
                HStack(spacing: -8) {
                    Mascot(mood: .running, bobbing: false).frame(width: 34, height: 28)
                    Mascot(mood: .running, bobbing: false).frame(width: 34, height: 28).scaleEffect(x: -1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(duelLabel).font(.viet(15, .bold)).foregroundStyle(.white)
                    Text("Đua 500 m tay đôi — GPS thật phân thắng bại")
                        .font(.viet(12.5)).foregroundStyle(Color(hex: 0xD9CCF2))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xD9CCF2))
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(LinearGradient(colors: [Theme.purpleDeep, Theme.purpleMid], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    private var duelLabel: String {
        switch app.duel?.status {
        case "open": "Thách đấu 1v1 — đang chờ đối thủ"
        case "active": "Thách đấu 1v1 — trận đang diễn ra!"
        default: "Thách đấu 1v1"
        }
    }

    private var header: some View {
        HStack {
            Text(joined ? app.leagueTitle : "Giải đấu tuần").font(.viet(23, .bold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 12, weight: .semibold))
                Text(daysLeftLabel).font(.viet(13.5, .semibold))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.white)
            .clipShape(Capsule())
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
        }
        .padding(.bottom, 4)
    }

    private var daysLeftLabel: String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let left = weekday == 1 ? 1 : 9 - weekday
        return "Còn \(left) ngày"
    }

    private var board: some View {
        ScrollView {
            VStack(spacing: 0) {
                zoneHeader(icon: "arrow.up", text: "Vùng thăng hạng — top \(min(promotionCut, standings.count))",
                           fg: Theme.greenDeep, bg: Theme.greenBgSoft)
                ForEach(standings, id: \.rank) { entry in
                    if entry.isMe {
                        meRow(entry)
                    } else {
                        row(entry)
                    }
                    if entry.rank == promotionCut && standings.count > promotionCut {
                        Divider().overlay(Theme.divider)
                    }
                    if isDemotionStart(after: entry.rank) {
                        zoneHeader(icon: "arrow.down", text: "Vùng xuống hạng — \(demotionCount) cuối",
                                   fg: Theme.danger, bg: Color(hex: 0xF7E9E7))
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
        }
    }

    private func isDemotionStart(after rank: Int) -> Bool {
        standings.count > 15 && rank == standings.count - demotionCount
    }

    private func inDemotion(_ rank: Int) -> Bool {
        standings.count > 15 && rank > standings.count - demotionCount
    }

    private func zoneHeader(icon: String, text: String, fg: Color, bg: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.viet(12.5, .bold))
            Spacer()
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(bg)
    }

    private func row(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.mono(14, .regular))
                .foregroundStyle(inDemotion(entry.rank) ? Theme.danger : Theme.muted)
                .frame(width: 22, alignment: .leading)
            InitialAvatar(name: entry.displayName, index: entry.rank)
            Text(entry.displayName).font(.viet(14.5, .semibold)).lineLimit(1)
            Spacer()
            Text("\(entry.points)").font(.mono(14.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background {
            if inDemotion(entry.rank) {
                HatchPattern().opacity(0.9)
            }
        }
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    private func meRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)").font(.mono(14)).frame(width: 22, alignment: .leading)
            Circle()
                .fill(Theme.green)
                .frame(width: 38, height: 38)
                .overlay {
                    Text(String(entry.displayName.prefix(1)).uppercased())
                        .font(.viet(13, .bold)).foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.displayName) — bạn").font(.viet(15, .heavy))
                Text(meHint(entry)).font(.viet(12, .semibold))
                    .foregroundStyle(entry.rank <= promotionCut ? Theme.green : Theme.orangeDeep)
            }
            Spacer()
            Text("\(entry.points)").font(.mono(16, .bold))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.sheetBg)
        .overlay(alignment: .top) {
            Line().stroke(Color(hex: 0xC9E2D3), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(height: 2)
        }
        .overlay(alignment: .bottom) { Theme.divider.frame(height: 1) }
    }

    /// League one tier above the user's current one (promotion target).
    private var nextLeagueTitle: String {
        switch app.points?.tier {
        case "bronze": return "Giải Bạc"
        case "silver": return "Giải Vàng"
        case "gold", "platinum": return "Giải Bạch Kim"
        default: return "hạng trên"
        }
    }

    private func meHint(_ entry: LeaderboardEntry) -> String {
        if entry.rank <= promotionCut { return "Giữ vững là lên \(nextLeagueTitle)" }
        let demotionStart = standings.count - demotionCount + 1
        let gap = demotionStart - entry.rank
        if standings.count > 15 && gap <= 3 { return "Cách vùng xuống hạng \(gap) bậc" }
        return "Top \(promotionCut) sẽ thăng hạng"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Mascot(mood: .running).frame(width: 96, height: 80)
            Text("Chưa vào bảng đấu tuần này").font(.viet(19, .bold))
            Text("Hoàn thành 1 buổi tập có điểm là bạn được xếp vào\nbảng 50 người cùng nhịp độ.")
                .font(.viet(14)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Bắt đầu buổi đầu tiên", height: 56, glow: true) {
                app.screen = .prerun
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct InitialAvatar: View {
    let name: String
    let index: Int

    private static let palette: [(bg: UInt32, fg: UInt32)] = [
        (0xDCE7F5, 0x3D5C9E), (0xF5E3DC, 0xB85E23), (0xE4EFE0, 0x4B7040),
        (0xEAE4F2, 0x6B5A9E), (0xE9E3D7, 0x8A8072),
    ]

    var body: some View {
        let colors = Self.palette[index % Self.palette.count]
        Circle()
            .fill(Color(hex: colors.bg))
            .frame(width: 34, height: 34)
            .overlay {
                Text(initials).font(.viet(13, .bold)).foregroundStyle(Color(hex: colors.fg))
            }
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { !$0.hasPrefix("•") }
        let letters = words.suffix(2).compactMap(\.first)
        return letters.isEmpty ? "R" : String(letters).uppercased()
    }
}

struct HatchPattern: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFBF3F2)))
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: .init(x: x, y: size.height))
                p.addLine(to: .init(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(Color(hex: 0xF7E9E7)), lineWidth: 4)
                x += 12
            }
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: rect.minX, y: rect.midY))
        p.addLine(to: .init(x: rect.maxX, y: rect.midY))
        return p
    }
}
