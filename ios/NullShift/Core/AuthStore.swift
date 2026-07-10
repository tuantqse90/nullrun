import Foundation

/// Session state for the app. Tokens live in the Keychain.
@MainActor
final class AuthStore: ObservableObject {
    enum SessionState {
        case loggedOut
        case needsPermissions
        case ready
    }

    @Published var state: SessionState = .loggedOut

    private let permissionsDoneKey = "onboarding.permissions.done"

    /// Everything bound to this user+server pair. Keychain AND UserDefaults
    /// survive app reinstall, so any of it can be stale against a new
    /// backend — a forced logout must wipe exactly what logout() wipes.
    /// body.measures stays: on-device by design, never tied to a server.
    private func wipeLocalSession() {
        Keychain.delete("access_token")
        Keychain.delete("refresh_token")
        let d = UserDefaults.standard
        d.removeObject(forKey: permissionsDoneKey)
        d.removeObject(forKey: "device.id")
        d.removeObject(forKey: "guardian.linked")
        // Celebration baselines are per-user — a new login starts clean.
        for key in ["seen.tier", "seen.level", "seen.streak", "seen.baseline"] {
            d.removeObject(forKey: key)
        }
    }

    /// Tokens can outlive their server (Keychain survives reinstall, or the
    /// backend moved) — when refresh definitively fails, drop to login.
    private func observeSessionExpiry() {
        NotificationCenter.default.addObserver(
            forName: .authSessionExpired, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state != .loggedOut else { return }
                self.wipeLocalSession()
                self.state = .loggedOut
            }
        }
    }

    init() {
        observeSessionExpiry()
        #if DEBUG
        // UI-test hook: start from a clean logged-out state.
        if ProcessInfo.processInfo.environment["DEV_FORCE_LOGOUT"] != nil {
            Keychain.delete("access_token")
            Keychain.delete("refresh_token")
            UserDefaults.standard.removeObject(forKey: permissionsDoneKey)
            return
        }
        #endif
        if Keychain.get("refresh_token") != nil {
            state = UserDefaults.standard.bool(forKey: permissionsDoneKey)
                ? .ready
                : .needsPermissions
        }
    }

    func requestOTP(phone: String) async throws {
        try await APIClient.shared.requestOTP(phone: phone)
    }

    func verifyOTP(phone: String, code: String) async throws {
        let pair = try await APIClient.shared.verifyOTP(phone: phone, code: code)
        Keychain.set(pair.accessToken, for: "access_token")
        Keychain.set(pair.refreshToken, for: "refresh_token")
        state = .needsPermissions
    }

    func permissionsCompleted() {
        UserDefaults.standard.set(true, forKey: permissionsDoneKey)
        state = .ready
    }

    #if DEBUG
    /// Simulator/dev shortcut: sms_mode=log echoes the OTP, so the whole
    /// login can run unattended. Triggered by DEV_AUTOLOGIN_PHONE env.
    /// Always starts a fresh session so UI tests control which user runs.
    func devAutoLogin(phone: String) async {
        await logout()
        guard let code = try? await APIClient.shared.requestOTP(phone: phone) ?? nil else { return }
        try? await verifyOTP(phone: phone, code: code)
        if state == .needsPermissions { permissionsCompleted() }
    }
    #endif

    func logout() async {
        if let refreshToken = Keychain.get("refresh_token") {
            try? await APIClient.shared.logout(refreshToken: refreshToken)
        }
        wipeLocalSession()
        state = .loggedOut
    }
}
