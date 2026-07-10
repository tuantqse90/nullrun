import Foundation
import SwiftUI
import UIKit

/// Screen router mirroring the prototype's state machine.
enum Screen: Equatable {
    case home
    case prerun
    case run
    case locked
    case summary(ActivitySession)
    case rewards
    case voucher(Redemption)
    case wheel
    case league
    case guild
    case games
    case duel
    case scanIntro, scanCam, scanProc, scanRes

    var isDark: Bool {
        switch self {
        case .run, .locked, .scanCam: true
        default: false
        }
    }

    static func == (lhs: Screen, rhs: Screen) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.prerun, .prerun), (.run, .run), (.locked, .locked),
             (.rewards, .rewards), (.wheel, .wheel), (.scanIntro, .scanIntro),
             (.scanCam, .scanCam), (.scanProc, .scanProc), (.scanRes, .scanRes),
             (.league, .league), (.guild, .guild), (.games, .games), (.duel, .duel):
            true
        case (.summary(let a), .summary(let b)): a.id == b.id
        case (.voucher(let a), .voucher(let b)): a.id == b.id
        default: false
        }
    }
}

/// App-wide state — everything here is server data; the only client-side
/// persistence left is body-scan measurements, which stay on device by
/// design (privacy story).
@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published var points: MePoints?
    @Published var quests: [QuestStatus] = []
    @Published var wheel: WheelState?
    @Published var catalog: [Reward] = []
    @Published var wallet: [Redemption] = []
    @Published var league: LeagueStanding?
    @Published var games: [GameStatus] = []
    @Published var duel: DuelState?
    @Published var guild: GuildState?
    @Published var races: [RaceWindow] = []
    @Published var pendingDuelId: UUID?
    @Published var deviceId: UUID?
    @Published var toast: String?
    @Published var guardianLinked = UserDefaults.standard.bool(forKey: "guardian.linked")
    @Published var sessionsToday = 0
    @Published var celebration: Celebration?
    /// Scan photos in transit between capture and measuring — RAM only,
    /// cleared the moment processing finishes (the privacy promise).
    @Published var scanFront: UIImage?
    @Published var scanSide: UIImage?

    var balance: Int { points?.balance ?? 0 }
    var weeklyKm: Double { points?.weeklyKm ?? 0 }
    var weeklyGoalKm: Double { points?.weeklyGoalKm ?? 25 }

    // Level comes straight from the server (single source of truth).
    var levelNum: Int { points?.level ?? 2 }
    var xpToNext: Int { (points?.xpPerLevel ?? 120) - (points?.xpInLevel ?? 0) }
    var xpFraction: Double {
        Double(points?.xpInLevel ?? 0) / Double(max(1, points?.xpPerLevel ?? 120))
    }

    /// League display name follows the member tier (both are season-scoped).
    var leagueTitle: String {
        switch points?.tier {
        case "silver": "Giải Bạc"
        case "gold": "Giải Vàng"
        case "platinum": "Giải Bạch Kim"
        default: "Giải Đồng"
        }
    }

    func bootstrap() async {
        await ensureDevice()
        await refresh()
        #if DEBUG
        // Design-QA hook: jump straight to a screen (simulator only).
        switch ProcessInfo.processInfo.environment["DEV_SCREEN"] {
        case "league": screen = .league
        case "guild": screen = .guild
        case "rewards": screen = .rewards
        case "wheel": screen = .wheel
        case "games": screen = .games
        case "duel": screen = .duel
        case "prerun": screen = .prerun
        // The designed v1.5 scan-capture screens — reachable only for
        // design QA until the real Core ML engine lands.
        case "scancam": screen = .scanCam
        case "scanres": screen = .scanRes
        default: break
        }
        // Force-show a celebration for design QA (simulator only).
        switch ProcessInfo.processInfo.environment["DEV_CELEBRATE"] {
        case "tier": celebration = .tierUp(tier: "silver", seasonEarned: points?.seasonEarned ?? 1200)
        case "level": celebration = .levelUp(level: levelNum)
        case "streak": celebration = .streakMilestone(days: 7)
        default: break
        }
        #endif
    }

    func refresh() async {
        async let p: MePoints? = try? APIClient.shared.mePoints()
        async let q: [QuestStatus]? = try? APIClient.shared.quests()
        async let wh: WheelState? = try? APIClient.shared.wheelState()
        async let r: [Reward]? = try? APIClient.shared.rewards()
        async let w: [Redemption]? = try? APIClient.shared.redemptions()
        async let l: LeagueStanding? = try? APIClient.shared.league()
        async let g: [GameStatus]? = try? APIClient.shared.games()
        async let d: DuelState? = try? APIClient.shared.currentDuel()
        async let gu: GuildState? = try? APIClient.shared.myGuild()
        async let rc: [RaceWindow]? = try? APIClient.shared.races()
        async let s: [ActivitySession]? = try? APIClient.shared.sessions()
        points = await p
        quests = await q ?? []
        wheel = await wh
        catalog = await r ?? []
        wallet = (await w ?? []).filter { $0.status == "fulfilled" && $0.expiresAt > Date() }
        league = await l
        games = await g ?? []
        duel = await d
        guild = await gu
        races = await rc ?? []

        if let sessions = await s {
            sessionsToday = sessions
                .filter { $0.status == "completed" && Calendar.current.isDateInToday($0.startedAt) }
                .count
        }

        detectCelebrations()
    }

    /// Compares tier/level/streak against the last-seen values and queues at
    /// most one celebration — priority: tier ceremony > level-up > streak
    /// milestone. The first refresh only records a baseline so a fresh
    /// login never celebrates stale progress.
    private func detectCelebrations() {
        guard let p = points else { return }
        let d = UserDefaults.standard
        let tierRank = ["bronze": 0, "silver": 1, "gold": 2, "platinum": 3][p.tier] ?? 0
        let milestones: Set<Int> = [3, 7, 14, 21, 30, 50, 100]

        defer {
            d.set(tierRank, forKey: "seen.tier")
            d.set(p.level, forKey: "seen.level")
            d.set(p.streakCurrent, forKey: "seen.streak")
            d.set(true, forKey: "seen.baseline")
        }
        guard d.bool(forKey: "seen.baseline"), celebration == nil else { return }

        if tierRank > d.integer(forKey: "seen.tier") {
            withAnimation { celebration = .tierUp(tier: p.tier, seasonEarned: p.seasonEarned) }
        } else if p.level > d.integer(forKey: "seen.level") {
            withAnimation { celebration = .levelUp(level: p.level) }
        } else if p.streakCurrent > d.integer(forKey: "seen.streak"),
                  milestones.contains(p.streakCurrent) {
            withAnimation { celebration = .streakMilestone(days: p.streakCurrent) }
        }
    }

    func setWeeklyGoal(km: Double) async {
        guard (5...200).contains(km) else { return }
        try? await APIClient.shared.updateWeeklyGoal(km: km)
        await refresh()
    }

    /// Register (dev-attested) device once; reuse its id for sessions.
    func ensureDevice() async {
        if let raw = UserDefaults.standard.string(forKey: "device.id"), let id = UUID(uuidString: raw) {
            deviceId = id
            return
        }
        if let device = try? await APIClient.shared.registerDevice() {
            UserDefaults.standard.set(device.id.uuidString, forKey: "device.id")
            deviceId = device.id
        }
    }

    /// The stored registration can be stale (UserDefaults survives
    /// reinstall; the server may not know the id). Drop it and register
    /// fresh — callers retry their request with the returned id.
    func reregisterDevice() async -> UUID? {
        UserDefaults.standard.removeObject(forKey: "device.id")
        deviceId = nil
        await ensureDevice()
        return deviceId
    }

    func linkGuardian(memberId: String) async throws {
        try await APIClient.shared.linkGuardian(memberId: memberId)
        guardianLinked = true
        UserDefaults.standard.set(true, forKey: "guardian.linked")
    }

    func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation { self.toast = nil }
        }
    }

    // Greeting per time of day, date line in Vietnamese.
    var greeting: String {
        let name = points?.displayName ?? "bạn"
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "Chào buổi sáng, \(name)"
        case 11..<14: return "Chào buổi trưa, \(name)"
        case 14..<18: return "Chào buổi chiều, \(name)"
        default: return "Chào buổi tối, \(name)"
        }
    }

    var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: Date()).capitalized(with: Locale(identifier: "vi_VN"))
    }
}
