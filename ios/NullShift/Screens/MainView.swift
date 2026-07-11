import SwiftUI

/// Root router mirroring the prototype's screen state machine.
struct MainView: View {
    @StateObject private var app = AppModel()
    @StateObject private var tracker = RunTracker()

    var body: some View {
        Group {
            switch app.screen {
            case .home: HomeView()
            case .prerun: PrerunView()
            case .run: RunView()
            case .locked: LockedView()
            case .summary(let session): SummaryView(session: session)
            case .rewards: RewardsView()
            case .voucher(let redemption): VoucherView(redemption: redemption)
            case .wheel: WheelView()
            case .league: LeagueView()
            case .guild: GuildView()
            case .games: GamesView()
            case .duel: DuelView()
            case .scanIntro: ScanIntroView()
            case .scanCam: ScanCamView()
            case .scanProc: ScanProcView()
            case .scanRes: ScanResView()
            case .catchIntro: CatchIntroView()
            case .catchCam: CatchCamView()
            case .catchDex: CritterDexView()
            }
        }
        .overlay { CelebrationHost() }
        .environmentObject(app)
        .environmentObject(tracker)
        .foregroundStyle(app.screen.isDark ? Theme.darkInk : Theme.ink)
        .preferredColorScheme(app.screen.isDark ? .dark : .light)
        .animation(.easeOut(duration: 0.2), value: app.screen)
        .task { await app.bootstrap() }
    }
}
