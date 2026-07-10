import CoreLocation
import CoreMotion
import SwiftUI

/// Explains WHY before triggering the system prompts — priming raises
/// "Always" location grant rates, and background location is the product.
struct PermissionPrimingView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var location = LocationPermission()
    @State private var motionGranted = false

    private let motionManager = CMMotionActivityManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Để tính điểm cho bạn")
                .font(.title.bold())
                .padding(.top, 48)

            permissionRow(
                icon: "location.fill",
                title: "Vị trí — chọn “Luôn luôn”",
                detail: "Ghi nhận quãng đường ngay cả khi màn hình tắt. Không có quyền này, hoạt động không được tính điểm.",
                done: location.hasAlways
            )
            permissionRow(
                icon: "figure.run",
                title: "Chuyển động & thể chất",
                detail: "Xác thực bạn thật sự chạy — chống gian lận, bảo vệ giá trị điểm thưởng.",
                done: motionGranted
            )

            Spacer()

            Button(action: next) {
                Text(buttonTitle)
                    .font(.viet(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.green)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressScale())
        }
        .padding(24)
        .background(Theme.bg)
        .foregroundStyle(Theme.ink)
    }

    private var buttonTitle: String {
        if !location.hasAlways { return "Cho phép vị trí" }
        if !motionGranted { return "Cho phép chuyển động" }
        return "Bắt đầu"
    }

    private func next() {
        if !location.hasAlways {
            location.request()
        } else if !motionGranted {
            requestMotion()
        } else {
            auth.permissionsCompleted()
        }
    }

    private func requestMotion() {
        // Querying activity triggers the system permission prompt.
        let now = Date()
        motionManager.queryActivityStarting(from: now, to: now, to: .main) { _, error in
            motionGranted = error == nil
        }
    }

    @ViewBuilder
    private func permissionRow(icon: String, title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.title2)
                .foregroundStyle(done ? Theme.green : Theme.greenDeep)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.viet(16, .bold))
                Text(detail).font(.viet(14)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Two-step ask: When-In-Use first, then Always — Apple only shows the
/// "Change to Always" upgrade prompt after When-In-Use is granted.
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var hasAlways = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        hasAlways = manager.authorizationStatus == .authorizedAlways
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        hasAlways = manager.authorizationStatus == .authorizedAlways
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }
}
