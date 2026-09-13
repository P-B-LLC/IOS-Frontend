import CoreLocation
import Foundation

/// One recorded GPS fix, ready to be sent to the API.
nonisolated struct RoutePoint: Identifiable, Hashable, Codable, Sendable {
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
