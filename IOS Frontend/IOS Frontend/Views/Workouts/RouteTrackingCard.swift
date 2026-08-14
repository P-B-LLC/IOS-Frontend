//
//  RouteTrackingCard.swift
//  IOS Frontend
//
//  Live GPS state for a cardio session: permission, the map of the route so
//  far, and the fixes recorded. Distance and pace are shown only once the
//  backend has computed them.
//

import CoreLocation
import MapKit
import SwiftUI

struct RouteTrackingCard: View {
    let tracker: RouteTracker
    let workoutType: WorkoutType

    @Environment(\.workoutVisualPhase) private var phase
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch tracker.permission {
            case .notDetermined:
                permissionPrompt
            case .denied, .restricted:
                permissionDenied
            case .authorized:
                trackingBody
            }

            if let error = tracker.trackingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
        .workoutCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.subheadline)
                .foregroundStyle(tracker.isTracking ? phase.accent : phase.secondaryText)
            Text("Route")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if tracker.isTracking {
                Text("TRACKING")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(phase.accent.opacity(0.14), in: Capsule())
            }
        }
    }

    /// Shown before the system prompt so the reason is on screen when it appears.
    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Track this \(workoutType.title.lowercased())?")
                .font(.callout.weight(.semibold))
            Text("Repbase can map your route and measure your distance and pace while this session runs. Location is only used during a session you start.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                tracker.requestPermission()
            } label: {
                Label("Allow Location Access", systemImage: "location")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
        }
    }

    private var permissionDenied: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                tracker.permission == .restricted
                    ? "Location access is restricted on this device."
                    : "Location access is off."
            )
            .font(.callout.weight(.semibold))
            Text("Your \(workoutType.title.lowercased()) is still timed and saved — it just won't have a map or a measured distance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if tracker.permission == .denied,
               let settings = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settings) {
                    Label("Open Settings", systemImage: "gear")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    /// Live speed straight from the GPS sensor. A ride reads in km/h and a run
    /// or swim in pace, since that is how each is normally judged.
    @ViewBuilder
    private var liveReadout: some View {
        let isRide = workoutType == .biking
        let value: String? = isRide
            ? tracker.currentSpeedKilometersPerHour.map { String(format: "%.1f", $0) }
            : SessionRouteSummary.paceText(tracker.currentPaceSecondsPerKilometer)
                .map { $0.replacingOccurrences(of: " /km", with: "") }

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(isRide ? "SPEED" : "PACE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value ?? "--")
                .font(.title2.weight(.bold).monospacedDigit())
            Text(isRide ? "km/h" : "/km")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var trackingBody: some View {
        if tracker.points.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for a GPS fix…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
        } else {
            Map(position: $cameraPosition) {
                MapPolyline(coordinates: tracker.points.map(\.coordinate))
                    .stroke(phase.accent, lineWidth: 4)
                if let last = tracker.points.last {
                    Annotation("You", coordinate: last.coordinate) {
                        Circle()
                            .fill(phase.accent)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: tracker.points.count) {
                guard let last = tracker.points.last else { return }
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: last.coordinate,
                        latitudinalMeters: 800,
                        longitudinalMeters: 800
                    )
                )
            }

            liveReadout

            Text("^[\(tracker.points.count) point](inflect: true) recorded · your distance, pace and splits are calculated when you end the session")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
