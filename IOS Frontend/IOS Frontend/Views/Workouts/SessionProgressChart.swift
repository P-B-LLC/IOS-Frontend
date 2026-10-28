//
//  SessionProgressChart.swift
//  IOS Frontend
//
//  How a run has progressed over past sessions of the same workout.
//

import Charts
import Foundation
import SwiftUI

struct SessionProgressChart: View {
    /// Past sessions, oldest first.
    let history: [SessionHistoryPoint]
    let workoutType: WorkoutType
    let phase: WorkoutVisualPhase

    enum Metric: String, CaseIterable, Identifiable {
        case distance
        case pace

        var id: String { rawValue }

        func title(for type: WorkoutType) -> String {
            switch self {
            case .distance: return String(localized: "Distance", bundle: .app, locale: .app)
            case .pace:
                return type == .biking
                    ? String(localized: "Speed", bundle: .app, locale: .app)
                    : String(localized: "Pace", bundle: .app, locale: .app, comment: "Running pace: time per mile")
            }
        }
    }

    @State private var metric: Metric = .distance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PROGRESS")
                    .font(.community(.caption2, weight: .bold))
                    .foregroundStyle(phase.secondaryText)
                Spacer()
                Text("^[last \(history.count) session](inflect: true)")
                    .font(.community(.caption2))
                    .foregroundStyle(phase.secondaryText)
            }

            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { option in
                    Text(option.title(for: workoutType)).tag(option)
                }
            }
            .pickerStyle(.segmented)

            chart
                .frame(height: 150)

            if let caption {
                Text(caption)
                    .font(.community(.caption2))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .padding(14)
        .background(
            phase.accent.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    @ViewBuilder
    private var chart: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Session", point.date),
                y: .value(metric.title(for: workoutType), point.value)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [phase.accent.opacity(0.28), phase.accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Session", point.date),
                y: .value(metric.title(for: workoutType), point.value)
            )
            .foregroundStyle(phase.accent)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.monotone)

            PointMark(
                x: .value("Session", point.date),
                y: .value(metric.title(for: workoutType), point.value)
            )
            .foregroundStyle(phase.accent)
            .symbolSize(45)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(phase.secondaryText.opacity(0.25))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(axisLabel(for: raw))
                            .font(.community(.caption2))
                            .foregroundStyle(phase.secondaryText)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.community(.caption2))
                            .foregroundStyle(phase.secondaryText)
                    }
                }
            }
        }
        // Pace is better when lower, so the axis is flipped to keep "up" as
        // "improving" whichever metric is shown.
        .chartYScale(domain: .automatic(includesZero: false, reversed: isReversed))
    }

    // MARK: - Data

    private struct ChartPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    private var points: [ChartPoint] {
        history.compactMap { entry in
            // Converted here rather than at the axis, so the plotted values and
            // the caption underneath are the same numbers.
            let value: Double?
            switch metric {
            case .distance:
                value = ImperialUnits.miles(fromKilometers: entry.distanceKilometers)
            case .pace:
                guard let pace = entry.paceSecondsPerKilometer, pace > 0 else {
                    return nil
                }
                // A ride reads in mph, where higher is better; a run reads in
                // seconds per mile, where lower is.
                value = workoutType == .biking
                    ? ImperialUnits.milesPerHour(fromKilometersPerHour: 3600 / pace)
                    : ImperialUnits.paceSecondsPerMile(fromPerKilometer: pace)
            }
            guard let value else { return nil }
            return ChartPoint(id: entry.sessionID, date: entry.date, value: value)
        }
    }

    /// Only running and swimming pace improves downward.
    private var isReversed: Bool {
        metric == .pace && workoutType != .biking
    }

    private func axisLabel(for value: Double) -> String {
        switch metric {
        case .distance:
            return String(format: "%.1f", value)
        case .pace:
            if workoutType == .biking {
                return String(format: "%.0f", value)
            }
            let total = Int(value.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    private var caption: String? {
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return nil
        }
        // `points` is already imperial, so this difference is in miles, mph, or
        // seconds per mile. Converting again here would square the conversion
        // and report a 1 mile gain as 0.62.
        let change = last.value - first.value

        // Numbers are written out first, so each sentence is translated
        // whole with the figure as its placeholder.
        switch metric {
        case .distance:
            guard abs(change) >= 0.05 else { return String(localized: "Distance is holding steady.", bundle: .app, locale: .app) }
            let miles = String(format: "%.2f", abs(change))
            return change > 0
                ? String(localized: "Up \(miles) mi since your first session.", bundle: .app, locale: .app, comment: "The placeholder is a number of miles")
                : String(localized: "Down \(miles) mi since your first session.", bundle: .app, locale: .app, comment: "The placeholder is a number of miles")
        case .pace:
            if workoutType == .biking {
                guard abs(change) >= 0.1 else { return String(localized: "Speed is holding steady.", bundle: .app, locale: .app) }
                let speed = String(format: "%.1f", abs(change))
                return change > 0
                    ? String(localized: "Averaging \(speed) mph faster than your first ride.", bundle: .app, locale: .app, comment: "The placeholder is a speed in miles per hour")
                    : String(localized: "Averaging \(speed) mph slower than your first ride.", bundle: .app, locale: .app, comment: "The placeholder is a speed in miles per hour")
            }
            guard abs(change) >= 1 else { return String(localized: "Pace is holding steady.", bundle: .app, locale: .app) }
            let seconds = Int(abs(change).rounded())
            let text = String(format: "%d:%02d", seconds / 60, seconds % 60)
            return change < 0
                ? String(localized: "\(text) per mile faster than your first session.", bundle: .app, locale: .app, comment: "The placeholder is minutes and seconds, e.g. 0:12")
                : String(localized: "\(text) per mile slower than your first session.", bundle: .app, locale: .app, comment: "The placeholder is minutes and seconds, e.g. 0:12")
        }
    }
}
