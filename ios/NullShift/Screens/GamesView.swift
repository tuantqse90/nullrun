import CoreMotion
import SwiftUI

/// Wellness games — every definition, reward, and completion state comes
/// from the server. The phone only supplies pedometer steps for the
/// sensor-verified games.
struct GamesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var todaySteps: Double = 0
    @State private var claiming: String?
    @State private var error: String?

    private let pedometer = CMPedometer()

    private var tiers: [(key: String, label: String, color: Color)] {
        [
            ("easy", "Dễ — thói quen mỗi ngày", Theme.green),
            ("medium", "Vừa — nỗ lực thật", Theme.orangeDeep),
            ("hard", "Khó — thành tựu lớn", Theme.purpleDeep),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Games").font(.viet(23, .bold))
                    Text("Hoàn thành để nhận điểm — tự xác minh khi có thể")
                        .font(.viet(13.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    app.screen = .home
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 40, height: 40)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
                }
            }
            .padding(.horizontal, 20).padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error {
                        Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
                    }
                    ForEach(tiers, id: \.key) { tier in
                        let items = app.games.filter { $0.tier == tier.key }
                        if !items.isEmpty {
                            Text(tier.label)
                                .font(.viet(14, .bold)).foregroundStyle(tier.color)
                                .padding(.top, 6)
                            ForEach(items) { game in
                                gameCard(game)
                            }
                        }
                    }
                    Text("Nhiệm vụ tự khai dựa trên tinh thần trung thực — tối đa 3 lượt/ngày.")
                        .font(.viet(12.5)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                }
                .padding(.horizontal, 20).padding(.top, 10)
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) { toast.padding(.bottom, 30) }
        .task {
            await app.refresh()
            readSteps()
        }
    }

    private func gameCard(_ game: GameStatus) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(game.title).font(.viet(15, .bold))
                    if game.cadence == "once" {
                        Text("cột mốc").font(.viet(10.5, .semibold))
                            .foregroundStyle(Theme.purpleDeep)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.purpleBg)
                            .clipShape(Capsule())
                    }
                }
                Text(game.description).font(.viet(12.5)).foregroundStyle(Theme.muted)
                if let progressLabel {
                    if let label = progressLabel(game) {
                        Text(label).font(.mono(12, .regular)).foregroundStyle(Theme.greenDeep)
                    }
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Text("+\(game.rewardPoints)").font(.mono(15)).foregroundStyle(Theme.greenDeep)
                claimButton(game)
            }
        }
        .card()
        .opacity(game.completed ? 0.62 : 1)
    }

    // Progress line for verifiable games (server data / device steps).
    private var progressLabel: ((GameStatus) -> String?)? {
        { game in
            switch game.verification {
            case "auto_distance", "auto_duration", "auto_streak":
                guard let p = game.progress else { return nil }
                return "\(Int(p))/\(Int(game.targetValue)) \(game.unit)"
            case "sensor_steps":
                return "\(Int(todaySteps))/\(Int(game.targetValue)) bước (hôm nay)"
            default:
                return nil
            }
        }
    }

    @ViewBuilder
    private func claimButton(_ game: GameStatus) -> some View {
        if game.completed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                Text("Xong").font(.viet(12.5, .bold))
            }
            .foregroundStyle(Theme.greenDeep)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.greenBgSoft)
            .clipShape(Capsule())
        } else {
            let enabled = isClaimable(game)
            Button {
                Task { await claim(game) }
            } label: {
                Text(claiming == game.code ? "…" : "Nhận")
                    .font(.viet(12.5, .bold))
                    .foregroundStyle(enabled ? .white : Theme.muted)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(enabled ? Theme.green : Theme.track)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressScale())
            .disabled(!enabled || claiming != nil)
        }
    }

    private func isClaimable(_ game: GameStatus) -> Bool {
        switch game.verification {
        case "sensor_steps": todaySteps >= game.targetValue
        default: game.claimable
        }
    }

    private func claim(_ game: GameStatus) async {
        claiming = game.code
        error = nil
        do {
            let value = game.verification == "sensor_steps" ? todaySteps : nil
            let points = try await APIClient.shared.claimGame(code: game.code, value: value)
            app.showToast("+\(points) điểm — \(game.title)")
            await app.refresh()
        } catch {
            self.error = error.localizedDescription
        }
        claiming = nil
    }

    private func readSteps() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())
        pedometer.queryPedometerData(from: start, to: Date()) { data, _ in
            Task { @MainActor in
                todaySteps = data?.numberOfSteps.doubleValue ?? 0
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let toast = app.toast {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.greenBright)
                Text(toast).font(.viet(13)).foregroundStyle(Theme.darkInk)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
