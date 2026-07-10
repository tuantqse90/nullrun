import SwiftUI

/// GPS warm-up screen: stylized map, ripple marker, walk/run toggle.
struct PrerunView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var tracker: RunTracker
    @State private var starting = false
    @State private var error: String?

    private var ready: Bool { tracker.gpsState == .ready }

    var body: some View {
        VStack(spacing: 0) {
            mapPanel
                .padding(.horizontal, 20)
                .padding(.top, 8)
            VStack(spacing: 14) {
                typeToggle
                if ready {
                    PrimaryButton(title: tracker.activityType == "walk" ? "Bắt đầu đi bộ" : "Bắt đầu chạy", height: 64, glow: true) {
                        Task { await begin() }
                    }
                    .disabled(starting)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Chờ tín hiệu…").font(.viet(19, .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color(hex: 0xA8C4B4))
                    .clipShape(Capsule())
                }
                HStack(spacing: 10) {
                    Mascot(mood: .running).frame(width: 46, height: 38)
                    Text(ready ? "Điểm được tích từ mét đầu tiên." : "Ra chỗ thoáng để bắt GPS nhanh hơn.")
                        .font(.viet(13)).foregroundStyle(Theme.faint)
                    Spacer(minLength: 0)
                }
                if let error {
                    Text(error).font(.viet(13)).foregroundStyle(Theme.danger)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 46, trailing: 20))
        }
        .background(Theme.bg)
        .onAppear { tracker.warmUp() }
    }

    private func begin() async {
        starting = true
        error = nil
        do {
            try await createAndStart(deviceId: app.deviceId)
        } catch let apiError as APIClient.APIError where apiError.status == 400 {
            // Self-heal the two stranded-state 400s, then retry once:
            // a device registration the server doesn't know (UserDefaults
            // survives reinstall/server switch) and an open session left
            // behind by a killed app.
            NSLog("[heal] create 400: %@", apiError.localizedDescription)
            do {
                if apiError.localizedDescription.contains("unknown device_id") {
                    let fresh = await app.reregisterDevice()
                    NSLog("[heal] reregistered device: %@", fresh?.uuidString ?? "nil")
                    try await createAndStart(deviceId: fresh)
                } else if apiError.localizedDescription.contains("open session") {
                    try await discardOpenSession()
                    NSLog("[heal] discarded open session, retrying")
                    try await createAndStart(deviceId: app.deviceId)
                } else {
                    throw apiError
                }
            } catch {
                NSLog("[heal] retry failed: %@", error.localizedDescription)
                self.error = error.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
        starting = false
    }

    private func createAndStart(deviceId: UUID?) async throws {
        let session = try await APIClient.shared.createSession(
            type: tracker.activityType,
            deviceId: deviceId,
            duelId: app.pendingDuelId
        )
        app.pendingDuelId = nil
        tracker.begin(session: session.id, type: tracker.activityType)
        app.screen = .run
    }

    private func discardOpenSession() async throws {
        let open = try await APIClient.shared.sessions(limit: 10)
            .first { $0.status == "active" || $0.status == "paused" }
        if let open {
            try await APIClient.shared.discard(session: open.id)
        }
    }

    private var mapPanel: some View {
        ZStack {
            // Real basemap (NullMaps) following the live fix; the doodle
            // stays underneath as the offline/loading backdrop.
            MapDoodle()
            NullMap(center: tracker.currentCoordinate)
            gpsMarker
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(ready ? Theme.green : Theme.orange).frame(width: 9, height: 9)
                        Text(ready ? "GPS tốt · ±5 m" : "Đang tìm GPS… vài giây")
                            .font(.viet(13.5, .semibold))
                            .foregroundStyle(ready ? Theme.greenDeep : Theme.orangeDeep)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .background(.white.opacity(0.95))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    Spacer()
                    Button {
                        Task { await tracker.abort() }
                        app.screen = .home
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.95))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    }
                }
                .padding(14)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var gpsMarker: some View {
        ZStack {
            RippleRing(color: ready ? Theme.green : Theme.orange, delay: 0)
            RippleRing(color: ready ? Theme.green : Theme.orange, delay: 0.9)
            Circle()
                .fill((ready ? Theme.green : Theme.orange).opacity(0.18))
                .frame(width: 76, height: 76)
            Circle()
                .fill(ready ? Theme.green : Theme.orange)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
        .animation(.easeInOut(duration: 0.5), value: ready)
    }

    private var typeToggle: some View {
        HStack(spacing: 0) {
            typeOption("walk", label: "Đi bộ", icon: "figure.walk")
            typeOption("run", label: "Chạy bộ", icon: "figure.run")
        }
        .padding(6)
        .background(.white)
        .clipShape(Capsule())
        .shadow(color: Theme.cardShadow, radius: 5, y: 2)
    }

    private func typeOption(_ value: String, label: String, icon: String) -> some View {
        let selected = tracker.activityType == value
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(label).font(.viet(15, selected ? .bold : .regular))
        }
        .foregroundStyle(selected ? Theme.greenDeep : Theme.muted)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(selected ? Theme.greenBgSoft : .clear)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { tracker.activityType = value } }
    }
}

struct RippleRing: View {
    let color: Color
    let delay: Double
    @State private var expand = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: 76, height: 76)
            .scaleEffect(expand ? 2 : 0.55)
            .opacity(expand ? 0 : 0.75)
            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(delay), value: expand)
            .onAppear { expand = true }
    }
}

/// The prototype's flat-map doodle: roads, blocks, dashed route + pin.
struct MapDoodle: View {
    var body: some View {
        ZStack {
            Theme.mapBg
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: .init(x: 0, y: h * 0.24)); p.addLine(to: .init(x: w, y: h * 0.18))
                    p.move(to: .init(x: 0, y: h * 0.52)); p.addLine(to: .init(x: w, y: h * 0.46))
                    p.move(to: .init(x: 0, y: h * 0.80)); p.addLine(to: .init(x: w, y: h * 0.76))
                    p.move(to: .init(x: w * 0.25, y: 0)); p.addLine(to: .init(x: w * 0.33, y: h))
                    p.move(to: .init(x: w * 0.69, y: 0)); p.addLine(to: .init(x: w * 0.75, y: h))
                }
                .stroke(Theme.mapRoad, lineWidth: 11)
                Rectangle().fill(Theme.mapBlock).frame(width: w * 0.29, height: h * 0.22)
                    .position(x: w * 0.51, y: h * 0.32)
                Rectangle().fill(Theme.mapBlock).frame(width: w * 0.17, height: h * 0.18)
                    .position(x: w * 0.14, y: h * 0.65)
                Rectangle().fill(Theme.mapBlock).frame(width: w * 0.15, height: h * 0.23)
                    .position(x: w * 0.87, y: h * 0.61)
            }
        }
    }
}
