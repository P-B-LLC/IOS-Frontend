//
//  SessionProgressChart.swift
//  IOS Frontend
//
//  How a run has progressed over past sessions of the same workout.
//

import Charts
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
            case .distance: return "Distance"
            case .pace: return type == .biking ? "Speed" : "Pace"
            }
        }
    }

    @State private var metric: Metric = .distance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PROGRESS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.secondaryText)
                Spacer()
                Text("^[last \(history.count) session](inflect: true)")
                    .font(.caption2)
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
                    .font(.caption2)
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
                            .font(.caption2)
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
                            .font(.caption2)
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
            let value: Double?
            switch metric {
            case .distance:
                value = entry.distanceKilometers
            case .pace:
                guard let pace = entry.paceSecondsPerKilometer, pace > 0 else {
                    return nil
                }
                // A ride reads in km/h, where higher is better; a run reads in
                // seconds per km, where lower is.
                value = workoutType == .biking ? 3600 / pace : pace
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
        let change = last.value - first.value

        switch metric {
        case .distance:
            guard abs(change) >= 0.05 else { return "Distance is holding steady." }
            return change > 0
                ? String(format: "Up %.2f km since your first session.", change)
                : String(format: "Down %.2f km since your first session.", -change)
        case .pace:
            if workoutType == .biking {
                guard abs(change) >= 0.1 else { return "Speed is holding steady." }
                return change > 0
                    ? String(format: "Averaging %.1f km/h faster than your first ride.", change)
                    : String(format: "Averaging %.1f km/h slower than your first ride.", -change)
            }
            guard abs(change) >= 1 else { return "Pace is holding steady." }
            let seconds = Int(abs(change).rounded())
            let text = String(format: "%d:%02d", seconds / 60, seconds % 60)
            return change < 0
                ? "\(text) per km faster than your first session."
                : "\(text) per km slower than your first session."
        }
    }
}
