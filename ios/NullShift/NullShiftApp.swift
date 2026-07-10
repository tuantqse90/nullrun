import SwiftUI

@main
struct NullShiftApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task {
                    #if DEBUG
                    if let phone = ProcessInfo.processInfo.environment["DEV_AUTOLOGIN_PHONE"] {
                        await auth.devAutoLogin(phone: phone)
                    }
                    #endif
                }
        }
    }
}
