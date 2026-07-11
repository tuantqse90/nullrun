import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var goalPrompt = false
    @State private var goalInput = ""
    @State private var showCoach = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 13) {
                    header.riseIn(0)
                    weeklyGoalCard.riseIn(1)
                    coachCard.riseIn(2)
                    statGrid.riseIn(3)
                    leagueCard.riseIn(4)
                    levelCard.riseIn(5)
                    questsCard.riseIn(6)
                    gamesCard.riseIn(7)
                    critterCard.riseIn(8)
                    wheelBanner.riseIn(9)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            startButton
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            AppTabBar(active: .today) { tab in
                switch tab {
                case .league: app.screen = .league
                case .rewards: app.screen = .rewards
                case .guild: app.screen = .guild
                case .body: app.screen = .scanIntro
                default: break
                }
            }
        }
        .background(Theme.bg)
        .task { await app.refresh() }
        .sheet(isPresented: $showCoach) {
            HealthChatView()
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEV_COACH"] != nil { showCoach = true }
            #endif
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.purpleBg)
                    Mascot(mood: .happy)
                        .frame(width: 44, height: 38)
                        .offset(y: 6)
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                // Tap the mascot to chat with Nhím Coach (health/running/food).
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(4).background(Theme.green).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
                .contentShape(Circle())
                .onTapGesture { Haptics.light(); showCoach = true }
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.dateLine).font(.viet(14)).foregroundStyle(Theme.muted)
                    Text(app.greeting).font(.viet(23, .bold))
                }
            }
            Spacer()
            StreakPill(days: app.points?.streakCurrent ?? 0)
        }
    }

    private var weeklyGoalCard: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: app.weeklyKm / max(1, app.weeklyGoalKm))
                    .frame(width: 104, height: 104)
                OrbitingSpark(radius: 52)
                Text("\(Int(min(100, app.weeklyKm / max(1, app.weeklyGoalKm) * 100)))%")
                    .font(.mono(21))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Mục tiêu tuần này").font(.viet(14)).foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", app.weeklyKm).replacingOccurrences(of: ".", with: ","))
                        .font(.mono(24))
                    Text("/ \(Int(app.weeklyGoalKm)) km").font(.mono(15, .regular)).foregroundStyle(Theme.muted)
                }
                Text(weeklyHint).font(.viet(13.5, .semibold)).foregroundStyle(Theme.green)
            }
            Spacer(minLength: 0)
        }
        .card(radius: 22, padding: EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22))
        .contentShape(Rectangle())
        .onTapGesture { goalPrompt = true }
        .alert("Mục tiêu tuần (km)", isPresented: $goalPrompt) {
            TextField("VD: 25", text: $goalInput).keyboardType(.numberPad)
            Button("Lưu") {
                if let km = Double(goalInput.replacingOccurrences(of: ",", with: ".")) {
                    Task { await app.setWeeklyGoal(km: km) }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Từ 5 đến 200 km — chạm thẻ này để đổi bất cứ lúc nào.")
        }
    }

    private var weeklyHint: String {
        // Server weeks start Monday (VN). Apple weekday is 1=Sun…7=Sat;
        // map to Mon=0…Sun=6 so days-left-incl-today is correct all week.
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mondayIdx = (weekday + 5) % 7
        let daysLeft = 7 - mondayIdx
        return app.weeklyKm >= app.weeklyGoalKm
            ? "Đã đạt mục tiêu — quá đỉnh!"
            : "Còn \(daysLeft) ngày — bạn đang đúng nhịp"
    }

    private var statGrid: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Buổi tập hôm nay").font(.viet(13)).foregroundStyle(Theme.muted)
                Text("\(app.sessionsToday)").font(.mono(23))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            VStack(alignment: .leading, spacing: 0) {
                Text("Điểm hôm nay").font(.viet(13)).foregroundStyle(Theme.muted)
                Text("+\(app.points?.todayEarned ?? 0)").font(.mono(23)).foregroundStyle(Theme.greenDeep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var leagueCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(hex: 0xE8EAF0), Color(hex: 0xC9CBD4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: 0x9FA3B2))
                    .overlay {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.white).offset(y: -1)
                    }
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(leagueTitle).font(.viet(15, .bold))
                    Text(leagueRank).font(.mono(14, .regular)).foregroundStyle(Theme.muted)
                }
                Text("Top 10 sẽ thăng hạng · tuần này").font(.viet(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xC6BEB0))
        }
        .card()
    }

    private var leagueTitle: String { app.leagueTitle }

    private var leagueRank: String {
        guard let league = app.league, league.joined, let standings = league.standings,
              let mine = standings.first(where: { $0.isMe }) else { return "chưa xếp hạng" }
        return "hạng \(mine.rank)/\(standings.count)"
    }

    /// AI coach nudge — phrased by the server from the user's real weekly
    /// numbers (or a template when no AI key). Tap to regenerate. Purely
    /// motivational copy; it never mints points (economy firewall).
    @ViewBuilder private var coachCard: some View {
        if let coach = app.coach {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.purpleBg)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.purple)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(coach.headline)
                            .font(.viet(14, .bold)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if coach.ai {
                            Text("AI").font(.mono(9, .bold)).foregroundStyle(Theme.purpleDeep)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.purpleBg).clipShape(Capsule())
                        }
                    }
                    Text(coach.body)
                        .font(.viet(12.5)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.light()
                Task { await app.reloadCoach() }
            }
        }
    }

    private var levelCard: some View {
        HStack(spacing: 12) {
            Mascot(mood: .happy, bobbing: false).frame(width: 34, height: 30)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Cấp \(app.levelNum)").font(.viet(14, .bold))
                    Text("· Nhím Tím").font(.viet(12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(app.xpToNext) XP nữa").font(.mono(12, .regular)).foregroundStyle(Theme.muted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.purpleBg)
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.purpleMid, Theme.purpleSoft], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * app.xpFraction)
                    }
                }
                .frame(height: 8)
            }
        }
        .card()
    }

    private var questsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Nhiệm vụ hôm nay").font(.viet(14, .bold))
                Spacer()
                Text("\(app.quests.filter(\.completed).count)/\(max(1, app.quests.count))")
                    .font(.mono(13, .regular)).foregroundStyle(Theme.muted)
            }
            ForEach(app.quests) { quest in
                questRow(text: quest.title, done: quest.completed, reward: quest.rewardPoints)
            }
            if app.quests.isEmpty {
                Text("Đang tải nhiệm vụ…").font(.viet(13)).foregroundStyle(Theme.faint)
            }
        }
        .card(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }

    private func questRow(text: String, done: Bool, reward: Int = 5) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(done ? Theme.green : .clear)
                Circle()
                    .strokeBorder(done ? Theme.green : Color(hex: 0xC6BEB0), lineWidth: 2)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            Text(text)
                .font(.viet(13.5))
                .foregroundStyle(done ? Theme.muted : Theme.ink)
            Spacer()
            Text("+\(reward)").font(.mono(12.5)).foregroundStyle(Theme.greenDeep)
        }
    }

    private var gamesCard: some View {
        Button { app.screen = .games } label: {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.greenBgSoft)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "gamecontroller").font(.system(size: 20)).foregroundStyle(Theme.greenDeep)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Games").font(.viet(15, .bold)).foregroundStyle(Theme.ink)
                        Text("\(app.games.filter(\.completed).count)/\(app.games.count)")
                            .font(.mono(13, .regular)).foregroundStyle(Theme.muted)
                    }
                    Text("Thử thách sức khoẻ — nhận điểm mỗi ngày")
                        .font(.viet(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xC6BEB0))
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
        }
        .buttonStyle(PressScale())
    }

    private var critterCard: some View {
        Button { app.screen = .catchIntro } label: {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.orangeBg)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "pawprint.fill").font(.system(size: 20)).foregroundStyle(Theme.orangeDeep)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thú cưng đường phố").font(.viet(15, .bold)).foregroundStyle(Theme.ink)
                    Text("Bắt chó mèo ngoài đường vào Sổ Bạn Nhỏ 🐾")
                        .font(.viet(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xC6BEB0))
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
        }
        .buttonStyle(PressScale())
    }

    @ViewBuilder
    private var wheelBanner: some View {
        if app.wheel?.available == true {
            Button { app.screen = .wheel } label: {
                HStack(spacing: 13) {
                    WheelDisc().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Vòng quay sẵn sàng!").font(.viet(15, .bold)).foregroundStyle(.white)
                        Text("Quà cho buổi tập hôm nay — mọi ô đều trúng")
                            .font(.viet(12.5)).foregroundStyle(Color(hex: 0xD9CCF2))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xD9CCF2))
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .background(LinearGradient(colors: [Theme.purpleDeep, Theme.purpleMid], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressScale())
        } else if app.wheel?.unlocked == false {
            HStack(spacing: 12) {
                Image(systemName: "lock").font(.system(size: 16)).foregroundStyle(Theme.faint)
                (Text("Hoàn thành 1 buổi tập để mở ")
                    + Text("vòng quay quà").bold().foregroundColor(Theme.purpleDeep)
                    + Text(" hôm nay"))
                    .font(.viet(13))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(hex: 0xC6BEB0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
    }

    private var startButton: some View {
        Button { app.screen = .prerun } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 17))
                Text("Bắt đầu").font(.viet(19, .bold))
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        ChevronBlink(delay: Double(i) * 0.18)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Theme.green)
            .clipShape(Capsule())
            .shadow(color: Theme.green.opacity(0.35), radius: 9, y: 6)
        }
        .buttonStyle(PressScale())
    }
}

/// Mini spinning wheel disc used in the home banner.
struct WheelDisc: View {
    @State private var spin = false
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                WheelSlice(index: i, total: 6)
                    .fill([Theme.greenBgSoft, Theme.orangeBg, Theme.blueBg][i % 3])
            }
            Circle().strokeBorder(Theme.purpleInk, lineWidth: 3)
        }
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(.linear(duration: 7).repeatForever(autoreverses: false), value: spin)
        .onAppear { spin = true }
    }
}

struct WheelSlice: Shape {
    let index: Int
    let total: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let a0 = Angle.degrees(Double(index) / Double(total) * 360 - 90)
        let a1 = Angle.degrees(Double(index + 1) / Double(total) * 360 - 90)
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct ChevronBlink: View {
    let delay: Double
    @State private var on = false
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay), value: on)
            .onAppear { on = true }
    }
}
