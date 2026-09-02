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

/// One live figure in the route card's readout.
private struct LiveStat: View {
    let title: String
    let value: String
    let unit: String
    let accent: Color
    let secondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.community(.title3, weight: .bold).monospacedDigit())
                Text(unit)
                    .font(.community(.caption2))
                    .foregroundStyle(secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title.lowercased()) \(value) \(unit)")
    }
}

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
                    .font(.community(.caption))
                    .foregroundStyle(Color.orange)
            }
        }
        .workoutCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.community(.subheadline))
                .foregroundStyle(tracker.isTracking ? phase.accent : phase.secondaryText)
            Text("Route")
                .font(.community(.subheadline, weight: .semibold))
            Spacer()
            if tracker.isTracking {
                Text("TRACKING")
                    .font(.community(.caption2, weight: .bold))
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
                .font(.community(.callout, weight: .semibold))
            Text("Rytivo can map your route and measure your distance and pace while this session runs. Location is only used during a session you start.")
                .font(.community(.caption))
                .foregroundStyle(.secondary)
            Button {
                tracker.requestPermission()
            } label: {
                Label("Allow Location Access", systemImage: "location")
                    .font(.community(.subheadline, weight: .semibold))
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
            .font(.community(.callout, weight: .semibold))
            Text("Your \(workoutType.title.lowercased()) is still timed and saved — it just won't have a map or a measured distance.")
                .font(.community(.caption))
                .foregroundStyle(.secondary)
            if tracker.permission == .denied,
               let settings = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settings) {
                    Label("Open Settings", systemImage: "gear")
                        .font(.community(.subheadline, weight: .semibold))
                }
            }
        }
    }

    /// Distance, pace or speed, and climb as the activity unfolds. A ride reads
    /// in mph and a run or swim in pace, since that is how each is judged.
    ///
    /// These are running estimates for the screen. When the session ends, the
    /// track is measured by the backend and those are the figures that count.
    /// The tracker holds kilometres throughout; miles are made here.
    private var liveReadout: some View {
        let isRide = workoutType == .biking

        // Prefer the average over the run so far: it is steadier to read than
        // the instantaneous value, which jitters with every fix.
        let rate: String = isRide
            ? (tracker.liveAverageSpeedKilometersPerHour
                ?? tracker.currentSpeedKilometersPerHour)
                .map {
                    String(
                        format: "%.1f",
                        ImperialUnits.milesPerHour(fromKilometersPerHour: $0)
                    )
                } ?? "--"
            : SessionRouteSummary.paceText(
                tracker.liveAveragePaceSecondsPerKilometer
                    ?? tracker.currentPaceSecondsPerKilometer
              )?.replacingOccurrences(of: " /mi", with: "") ?? "--"

        return HStack(alignment: .top, spacing: 0) {
            LiveStat(
                title: "DISTANCE",
                value: String(
                    format: "%.2f",
                    ImperialUnits.miles(fromKilometers: tracker.liveDistanceKilometers)
                ),
                unit: "mi",
                accent: phase.accent,
                secondary: phase.secondaryText
            )
            LiveStat(
                title: isRide ? "SPEED" : "PACE",
                value: rate,
                unit: isRide ? "mph" : "/mi",
                accent: phase.accent,
                secondary: phase.secondaryText
            )
            LiveStat(
                title: "CLIMB",
                value: String(
                    format: "%.0f",
                    ImperialUnits.feet(fromMeters: tracker.liveElevationGainMeters)
                ),
                unit: "ft",
                accent: phase.accent,
                secondary: phase.secondaryText
            )
        }
    }

    @ViewBuilder
    private var trackingBody: some View {
        if tracker.points.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for a GPS fix…")
                    .font(.community(.caption))
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

            Text("Live estimate · your distance, pace, climb and splits are measured from the full track when you end the session")
                .font(.community(.caption2))
                .foregroundStyle(.secondary)
        }
    }
}
