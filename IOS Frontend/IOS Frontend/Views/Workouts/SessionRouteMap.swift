//
//  SessionRouteMap.swift
//  IOS Frontend
//
//  The track a finished run, ride or swim covered, drawn on a map.
//

import CoreLocation
import MapKit
import SwiftUI

/// A finished session's route, framed to fit and not interactive.
///
/// Deliberately inert. A `Map` inside a `ScrollView` takes the drag for itself,
/// so a live one here would swallow every attempt to scroll past it; this is a
/// picture of where the user went, and pictures do not need panning.
struct SessionRouteMap: View {
    let points: [RoutePoint]
    let accent: Color

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            MapPolyline(coordinates: points.map(\.coordinate))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )

            if let start = points.first {
                Annotation("Start", coordinate: start.coordinate) {
                    endpointMarker(fill: .white)
                }
                .annotationTitles(.hidden)
            }

            // Only when the finish is somewhere else. A loop ends where it
            // began, and two markers stacked on one spot read as a mistake.
            if let end = points.last, isLoop == false {
                Annotation("Finish", coordinate: end.coordinate) {
                    endpointMarker(fill: accent)
                }
                .annotationTitles(.hidden)
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityLabel("Map of the route taken")
    }

    private func endpointMarker(fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 13, height: 13)
            .overlay(Circle().strokeBorder(accent, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    /// Whether the track finishes close enough to its start to call it a loop.
    /// Thirty metres is wider than GPS drift on a stationary phone and far
    /// narrower than a there-and-back.
    private var isLoop: Bool {
        guard let first = points.first, let last = points.last else { return false }
        return CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(
                from: CLLocation(latitude: last.latitude, longitude: last.longitude)
            ) < 30
    }

    /// The smallest region containing the whole track, with room around it.
    ///
    /// Built from the extremes rather than centred on the midpoint, so an
    /// out-and-back that doubles back on itself is still framed by where it
    /// actually reached. The minimum span keeps a treadmill-short track from
    /// being magnified until the map is a single texture.
    private var region: MKCoordinateRegion {
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.35, 0.003),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.35, 0.003)
            )
        )
    }
}

#if DEBUG
extension SessionRouteMap {
    /// An out-and-back with a loop at the far end, for looking at the map.
    ///
    /// The simulator does not move, so a session recorded there has no track
    /// and the map is correctly absent — which is useless for checking that
    /// the line, the framing and the markers are right. Deliberately not a
    /// closed loop, so both endpoint markers are exercised.
    static var previewPoints: [RoutePoint] {
        let start = CLLocationCoordinate2D(latitude: 43.6480, longitude: -79.4103)
        let legs: [(Double, Double, Int)] = [
            // (metres north per step, metres east per step, steps)
            (14, 0, 26),
            (0, 15, 14),
            (13, 0, 12),
            (0, -16, 15),
            (-12, 0, 11),
            (0, -14, 10),
            (11, 0, 9),
        ]

        var latitude = start.latitude
        var longitude = start.longitude
        var points: [RoutePoint] = []
        var moment = Date().addingTimeInterval(-3_000)

        for (north, east, steps) in legs {
            for _ in 0..<steps {
                latitude += north / 111_320
                longitude += east / (111_320 * cos(latitude * .pi / 180))
                moment.addTimeInterval(9)
                points.append(
                    RoutePoint(
                        latitude: latitude,
                        longitude: longitude,
                        recordedAt: moment,
                        speedMetersPerSecond: 3.1,
                        altitudeMeters: 96
                    )
                )
            }
        }
        return points
    }
}
#endif
