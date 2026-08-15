//
//  LiftProgressChart.swift
//  IOS Frontend
//
//  How the lifts in a session have progressed over every session before it.
//

import Charts
import SwiftUI

struct LiftProgressChart: View {
    /// One series per exercise in the finished session.
    let series: [LiftProgressSeries]
    let phase: WorkoutVisualPhase

    enum Metric: String, CaseIterable, Identifiable {
        case heaviest
        case volume

        var id: String { rawValue }

        var title: String {
            switch self {
            case .heaviest: return "Heaviest"
            case .volume: return "Volume"
            }
        }
    }

    @State private var metric: Metric = .heaviest
    @State private var selectedExerciseID: Int?

    private var selected: LiftProgressSeries? {
        series.first { $0.exerciseID == selectedExerciseID } ?? series.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PROGRESS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.secondaryText)
                Spacer()
                if let selected {
                    Text("^[\(selected.days.count) session](inflect: true)")
                        .font(.caption2)
                        .foregroundStyle(phase.secondaryText)
                }
            }

            // Only worth a picker when the session trained more than one lift.
            if series.count > 1 {
                Picker("Exercise", selection: exerciseBinding) {
                    ForEach(series) { entry in
                        Text(entry.exerciseName).tag(entry.exerciseID)
                    }
                }
                .pickerStyle(.menu)
                .tint(phase.accent)
            } else if let selected {
                Text(selected.exerciseName)
                    .font(.subheadline.weight(.semibold))
            }

            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if let selected {
                chart(for: selected)
                    .frame(height: 150)

                if let caption = caption(for: selected) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(phase.secondaryText)
                }
            }
        }
        .padding(14)
        .background(
            phase.accent.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var exerciseBinding: Binding<Int> {
        Binding(
            get: { selected?.exerciseID ?? 0 },
            set: { selectedExerciseID = $0 }
        )
    }

    private func chart(for entry: LiftProgressSeries) -> some View {
        Chart(entry.days) { day in
            // A line reads as a trend across sessions in a way separate bars
            // do not, which is the point of the chart.
            AreaMark(
                x: .value("Session", day.date),
                y: .value(metric.title, value(for: day))
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [phase.accent.opacity(0.28), phase.accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Session", day.date),
                y: .value(metric.title, value(for: day))
            )
            .foregroundStyle(phase.accent)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.monotone)

            PointMark(
                x: .value("Session", day.date),
                y: .value(metric.title, value(for: day))
            )
            .foregroundStyle(phase.accent)
            .symbolSize(45)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(phase.secondaryText.opacity(0.25))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(String(format: "%.0f", raw))
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
    }

    private func value(for day: LiftProgressSeries.Day) -> Double {
        switch metric {
        case .heaviest: return day.heaviestKilograms
        case .volume: return day.volumeKilograms
        }
    }

    private func caption(for entry: LiftProgressSeries) -> String? {
        guard let first = entry.days.first, let last = entry.days.last,
              entry.days.count > 1 else {
            return nil
        }
        let change = value(for: last) - value(for: first)
        let unit = metric == .heaviest ? "kg" : "kg lifted"

        guard abs(change) >= 0.5 else {
            return "\(metric.title) is holding steady."
        }
        return change > 0
            ? String(format: "Up %.0f %@ since your first session.", change, unit)
            : String(format: "Down %.0f %@ since your first session.", -change, unit)
    }
}
