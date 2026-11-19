//
//  RouteProbeView.swift
//  IOS Frontend
//
//  A launch-time run of the GPS path, end to end, because nothing else can
//  reach it.
//
//  No session in the database has ever stored a single route point. Every
//  piece exists and is tested on its own -- RouteTracker, the upload
//  endpoint, the deduplication, the stored summary -- and not one of them has
//  ever been run against the next one. The reason is mundane: recording a run
//  starts with tapping a button, `simctl` has no way to tap, and there is no
//  XCUITest target to do it instead.
//
//  So this does what the tap would have led to. `simctl location start`
//  drives the simulator along a set of waypoints, `simctl privacy grant`
//  supplies the authorisation the permission sheet would have, and this view
//  starts the real tracker, waits for real fixes, and hands them to the real
//  repository method the workout screen calls. What it proves is only what it
//  actually runs: CoreLocation reaching RouteTracker, RouteTracker's filters,
//  and the upload the app performs. It is not a substitute for someone
//  running outdoors with the screen locked.
//
//  Reads its token and session from the environment rather than signing in,
//  so it tests the route and nothing else. Output goes to NSLog, which
//  `simctl launch --console-pty` captures.
//

#if DEBUG
import SwiftUI

struct RouteProbeView: View {
    @State private var lines: [String] = ["starting…"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.community(.footnote).monospaced())
        .padding(24)
        .task { await probe() }
    }

    private func say(_ line: String) {
        NSLog("RYTIVO-ROUTE %@", line)
        lines.append(line)
    }

    private func probe() async {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["REPBASE_ROUTE_TOKEN"],
              let sessionText = environment["REPBASE_ROUTE_SESSION"],
              let sessionID = Int(sessionText) else {
            say("FAIL need REPBASE_ROUTE_TOKEN and REPBASE_ROUTE_SESSION")
            return
        }

        let tracker = RouteTracker()
        say("permission before: \(tracker.permission)")
        tracker.requestPermission()

        // The authorisation callback is asynchronous even when the state was
        // granted ahead of time, so give it a moment rather than reading a
        // value that has not arrived.
        for _ in 0..<20 where !tracker.permission.allowsTracking {
            try? await Task.sleep(for: .milliseconds(100))
        }
        say("permission after: \(tracker.permission) precise: \(tracker.hasPreciseLocation)")

        guard tracker.permission.allowsTracking else {
            say("FAIL not authorised, so startTracking would do nothing")
            return
        }

        tracker.startTracking()
        say("tracking: \(tracker.isTracking)")

        // Collect for a while, reporting as fixes land so a run that produces
        // nothing is distinguishable from one that never started.
        let wanted = Int(environment["REPBASE_ROUTE_POINTS"] ?? "") ?? 12
        for tick in 1...60 {
            try? await Task.sleep(for: .seconds(1))
            if tick % 5 == 0 {
                say("t+\(tick)s points: \(tracker.points.count) live_km: \(String(format: "%.3f", tracker.liveDistanceKilometers))")
            }
            if tracker.points.count >= wanted { break }
        }

        if let failure = tracker.trackingError {
            say("tracking error: \(failure)")
        }

        let points = tracker.stopTracking()
        say("recorded \(points.count) points")
        guard points.count >= 2 else {
            say("FAIL fewer than two fixes, nothing to upload")
            return
        }
        let withSpeed = points.filter { $0.speedMetersPerSecond != nil }.count
        let withAltitude = points.filter { $0.altitudeMeters != nil }.count
        say("with speed: \(withSpeed) with altitude: \(withAltitude)")

        do {
            let configuration = APIConfiguration.current
            say("server: \(configuration.serverURL)")
            let repository = try WorkoutAPIRepository(
                configuration: configuration,
                token: token
            )
            let summary = try await repository.uploadRoute(points, sessionID: sessionID)
            say("UPLOADED distance_km: \(summary.distanceKilometers.map { String(format: "%.3f", $0) } ?? "nil")")
            say("pace_s_per_km: \(summary.paceSecondsPerKilometer.map { String(format: "%.1f", $0) } ?? "nil")")
            say("max_speed_kmh: \(summary.maxSpeedKilometersPerHour.map { String(format: "%.2f", $0) } ?? "nil")")
            say("moving_seconds: \(summary.movingSeconds.map { String(format: "%.1f", $0) } ?? "nil")")
            say("elevation_gain_m: \(summary.elevationGainMeters.map { String(format: "%.1f", $0) } ?? "nil")")
            say("splits: \(summary.splits.count)")
            say("DONE")
        } catch {
            say("FAIL upload: \(error)")
        }
    }
}
#endif
