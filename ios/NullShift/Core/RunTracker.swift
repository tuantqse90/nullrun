import CoreLocation
import CoreMotion
import Foundation

/// Live tracking session: CoreLocation capture → batched upload to the
/// backend ingestion stream. Distance/pace shown live are client-side
/// estimates; the server recomputes authoritative stats at finish.
@MainActor
final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum GPSState { case searching, ready, lost }

    @Published var gpsState: GPSState = .searching
    @Published var activityType = "walk"
    @Published var running = false
    @Published var paused = false
    @Published var seconds = 0
    @Published var distanceKm: Double = 0
    @Published var sessionId: UUID?
    /// Latest fix + accepted track — feeds the live map (NullMap).
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var route: [CLLocationCoordinate2D] = []
    /// Pedometer steps since begin() — device hardware count (0 on simulator).
    @Published var steps = 0
    /// Elapsed seconds at each completed km — REAL per-km splits for the
    /// summary (empty if the run wasn't tracked on this device).
    @Published var kmSplits: [Int] = []
    /// Last milestone (km or 1000-step block) whose flag was shown — lives
    /// here so a lock/unlock round trip doesn't recreate RunView's state and
    /// replay the pill + haptic for the current milestone.
    @Published var lastMilestoneShown = 0

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?
    private var lastFixAt: Date?
    private var cadence: Double?
    private var buffer: [GpsPointDTO] = []
    private var timer: Timer?
    private var uploadTask: Task<Void, Never>?

    /// Live points estimate mirroring backend rules v1 (walk 10 / run 15 per km).
    var livePoints: Int {
        Int(distanceKm * (activityType == "walk" ? 10 : 15))
    }

    var paceSecPerKm: Double? {
        distanceKm > 0.05 ? Double(seconds) / distanceKm : nil
    }

    deinit {
        // The repeating timer is retained by the run loop; without this it
        // would stay scheduled forever if the tracker is torn down mid-run.
        timer?.invalidate()
        manager.stopUpdatingLocation()
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func warmUp() {
        gpsState = .searching
        manager.startUpdatingLocation()
    }

    func begin(session: UUID, type: String) {
        sessionId = session
        activityType = type
        running = true
        paused = false
        seconds = 0
        distanceKm = 0
        steps = 0
        kmSplits.removeAll()
        lastMilestoneShown = 0
        lastLocation = nil
        route.removeAll()
        buffer.removeAll()

        // One pedometer stream feeds both the live step count (UI) and the
        // cadence stamped on every GPS point (anti-cheat signal).
        if CMPedometer.isStepCountingAvailable() || CMPedometer.isCadenceAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                Task { @MainActor in
                    guard let self, let data else { return }
                    self.steps = data.numberOfSteps.intValue
                    self.cadence = data.currentCadence.map { $0.doubleValue * 60 } // steps/min
                }
            }
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard running, !paused else { return }
        seconds += 1
        if let last = lastFixAt, Date().timeIntervalSince(last) > 6 {
            gpsState = .lost
        }
        if seconds % 10 == 0 { flushBuffer() }
    }

    func togglePause() async {
        guard let sessionId else { return }
        if paused {
            _ = try? await APIClient.shared.resume(session: sessionId)
            paused = false
        } else {
            flushBuffer()
            _ = try? await APIClient.shared.pause(session: sessionId)
            paused = true
        }
    }

    /// Uploads the tail, closes the session, returns server-authoritative stats.
    func finish() async throws -> ActivitySession {
        guard let sessionId else { throw APIClient.APIError.server(status: 0, message: "no session") }
        running = false
        timer?.invalidate()
        pedometer.stopUpdates()
        manager.stopUpdatingLocation()
        await flushNow()
        return try await APIClient.shared.finish(session: sessionId)
    }

    func abort() async {
        timer?.invalidate()
        pedometer.stopUpdates()
        manager.stopUpdatingLocation()
        running = false
        if let sessionId {
            try? await APIClient.shared.discard(session: sessionId)
        }
        sessionId = nil
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        guard let sessionId else { return }
        let previous = uploadTask
        uploadTask = Task { @MainActor in
            await previous?.value // keep batches ordered
            do {
                try await APIClient.shared.pushPoints(session: sessionId, points: batch)
            } catch {
                // Upload failed (flaky network) — requeue the batch at the
                // front so these GPS points aren't silently lost; the next
                // flush or finish() retries them. Server dedups on PK.
                buffer.insert(contentsOf: batch, at: 0)
            }
        }
    }

    /// Drains the buffer, retrying failed uploads a few times so a transient
    /// blip at finish doesn't drop the tail of the run.
    private func flushNow() async {
        for _ in 0..<4 {
            flushBuffer()
            await uploadTask?.value
            if buffer.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations {
                self.handle(loc)
            }
        }
    }

    private func handle(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0 else { return }
        lastFixAt = Date()
        if loc.horizontalAccuracy <= 50 {
            currentCoordinate = loc.coordinate
        }
        if gpsState != .ready && loc.horizontalAccuracy <= 25 {
            gpsState = .ready
        } else if gpsState == .lost {
            gpsState = .ready
        }

        guard running, !paused else {
            lastLocation = loc
            return
        }

        // Mirror the server's data-quality gates for the live estimate.
        if let last = lastLocation, loc.horizontalAccuracy <= 50 {
            let dt = loc.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0, dt <= 120 {
                let meters = loc.distance(from: last)
                let speed = meters / dt
                if speed <= 12, speed >= 0.3 {
                    distanceKm += meters / 1000
                    // Record a REAL split each time we cross a whole km.
                    while kmSplits.count < Int(distanceKm) {
                        kmSplits.append(seconds)
                    }
                }
            }
        }
        lastLocation = loc

        // Map polyline: accepted fixes only, thinned to ~3 m steps.
        if loc.horizontalAccuracy <= 50 {
            if let tail = route.last {
                let step = CLLocation(latitude: tail.latitude, longitude: tail.longitude)
                    .distance(from: loc)
                if step > 3 { route.append(loc.coordinate) }
            } else {
                route.append(loc.coordinate)
            }
        }

        buffer.append(GpsPointDTO(
            recordedAt: loc.timestamp,
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            altitudeM: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
            horizontalAccuracyM: loc.horizontalAccuracy,
            speedMps: loc.speed >= 0 ? loc.speed : nil,
            stepCadence: cadence
        ))
        if buffer.count >= 25 { flushBuffer() }
    }
}
