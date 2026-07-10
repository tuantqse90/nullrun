import SwiftUI

/// Post-run summary: confetti, count-up points, verified badge, splits.
/// Numbers here are SERVER-computed — what the backend says is what counts.
struct SummaryView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var tracker: RunTracker
    let session: ActivitySession

    private var earned: Int { (session.pointsEarned ?? 0) + (session.challengeBonus ?? 0) }
    private var km: Double { session.distanceM / 1000 }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 6).padding(.bottom, 12)
            routeCard
            pointsCard.padding(.top, 12)
            statRow.padding(.top, 12)
            if !splits.isEmpty { splitsCard.padding(.top, 12) }
            Spacer()
            PrimaryButton(title: "Nhận \(earned) điểm", glow: true) {
                Task {
                    await app.refresh()
                    app.screen = .home
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(Theme.bg)
        .overlay(alignment: .top) { ConfettiBurst().frame(height: 200).padding(.top, 4) }
        .onAppear { if earned > 0 { Haptics.success() } }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(session.activityType == "walk" ? "Đi bộ xong!" : "Chạy xong!")
                    .font(.viet(23, .bold))
                Text(dateLine).font(.viet(14)).foregroundStyle(Theme.muted)
            }
            Spacer()
            ZStack {
                Circle().fill(Theme.purpleBg)
                Mascot(mood: .cheering).frame(width: 46, height: 40).offset(y: 6)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        }
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE, d MMM · HH:mm"
        return f.string(from: session.startedAt).capitalized(with: Locale(identifier: "vi_VN"))
    }

    private var routeCard: some View {
        ZStack {
            // Real route on the real map; the doodle only remains as the
            // fallback when no track exists (e.g. design-QA jumps).
            if tracker.route.count >= 2 {
                NullMap(route: tracker.route, fitToRoute: true)
            } else {
                MapDoodle()
                RouteLine()
                    .stroke(Theme.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .padding(24)
            }
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.orangeDeep)
                        .padding(.top, 10).padding(.trailing, 14)
                }
                Spacer()
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var pointsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Điểm buổi này").font(.viet(14)).foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(target: earned)
                    Text("điểm").font(.viet(15, .semibold)).foregroundStyle(Theme.green)
                }
            }
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 14))
                Text(verifiedLabel).font(.viet(13, .bold))
            }
            .foregroundStyle(Theme.greenDeep)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.greenBgSoft)
            .clipShape(Capsule())
        }
        .card(radius: 22, padding: EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22))
        .shineSweep(tint: Theme.green, opacity: 0.16)
        .popIn(delay: 0.15)
    }

    private var verifiedLabel: String {
        session.verdict == "clean" ? "Đã xác minh trên máy" : "Đang chờ xác minh"
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            summaryStat("Quãng đường", "\(Fmt.dist(km)) km")
            summaryStat("Thời gian", Fmt.time(Int(session.durationS)))
            // Steps are pedometer-local to this device (the server only
            // sees cadence); walks lead with them, runs keep pace.
            if session.activityType == "walk", tracker.steps > 0 {
                summaryStat("Bước chân", Fmt.int(tracker.steps))
            } else {
                summaryStat("Nhịp độ TB", Fmt.pace(session.avgPaceSPerKm))
            }
        }
    }

    private func summaryStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.viet(12.5)).foregroundStyle(Theme.muted)
            Text(value).font(.mono(19)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18, padding: EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
    }

    // REAL per-km splits from the tracker's recorded km marks — no
    // fabricated data. Empty when the run wasn't tracked on this device
    // (e.g. design QA), in which case the card is hidden.
    private var splits: [(km: Int, frac: Double, pace: String)] {
        let marks = tracker.kmSplits
        guard marks.count >= 1 else { return [] }
        var paces: [Double] = []
        for i in marks.indices {
            let prev = i == 0 ? 0 : marks[i - 1]
            paces.append(Double(marks[i] - prev)) // seconds for this km
        }
        let slowest = max(paces.max() ?? 1, 1)
        return paces.prefix(6).enumerated().map { i, p in
            (i + 1, max(0.15, p / slowest), Fmt.pace(p))
        }
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Từng km").font(.viet(14, .semibold))
            VStack(spacing: 7) {
                ForEach(splits, id: \.km) { sp in
                    HStack(spacing: 10) {
                        Text("\(sp.km)").font(.mono(13, .regular)).foregroundStyle(Theme.muted).frame(width: 18)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(Theme.green).frame(width: geo.size.width * sp.frac)
                            }
                        }
                        .frame(height: 12)
                        Text(sp.pace).font(.mono(13, .regular))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

}

struct RouteLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: rect.minX, y: rect.maxY * 0.9))
        p.addCurve(
            to: .init(x: rect.midX, y: rect.minY + rect.height * 0.25),
            control1: .init(x: rect.width * 0.2, y: rect.maxY * 0.75),
            control2: .init(x: rect.width * 0.3, y: rect.minY + rect.height * 0.2)
        )
        p.addCurve(
            to: .init(x: rect.maxX, y: rect.height * 0.55),
            control1: .init(x: rect.width * 0.7, y: rect.height * 0.3),
            control2: .init(x: rect.width * 0.8, y: rect.height * 0.65)
        )
        return p
    }
}
