//
//  RouteTracker.swift
//  IOS Frontend
//
//  Records the GPS track for an active cardio session. Distance and pace are
//  not derived here: the raw fixes are uploaded and the backend computes them.
//

import CoreLocation
import Foundation
import Observation

/// One recorded GPS fix, ready to be sent to the API.
nonisolated struct RoutePoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let recordedAt: Date

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        recordedAt: Date
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.recordedAt = recordedAt
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
    private(set) var isTracking = false
    private(set) var points: [RoutePoint] = []
    /// Set when a fix cannot be obtained, so the session UI can say so.
    private(set) var trackingError: String?

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
    }

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
        manager.startUpdatingLocation()
    }

    /// Stops recording and returns the track captured so far.
    @discardableResult
    func stopTracking() -> [RoutePoint] {
        guard isTracking else { return points }
        manager.stopUpdatingLocation()
        if Self.declaresLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = false
        }
        isTracking = false
        return points
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
            // Drop obviously bad fixes; a negative accuracy means invalid.
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 100 else {
                continue
            }
            points.append(
                RoutePoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    recordedAt: location.timestamp
                )
            )
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
