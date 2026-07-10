import Foundation

extension Notification.Name {
    /// Posted when a 401 could not be recovered by token refresh —
    /// the session is dead and the UI must return to login.
    static let authSessionExpired = Notification.Name("authSessionExpired")
}

/// Async client for the NullShift backend. Simulator reaches the host via
/// localhost; physical devices use API_BASE_URL from Info.plist.
final class APIClient {
    static let shared = APIClient()

    /// Simulator talks to the host directly; a physical device uses the
    /// Mac's LAN IP from Info.plist (API_BASE_URL, set in project.yml).
    var baseURL: URL = {
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:8080")!
        #else
        let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        return URL(string: configured ?? "http://localhost:8080")!
        #endif
    }()
    var accessToken: String? { Keychain.get("access_token") }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: s) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad date \(s)"))
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    enum APIError: Error, LocalizedError {
        case server(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .server(_, let message): message
            }
        }

        var status: Int {
            switch self {
            case .server(let status, _): status
            }
        }
    }

    // MARK: auth

    /// Returns the debug code when the backend runs in sms_mode=log (dev).
    @discardableResult
    func requestOTP(phone: String) async throws -> String? {
        struct R: Codable {
            let sent: Bool
            let debugCode: String?
        }
        let r: R = try await send("POST", "/v1/auth/otp/request", body: ["phone": phone], auth: false)
        return r.debugCode
    }

    func verifyOTP(phone: String, code: String) async throws -> TokenPair {
        try await send("POST", "/v1/auth/otp/verify", body: ["phone": phone, "code": code], auth: false)
    }

    func logout(refreshToken: String) async throws {
        struct R: Codable { let loggedOut: Bool }
        let _: R = try await send("POST", "/v1/auth/logout", body: ["refresh_token": refreshToken], auth: false)
    }

    // MARK: devices

    func registerDevice() async throws -> Device {
        struct Challenge: Codable { let challenge: String }
        let _: Challenge = try await send("POST", "/v1/devices/attest/challenge", body: Empty())
        // ATTEST_MODE=dev accepts this placeholder; real App Attest lands
        // with a physical-device build.
        return try await send("POST", "/v1/devices/register", body: [
            "platform": "ios",
            "model": "iPhone",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "attest_key_id": "dev-\(UUID().uuidString.prefix(12))",
            "attestation": "ZGV2LWF0dGVzdA==",
        ])
    }

    // MARK: points / gamification

    func mePoints() async throws -> MePoints {
        try await send("GET", "/v1/me/points")
    }

    func challenges() async throws -> [ChallengeItem] {
        try await send("GET", "/v1/challenges")
    }

    func league() async throws -> LeagueStanding {
        try await send("GET", "/v1/league")
    }

    func quests() async throws -> [QuestStatus] {
        try await send("GET", "/v1/quests")
    }

    func wheelState() async throws -> WheelState {
        try await send("GET", "/v1/wheel")
    }

    func spinWheel() async throws -> SpinResult {
        try await send("POST", "/v1/wheel/spin", body: Empty())
    }

    func games() async throws -> [GameStatus] {
        try await send("GET", "/v1/games")
    }

    func claimGame(code: String, value: Double? = nil) async throws -> Int {
        struct R: Codable { let claimed: Bool; let points: Int }
        var body: [String: Double] = [:]
        if let value { body["value"] = value }
        let r: R = try await send("POST", "/v1/games/\(code)/claim", body: body)
        return r.points
    }

    func createDuel(targetM: Double = 500) async throws -> DuelState {
        try await send("POST", "/v1/duels", body: ["target_m": targetM])
    }

    func joinDuel(code: String) async throws -> DuelState {
        try await send("POST", "/v1/duels/join", body: ["code": code])
    }

    func currentDuel() async throws -> DuelState {
        try await send("GET", "/v1/duels/current")
    }

    func duel(id: UUID) async throws -> DuelState {
        try await send("GET", "/v1/duels/\(id.uuidString)")
    }

    func cancelDuel(id: UUID) async throws {
        struct R: Codable { let cancelled: Bool }
        let _: R = try await send("POST", "/v1/duels/\(id.uuidString)/cancel", body: Empty())
    }

    // MARK: races

    func races() async throws -> [RaceWindow] {
        struct R: Codable { let windows: [RaceWindow] }
        let r: R = try await send("GET", "/v1/races")
        return r.windows
    }

    // MARK: guilds

    func myGuild() async throws -> GuildState {
        try await send("GET", "/v1/guilds/mine")
    }

    func createGuild(name: String, emblem: String, zaloLink: String?) async throws -> GuildState {
        var body = ["name": name, "emblem": emblem]
        if let zaloLink, !zaloLink.isEmpty { body["zalo_link"] = zaloLink }
        return try await send("POST", "/v1/guilds", body: body)
    }

    func joinGuild(code: String) async throws -> GuildState {
        try await send("POST", "/v1/guilds/join", body: ["code": code])
    }

    func joinGuild(id: UUID) async throws -> GuildState {
        try await send("POST", "/v1/guilds/\(id.uuidString)/join", body: Empty())
    }

    func leaveGuild() async throws {
        struct R: Codable { let left: Bool }
        let _: R = try await send("POST", "/v1/guilds/leave", body: Empty())
    }

    func discoverGuilds() async throws -> [GuildDiscoverRow] {
        struct R: Codable { let guilds: [GuildDiscoverRow] }
        let r: R = try await send("GET", "/v1/guilds/discover")
        return r.guilds
    }

    func updateGuildSettings(emblem: String?, zaloLink: String?) async throws -> GuildState {
        var body: [String: String] = [:]
        if let emblem { body["emblem"] = emblem }
        if let zaloLink { body["zalo_link"] = zaloLink }
        return try await send("PATCH", "/v1/guilds/mine/settings", body: body)
    }

    func updateWeeklyGoal(km: Double) async throws {
        struct R: Codable { let id: UUID }
        let _: R = try await send("PATCH", "/v1/me", body: ["weekly_goal_km": km])
    }

    // MARK: activities

    func createSession(type: String, deviceId: UUID?, duelId: UUID? = nil) async throws -> ActivitySession {
        var body: [String: String] = ["activity_type": type]
        if let deviceId { body["device_id"] = deviceId.uuidString }
        if let duelId { body["duel_id"] = duelId.uuidString }
        return try await send("POST", "/v1/activities", body: body)
    }

    func pushPoints(session: UUID, points: [GpsPointDTO]) async throws {
        struct R: Codable { let accepted: Int }
        let _: R = try await send("POST", "/v1/activities/\(session.uuidString)/points", body: ["points": points])
    }

    func pause(session: UUID) async throws -> ActivitySession {
        try await send("POST", "/v1/activities/\(session.uuidString)/pause", body: Empty())
    }

    func resume(session: UUID) async throws -> ActivitySession {
        try await send("POST", "/v1/activities/\(session.uuidString)/resume", body: Empty())
    }

    func finish(session: UUID) async throws -> ActivitySession {
        try await send("POST", "/v1/activities/\(session.uuidString)/finish", body: Empty())
    }

    func discard(session: UUID) async throws {
        let _: ActivitySession = try await send("POST", "/v1/activities/\(session.uuidString)/discard", body: Empty())
    }

    func sessions(limit: Int = 50) async throws -> [ActivitySession] {
        try await send("GET", "/v1/activities?limit=\(limit)")
    }

    // MARK: rewards

    func rewards() async throws -> [Reward] {
        try await send("GET", "/v1/rewards")
    }

    func redeem(reward: UUID, idempotencyKey: String) async throws -> Redemption {
        try await send("POST", "/v1/rewards/\(reward.uuidString)/redeem", body: ["idempotency_key": idempotencyKey])
    }

    func redemptions() async throws -> [Redemption] {
        try await send("GET", "/v1/redemptions")
    }

    func linkGuardian(memberId: String) async throws {
        struct R: Codable { let linked: Bool }
        let _: R = try await send("POST", "/v1/guardian/link", body: ["member_id": memberId])
    }

    // MARK: plumbing

    private struct Empty: Codable {}
    private struct ErrBody: Codable { let error: String }

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        auth: Bool = true
    ) async throws -> Response {
        try await perform(method: method, path: path, bodyData: nil, auth: auth)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Body,
        auth: Bool = true
    ) async throws -> Response {
        try await perform(method: method, path: path, bodyData: try encoder.encode(body), auth: auth)
    }

    private func perform<Response: Decodable>(
        method: String,
        path: String,
        bodyData: Data?,
        auth: Bool,
        isRetry: Bool = false
    ) async throws -> Response {
        var request = URLRequest(url: URL(string: baseURL.absoluteString + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Access tokens live 15 minutes — a 401 on an authed call is
            // routine. Refresh once (single-flight) and retry; only a dead
            // refresh token ends the session.
            if status == 401, auth, !isRetry {
                if await refresher.refresh(client: self) {
                    return try await perform(
                        method: method, path: path, bodyData: bodyData,
                        auth: auth, isRetry: true
                    )
                }
                // rotateTokens deletes the pair only on a definitive 401;
                // if it survived, this was a network blip — stay logged in.
                if Keychain.get("refresh_token") == nil {
                    NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                }
            }
            let message = (try? decoder.decode(ErrBody.self, from: data))?.error ?? "Lỗi máy chủ (\(status))"
            throw APIError.server(status: status, message: message)
        }
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: token refresh

    private let refresher = RefreshCoordinator()

    /// One refresh at a time: rotation revokes the presented token, so a
    /// second concurrent attempt with the same token would 401 and reads
    /// to the backend as token reuse.
    private actor RefreshCoordinator {
        private var inFlight: Task<Bool, Never>?

        func refresh(client: APIClient) async -> Bool {
            if let inFlight { return await inFlight.value }
            let task = Task { await client.rotateTokens() }
            inFlight = task
            let ok = await task.value
            inFlight = nil
            return ok
        }
    }

    fileprivate func rotateTokens() async -> Bool {
        guard let refreshToken = Keychain.get("refresh_token") else { return false }
        do {
            let pair: TokenPair = try await send(
                "POST", "/v1/auth/refresh",
                body: ["refresh_token": refreshToken], auth: false
            )
            Keychain.set(pair.accessToken, for: "access_token")
            Keychain.set(pair.refreshToken, for: "refresh_token")
            return true
        } catch {
            // Only a definitive rejection kills the session — a network
            // blip must not log the user out mid-run.
            if let apiError = error as? APIError, apiError.status == 401 {
                Keychain.delete("access_token")
                Keychain.delete("refresh_token")
            }
            return false
        }
    }
}
