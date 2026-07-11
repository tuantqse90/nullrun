import Foundation

// DTOs mirror backend /v1 responses (snake_case decoded globally).

struct User: Codable {
    let id: UUID
    let phone: String
    let displayName: String?
}

struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String
    let user: User
}

struct Device: Codable {
    let id: UUID
    let platform: String
    let attestedAt: Date?
}

struct MePoints: Codable {
    let balance: Int
    let season: String
    let seasonEarned: Int
    let todayEarned: Int
    let lifetimeEarned: Int
    let tier: String
    let nextTierAt: Int?
    let streakCurrent: Int
    let streakBest: Int
    let dailyCap: Int
    let weeklyGoalKm: Double
    let weeklyKm: Double
    let displayName: String?
    let level: Int
    let xpInLevel: Int
    let xpPerLevel: Int
}

/// AI coach nudge — server phrases the user's REAL weekly stats (or a
/// deterministic template when no AI key). `ai` flags which produced it.
struct CoachInsight: Codable {
    let ai: Bool
    let headline: String
    let body: String
}

/// One reply from the in-app health coach chat.
struct CoachChatReply: Codable {
    let ai: Bool
    let reply: String
}

struct GameStatus: Codable, Identifiable {
    let code: String
    let title: String
    let description: String
    let category: String
    let tier: String
    let verification: String
    let targetValue: Double
    let unit: String
    let rewardPoints: Int
    let cadence: String
    let progress: Double?
    let completed: Bool
    let claimable: Bool

    var id: String { code }
}

struct DuelPlayer: Codable, Identifiable {
    let userId: UUID
    let displayName: String
    let isMe: Bool
    let distanceM: Double
    let hasSession: Bool

    var id: UUID { userId }
}

struct DuelState: Codable {
    let exists: Bool
    let id: UUID?
    let code: String?
    let targetM: Double?
    let rewardPoints: Int?
    let status: String?
    let winnerId: UUID?
    let players: [DuelPlayer]?
}

struct QuestStatus: Codable, Identifiable {
    let key: String
    let title: String
    let target: Double
    let progress: Double
    let completed: Bool
    let rewardPoints: Int

    var id: String { key }
}

struct WheelState: Codable {
    let segments: [Int]
    let available: Bool
    let spunToday: Bool
    let unlocked: Bool
}

struct SpinResult: Codable {
    let prize: Int
    let segmentIndex: Int
}

struct ActivitySession: Codable, Identifiable {
    let id: UUID
    let activityType: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let distanceM: Double
    let durationS: Double
    let avgPaceSPerKm: Double?
    let verdict: String
    let pointsEarned: Int?
    let challengeBonus: Int?
}

struct GpsPointDTO: Codable {
    let recordedAt: Date
    let lat: Double
    let lon: Double
    let altitudeM: Double?
    let horizontalAccuracyM: Double?
    let speedMps: Double?
    let stepCadence: Double?
}

struct Reward: Codable, Identifiable {
    let id: UUID
    let partner: String
    let title: String
    let description: String?
    let costPoints: Int
    let stock: Int?

    /// Ticket-style card for vouchers, product card otherwise (per design).
    var isVoucher: Bool { title.lowercased().contains("voucher") }
}

struct Redemption: Codable, Identifiable {
    let id: UUID
    let rewardId: UUID
    let title: String
    let costPoints: Int
    let status: String
    let voucherCode: String?
    let createdAt: Date
    let expiresAt: Date
}

struct LeaderboardEntry: Codable {
    let rank: Int
    let displayName: String
    let points: Int
    let isMe: Bool
}

struct LeagueStanding: Codable {
    let week: String
    let joined: Bool
    let bucket: Int?
    let standings: [LeaderboardEntry]?
}

struct RaceMilestone: Codable, Identifiable {
    let distanceM: Double
    let guildXp: Int
    let reached: Bool

    var id: Double { distanceM }
}

struct RaceStanding: Codable {
    let displayName: String
    let distanceM: Double
    let isMe: Bool
}

/// Time-windowed daily race (giải khung giờ) — only counts sessions started
/// inside its VN-time hours; milestones feed guild XP.
struct RaceWindow: Codable, Identifiable {
    let code: String
    let title: String
    let icon: String
    let startHour: Int
    let endHour: Int
    let open: Bool
    let opensInS: Int
    let closesInS: Int
    let myDistanceM: Double
    let milestones: [RaceMilestone]
    let standings: [RaceStanding]

    var id: String { code }
}

struct GuildMember: Codable, Identifiable {
    let userId: UUID
    let displayName: String
    let role: String
    let isMe: Bool
    let activeToday: Bool
    /// % of the member's OWN weekly goal (0…1) — the design never compares
    /// absolute km between members.
    let contributionPct: Double

    var id: UUID { userId }
}

struct GuildQuestItem: Codable, Identifiable {
    let key: String
    let title: String
    let description: String
    let cadence: String
    let target: Double
    let progress: Double
    let completed: Bool
    let xpReward: Int

    var id: String { key }
}

struct GuildState: Codable {
    let exists: Bool
    let id: UUID?
    let name: String?
    let emblem: String?
    let code: String?
    let zaloLink: String?
    let xp: Int?
    let level: Int?
    let xpInLevel: Int?
    let xpPerLevel: Int?
    let memberCount: Int?
    let maxMembers: Int?
    let activeToday: Int?
    let isLeader: Bool?
    let members: [GuildMember]?
    let quests: [GuildQuestItem]?
}

struct GuildDiscoverRow: Codable, Identifiable {
    let id: UUID
    let name: String
    let emblem: String
    let xp: Int
    let level: Int
    let memberCount: Int
    let activeWeek: Int
}

struct ChallengeItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String?
    let target: Double
    let rewardPoints: Int
    let joined: Bool
    let progress: Double?
    let completedAt: Date?
}
