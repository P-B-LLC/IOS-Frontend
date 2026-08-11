//
//  WorkoutsView.swift
//  IOS Frontend
//
//  A day-first weekly workout dashboard.
//

import SwiftUI

/// The weekly workout dashboard. Every day is its own card and opens a complete
/// day workspace for creating, viewing, editing, or removing that workout.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Week")
                        .font(.title2.weight(.bold))
                    Text("Choose a day to build or manage its workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                if let persistenceError = store.persistenceError {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button("Retry") {
                            store.retryPersistence()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                ForEach(Weekday.allCases) { day in
                    NavigationLink {
                        DayWorkoutView(day: day)
                    } label: {
                        DayWorkoutCard(
                            day: day,
                            workout: store.workout(on: day),
                            isToday: store.today == day
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Workouts")
    }
}

/// One tappable weekday widget in the weekly dashboard.
private struct DayWorkoutCard: View {
    let day: Weekday
    let workout: Workout?
    let isToday: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(day.shortName.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? Color.white : Color.accentColor)
                .frame(width: 54, height: 54)
                .background(
                    isToday ? Color.accentColor : Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(day.fullName)
                        .font(.headline)
                    if isToday {
                        Text("Today")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }

                Text(workout?.name ?? "Add a workout")
                    .font(.subheadline.weight(workout == nil ? .regular : .semibold))
                    .foregroundStyle(workout == nil ? Color.secondary : Color.primary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 7, y: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isToday ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the \(day.fullName) workout")
    }

    private var summary: String {
        guard let workout else { return "No workout scheduled" }
        let exerciseCount = workout.exercises.count
        let setCount = workout.totalSets
        let exercises = "\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")"
        let sets = "\(setCount) set\(setCount == 1 ? "" : "s")"
        return "\(exercises) · \(sets)"
    }

    private var accessibilityText: String {
        let status = workout.map { "\($0.name), \(summary)" } ?? "no workout scheduled"
        return isToday ? "\(day.fullName), today, \(status)" : "\(day.fullName), \(status)"
    }
}

#Preview {
    NavigationStack {
        WorkoutsView()
    }
    .environment(WorkoutStore.preview)
}
