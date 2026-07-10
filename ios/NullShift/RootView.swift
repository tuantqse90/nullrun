import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var showSplash = true

    var body: some View {
        ZStack {
            switch auth.state {
            case .loggedOut:
                LoginView()
            case .needsPermissions:
                PermissionPrimingView()
            case .ready:
                MainView()
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Auth screens are light-only by design; once inside, MainView
        // manages dark mode per screen (run/locked/scan cam).
        .preferredColorScheme(auth.state == .ready ? nil : .light)
        // The design is scheme-independent: every unstyled Text falls back to
        // ink (not system .primary, which turns white in dark mode).
        .foregroundStyle(Theme.ink)
        .tint(Theme.green)
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
        }
    }
}
