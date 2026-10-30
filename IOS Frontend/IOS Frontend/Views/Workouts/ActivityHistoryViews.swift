//
//  ActivityHistoryViews.swift
//  IOS Frontend
//
//  How a finished activity reads back: on its day, and in recent history.
//

import SwiftUI

/// Everything a finished activity recorded beyond sets.
///
/// Measured and entered values are labelled differently on purpose. A
/// distance from GPS or Apple Health says "Measured"; a typed distance and
/// every calorie figure say they are the person's own, so nobody mistakes an
/// estimate for something a sensor recorded.
struct ActivitySessionSummary: View {
    let session: PostableSession
    var phase: WorkoutVisualPhase = .recover
    var unit: ActivityLogDraft.DistanceUnit = .kilometers

    private var summary: SessionActivitySummary { session.activitySummary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                if let duration = session.durationSeconds, duration > 0 {
                    metric(ActivityDurationText.text(seconds: duration), "TIME", note: nil)
                }
                if let distance = summary.distanceKilometers ?? session.routeDistanceKilometers, distance > 0 {
                    metric(
                        ActivityDistanceFormat.text(kilometers: distance, unit: unit),
                        "DISTANCE",
                        note: summary.manualDistanceKilometers != nil && !summary.distanceIsMeasured
                            ? String(localized: "Your entry", bundle: .app, locale: .app, comment: "Marks a value the person typed rather than one measured")
                            : String(localized: "Measured", bundle: .app, locale: .app, comment: "Marks a value recorded by GPS or Apple Health")
                    )
                }
                if let calories = summary.manualCaloriesKilocalories {
                    metric(
                        String(localized: "\(calories) kcal", bundle: .app, locale: .app, comment: "Calories; kcal is the abbreviation for kilocalories"),
                        "CALORIES",
                        note: String(localized: "Your estimate", bundle: .app, locale: .app, comment: "Marks a calorie figure the person entered, not one measured")
                    )
                }
            }

            if let effort = summary.perceivedEffort {
                HStack(spacing: 10) {
                    EffortGlyph(score: effort, phase: phase)
                    Text("Effort \(effort) · \(EffortLevel(score: effort).title)")
                        .font(.community(.subheadline, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }

            let details = summary.details.summary(for: session.activity ?? .other)
            if !details.isEmpty {
                Text(details.joined(separator: "  ·  "))
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !summary.notes.isEmpty {
                Text(summary.notes)
                    .font(.community(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if summary.isManualEntry {
                Label("Logged after the session", systemImage: "square.and.pencil")
                    .font(.community(.caption2, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RepbaseDesign.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ value: String, _ title: LocalizedStringKey, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.community(.headline).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(phase.secondaryText)
            if let note {
                Text(note)
                    .font(.community(size: 10, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The effort chart in miniature: one rounded bar per band, rising, lit in
/// caramel up to the band the score is in.
struct EffortGlyph: View {
    let score: Int
    var phase: WorkoutVisualPhase = .prepare

    var body: some View {
        let level = EffortLevel(score: score).rawValue
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= level ? phase.accent : phase.primaryText.opacity(0.14))
                    .frame(width: 4, height: CGFloat(6 + index * 3))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The latest finished sessions, newest first: what "history" means on the
/// Training page. Every activity reads in its own terms -- sets for a lifting
/// day, time and effort for a match, distance for a run.
struct RecentActivityList: View {
    let sessions: [PostableSession]
    var phase: WorkoutVisualPhase = .prepare
    var unit: ActivityLogDraft.DistanceUnit = .kilometers
    @State private var opened: PostableSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(.community(.title3, weight: .bold))
            if sessions.isEmpty {
                Text("Finished workouts and logged activities appear here.")
                    .font(.community(.footnote))
                    .foregroundStyle(phase.secondaryText)
            }
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    Button { opened = session } label: { row(session) }
                        .buttonStyle(.plain)
                    if index < sessions.count - 1 { Divider() }
                }
            }
        }
        .sheet(item: $opened) { session in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(session.performedAt.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(.app)), systemImage: "calendar")
                            .font(.community(.caption, weight: .semibold))
                            .foregroundStyle(phase.secondaryText)
                        if session.activity?.usesSets == false {
                            ActivitySessionSummary(session: session, phase: .recover, unit: unit)
                        } else {
                            Text("^[\(session.loggedSetCount) set](inflect: true) logged")
                                .font(.community(.headline))
                            if let effort = session.activitySummary.perceivedEffort {
                                Text("Effort \(effort) · \(EffortLevel(score: effort).title)")
                                    .font(.community(.subheadline, weight: .semibold))
                            }
                            if !session.activitySummary.notes.isEmpty {
                                Text(session.activitySummary.notes).font(.community(.subheadline))
                            }
                        }
                    }
                    .padding(20)
                }
                .navigationTitle(session.workoutName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { opened = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func row(_ session: PostableSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: (session.activity ?? .other).symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(phase.accent)
                .frame(width: 38, height: 38)
                .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.workoutName)
                    .font(.community(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text(detail(session))
                    .font(.community(.caption).monospacedDigit())
                    .foregroundStyle(phase.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let effort = session.activitySummary.perceivedEffort {
                EffortGlyph(score: effort, phase: phase)
            }
            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(phase.secondaryText)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Tue 28 Oct · 1 h 05 min · 5.20 km"
    private func detail(_ session: PostableSession) -> String {
        var parts = [session.performedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))]
        if session.activity?.usesSets != false {
            parts.append(String(localized: "^[\(session.loggedSetCount) set](inflect: true)", bundle: .app, locale: .app))
        } else {
            if let duration = session.durationSeconds, duration > 0 {
                parts.append(ActivityDurationText.text(seconds: duration))
            }
            if let distance = session.activitySummary.distanceKilometers ?? session.routeDistanceKilometers, distance > 0 {
                parts.append(ActivityDistanceFormat.text(kilometers: distance, unit: unit))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// A distance in the unit being shown, from the kilometres every distance is
/// stored in.
enum ActivityDistanceFormat {
    static func text(kilometers: Double, unit: ActivityLogDraft.DistanceUnit) -> String {
        switch unit {
        case .kilometers:
            String(localized: "\(String(format: "%.2f", kilometers)) km", bundle: .app, locale: .app, comment: "A distance; km is the abbreviation for kilometres")
        case .miles:
            String(localized: "\(ImperialUnits.distanceFigure(kilometers: kilometers)) mi", bundle: .app, locale: .app, comment: "A distance; mi is the abbreviation for miles")
        }
    }
}
