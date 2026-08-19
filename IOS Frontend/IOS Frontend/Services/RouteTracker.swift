//
//  RouteTracker.swift
//  IOS Frontend
//
//  Records the GPS track for an active cardio session. Distance and pace are
//  not derived here: the raw fixes are uploaded and the backend computes them.
//

import CoreLocation
import CoreMotion
import Foundation
import Observation

/// One recorded GPS fix, ready to be sent to the API.
nonisolated struct RoutePoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let recordedAt: Date
    /// The device's own speed reading in meters per second, taken from the
    /// GPS Doppler shift rather than derived from consecutive positions, so it
    /// carries no accumulated positional error. Nil when unavailable.
    let speedMetersPerSecond: Double?
    /// Height above sea level in meters, when the device had a vertical fix.
    let altitudeMeters: Double?

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        recordedAt: Date,
        speedMetersPerSecond: Double? = nil,
        altitudeMeters: Double? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.recordedAt = recordedAt
        self.speedMetersPerSecond = speedMetersPerSecond
        self.altitudeMeters = altitudeMeters
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Collects location fixes while a cardio session is running.
///
/// Authorization is requested when the user starts a session rather than at
/// launch, so the system prompt appears with the reason visible on screen.
@Observable
final class RouteTracker: NSObject, CLLocationManagerDelegate {
    /// What the app is allowed to do right now, in terms the UI can act on.
    enum Permission: Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized

        var allowsTracking: Bool { self == .authorized }
    }

    private(set) var permission: Permission = .notDetermined
    /// Whether iOS is giving real positions rather than a coarse area.
    ///
    /// With Precise Location switched off, CoreLocation answers with a fix
    /// good to a few kilometres. That is not a slightly worse route, it is no
    /// route: every fix fails the accuracy filter below, the track comes back
    /// empty, and the session reports having recorded nothing without ever
    /// saying why. Worth asking about before a run rather than after it.
    private(set) var hasPreciseLocation = true
    private(set) var isTracking = false
    private(set) var points: [RoutePoint] = []
    /// Set when a fix cannot be obtained, so the session UI can say so.
    private(set) var trackingError: String?
    /// Latest speed reading, shown live during a session. Display only — every
    /// saved figure is computed by the backend from the uploaded track.
    private(set) var currentSpeedMetersPerSecond: Double?

    // MARK: - Live estimates
    //
    // These exist so the user can watch their run unfold. They are running
    // estimates for display only: when the session ends, the uploaded track is
    // measured by the backend and those figures are what get recorded.

    /// Distance covered so far, accumulated fix by fix.
    private(set) var liveDistanceMeters: Double = 0
    /// Height climbed so far, ignoring drift smaller than a meter.
    private(set) var liveElevationGainMeters: Double = 0
    /// The last accepted fix, used to measure each new step.
    private var lastLocation: CLLocation?
    /// Altitude the current climb is measured from.
    private var elevationReference: Double?

    // MARK: - Barometric elevation
    //
    // GPS is poor at height, often several meters out, which is enough to
    // invent hills. The barometer measures *change* in height to roughly a
    // third of a meter, and change is exactly what climb is. A single GPS
    // reading anchors it to sea level; every movement after that comes from
    // the barometer.

    private let altimeter = CMAltimeter()
    private var isReadingBarometer = false
    /// Meters gained or lost since the barometer started, per CoreMotion.
    private var relativeAltitudeMeters: Double?
    /// The GPS altitude the barometric series is anchored to.
    private var altitudeAnchorMeters: Double?

    /// Whether height is coming from the barometer rather than GPS.
    private(set) var usesBarometricAltitude = false

    var liveDistanceKilometers: Double { liveDistanceMeters / 1000 }

    /// Pace averaged over the whole run so far, which is steadier to read than
    /// the instantaneous value and matches what the backend will report.
    var liveAveragePaceSecondsPerKilometer: Double? {
        guard liveDistanceMeters > 20,
              let first = points.first?.recordedAt,
              let last = points.last?.recordedAt else {
            return nil
        }
        let elapsed = last.timeIntervalSince(first)
        guard elapsed > 0 else { return nil }
        return elapsed / (liveDistanceMeters / 1000)
    }

    var liveAverageSpeedKilometersPerHour: Double? {
        guard let pace = liveAveragePaceSecondsPerKilometer, pace > 0 else {
            return nil
        }
        return 3600 / pace
    }

    /// Current speed in km/h, the natural unit for a ride.
    var currentSpeedKilometersPerHour: Double? {
        currentSpeedMetersPerSecond.map { $0 * 3.6 }
    }

    /// Current pace in seconds per km, the natural unit for a run or swim.
    /// Nil below a slow walk, where pace becomes meaningless.
    var currentPaceSecondsPerKilometer: Double? {
        guard let speed = currentSpeedMetersPerSecond, speed > 0.5 else {
            return nil
        }
        return 1000 / speed
    }

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        // Report every fix; the server decides what the track means.
        manager.distanceFilter = kCLDistanceFilterNone
        permission = Self.permission(for: manager.authorizationStatus)
        hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
    }

    /// Matches the key in `NSLocationTemporaryUsageDescriptionDictionary`.
    /// iOS refuses the request outright if the two disagree.
    private static let temporaryAccuracyPurposeKey = "RouteTracking"

    var hasRoute: Bool { points.count >= 2 }

    /// Asks for permission if it has never been requested. Returns immediately;
    /// the delegate callback updates `permission`.
    func requestPermission() {
        guard manager.authorizationStatus == .notDetermined else {
            permission = Self.permission(for: manager.authorizationStatus)
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    /// Begins recording. Does nothing unless location access is authorized.
    func startTracking() {
        guard permission.allowsTracking, !isTracking else { return }
        points = []
        trackingError = nil
        currentSpeedMetersPerSecond = nil
        liveDistanceMeters = 0
        liveElevationGainMeters = 0
        lastLocation = nil
        elevationReference = nil
        isTracking = true

        // Keeps fixes coming with the screen locked or the app backgrounded,
        // which is the normal case for a run or ride. iOS shows its own
        // indicator while this is on, and it is switched off when the session
        // ends so the app never tracks outside a session.
        //
        // CoreLocation raises an exception if this is set without the location
        // background mode declared, so it is gated on the bundle actually
        // declaring it rather than assumed.
        if Self.declaresLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.pausesLocationUpdatesAutomatically = false
        requestPreciseLocationIfNeeded()
        manager.startUpdatingLocation()
        startReadingBarometer()
    }

    /// Asks for one session's worth of precise location when the user has the
    /// setting off.
    ///
    /// Temporary rather than permanent: the app wants exact positions while a
    /// run is being recorded and has no use for them otherwise, and this is
    /// the request iOS provides for saying exactly that. It is asked at the
    /// start of a session, where the reason is on screen, and iOS will only
    /// show it once per session so it cannot become nagging.
    private func requestPreciseLocationIfNeeded() {
        guard manager.accuracyAuthorization == .reducedAccuracy else {
            hasPreciseLocation = true
            return
        }

        manager.requestTemporaryFullAccuracyAuthorization(
            withPurposeKey: Self.temporaryAccuracyPurposeKey
        ) { [weak self] _ in
            guard let self else { return }
            hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
            guard hasPreciseLocation == false else { return }
            // Said plainly, because the alternative is a session that records
            // nothing and never explains itself.
            trackingError = """
                Precise Location is off, so this route cannot be mapped. \
                Turn it on in Settings, Privacy & Security, Location Services, \
                Repbase.
                """
        }
    }

    /// Stops recording and returns the track captured so far.
    @discardableResult
    func stopTracking() -> [RoutePoint] {
        guard isTracking else { return points }
        manager.stopUpdatingLocation()
        if Self.declaresLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = false
        }
        stopReadingBarometer()
        isTracking = false
        return points
    }

    /// Only sustained height changes count as climbing. Matches the backend's
    /// threshold, which keeps the live figure close to the one recorded.
    private static let elevationNoiseMeters: Double = 3

    /// Fixes less certain than this are discarded. Roughly a running track's
    /// width: loose enough to keep tracking under trees, tight enough that
    /// drift is not mistaken for distance covered.
    private static let maximumAccuracyMeters: Double = 25

    /// CoreLocation replays its last known fix when updates begin; anything
    /// this old describes where the user was, not where they are.
    private static let maximumFixAgeSeconds: TimeInterval = 10

    /// Beyond any human-powered speed, including a fast descent on a bike, so
    /// a step above it is a bad fix rather than movement. Meters per second.
    private static let maximumPlausibleSpeed: Double = 30

    /// Below a slow walk the device is drifting, not travelling. Matches the
    /// floor the backend uses for moving time. Meters per second.
    private static let movingSpeedFloor: Double = 0.5

    // MARK: - Barometer

    private func startReadingBarometer() {
        guard CMAltimeter.isRelativeAltitudeAvailable(),
              CMAltimeter.authorizationStatus() != .denied,
              CMAltimeter.authorizationStatus() != .restricted,
              !isReadingBarometer else {
            return
        }
        isReadingBarometer = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            relativeAltitudeMeters = data.relativeAltitude.doubleValue
            usesBarometricAltitude = true
        }
    }

    private func stopReadingBarometer() {
        guard isReadingBarometer else { return }
        altimeter.stopRelativeAltitudeUpdates()
        isReadingBarometer = false
    }

    /// Height for a fix. Once the barometer is running its change is added to
    /// the GPS altitude it was anchored to, which keeps the absolute reference
    /// while taking every rise and fall from the far more precise sensor.
    private func altitude(for location: CLLocation) -> Double? {
        let gpsAltitude = location.verticalAccuracy >= 0 ? location.altitude : nil

        guard let relative = relativeAltitudeMeters else {
            return gpsAltitude
        }
        if altitudeAnchorMeters == nil, let gpsAltitude {
            // Anchor to the first usable GPS height, then never move it.
            altitudeAnchorMeters = gpsAltitude - relative
        }
        guard let anchor = altitudeAnchorMeters else { return gpsAltitude }
        return anchor + relative
    }

    /// Whether the app bundle declares the location background mode. Without
    /// it, background updates cannot be requested.
    static let declaresLocationBackgroundMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }()

    func reset() {
        stopTracking()
        points = []
        trackingError = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permission = Self.permission(for: manager.authorizationStatus)
        // This fires for a change of precision as well as of permission, so it
        // is the one place that learns the user turned Precise Location off
        // part way through a run.
        hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        if !permission.allowsTracking, isTracking {
            stopTracking()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard isTracking else { return }
        trackingError = nil

        for location in locations {
            // A negative accuracy means the fix is invalid. The limit is tight
            // because a loose one lets the position wander, and every wander
            // is counted as distance the user never covered.
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= Self.maximumAccuracyMeters else {
                continue
            }

            // Ignore stale fixes replayed by CoreLocation on start-up.
            guard location.timestamp.timeIntervalSinceNow > -Self.maximumFixAgeSeconds else {
                continue
            }

            // A jump no human could make is a bad fix, not a sprint.
            if let previous = lastLocation {
                let step = location.distance(from: previous)
                let gap = location.timestamp.timeIntervalSince(previous.timestamp)
                if gap > 0, step / gap > Self.maximumPlausibleSpeed {
                    continue
                }
            }
            // A negative accuracy means the device could not measure that
            // component of the fix.
            let speed = location.speed >= 0 ? location.speed : nil
            let altitude = altitude(for: location)

            points.append(
                RoutePoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    recordedAt: location.timestamp,
                    speedMetersPerSecond: speed,
                    altitudeMeters: altitude
                )
            )
            if let speed { currentSpeedMetersPerSecond = speed }

            // Accumulate the live figures. CLLocation measures the step
            // geodesically, so this matches the server's own distance closely.
            //
            // Distance only grows while the device reports actual movement.
            // Standing still, the position keeps drifting a few meters between
            // fixes, and counting that would add hundreds of meters to a run
            // that paused at a crossing. The Doppler speed reading is the
            // reliable way to tell moving from drifting.
            if let previous = lastLocation {
                let isMoving = speed.map { $0 >= Self.movingSpeedFloor } ?? true
                if isMoving {
                    liveDistanceMeters += location.distance(from: previous)
                }
            }
            lastLocation = location

            if let altitude {
                if let reference = elevationReference {
                    let change = altitude - reference
                    if change >= Self.elevationNoiseMeters {
                        liveElevationGainMeters += change
                        elevationReference = altitude
                    } else if change <= -Self.elevationNoiseMeters {
                        elevationReference = altitude
                    }
                } else {
                    elevationReference = altitude
                }
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        guard isTracking else { return }
        if let clError = error as? CLError, clError.code == .locationUnknown {
            // Transient: the device has not got a fix yet. Keep waiting.
            return
        }
        trackingError = error.localizedDescription
    }

    private static func permission(
        for status: CLAuthorizationStatus
    ) -> Permission {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .denied
        }
    }
}
