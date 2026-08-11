//
//  WorkoutsView.swift
//  IOS Frontend
//
//  Compact day-first weekly workout dashboard.
//

import SwiftUI

struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro

                if let persistenceError = store.persistenceError {
                    persistenceErrorCard(persistenceError)
                }

                weekCard
                focusCard
                weeklySummary
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Workouts")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Week")
                .font(.title2.weight(.bold))
            Text("Choose any day to plan, customize, or log a workout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Workout Plan", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text("Tap a day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    NavigationLink {
                        DayWorkoutView(day: day)
                    } label: {
                        WorkoutDayTile(
                            day: day,
                            workout: store.workout(on: day),
                            isToday: store.today == day,
                            isSessionActive: store.activeSession?.day == day
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .workoutCard()
    }

    @ViewBuilder
    private var focusCard: some View {
        if let session = store.activeSession {
            NavigationLink {
                DayWorkoutView(day: session.day)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(Color.white)
                        .frame(width: 48, height: 48)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SESSION IN PROGRESS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.green)
                        Text(session.workoutName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(session.loggedSetCount) of \(session.totalSetCount) sets logged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .workoutCard()
            }
            .buttonStyle(.plain)
        } else if let focusDay = store.today ?? Weekday.allCases.first {
            NavigationLink {
                DayWorkoutView(day: focusDay)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: store.workout(on: focusDay) == nil ? "plus" : "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text(store.workout(on: focusDay)?.name ?? "Plan today's workout")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(focusDescription(for: focusDay))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .workoutCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var weeklySummary: some View {
        let workouts = Weekday.allCases.compactMap { store.workout(on: $0) }
        let exerciseCount = workouts.reduce(0) { $0 + $1.exercises.count }
        let setCount = workouts.reduce(0) { $0 + $1.totalSets }

        return VStack(alignment: .leading, spacing: 14) {
            Text("Week at a Glance")
                .font(.headline)

            HStack(spacing: 10) {
                WeekStat(value: workouts.count, label: "Planned", icon: "calendar.badge.checkmark")
                WeekStat(value: exerciseCount, label: "Exercises", icon: "list.bullet")
                WeekStat(value: setCount, label: "Target Sets", icon: "checklist")
            }
        }
        .workoutCard()
    }

    private func persistenceErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.orange)
            Button("Retry") {
                store.retryPersistence()
            }
            .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func focusDescription(for day: Weekday) -> String {
        guard let workout = store.workout(on: day) else {
            return "Add a name, exercises, and target sets."
        }
        return "\(workout.exercises.count) exercises | \(workout.totalSets) target sets"
    }
}

private struct WeekStat: View {
    let value: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            Text("\(value)")
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

extension View {
    /// The shared surface treatment for workout planning and logging cards.
    func workoutCard() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 7, y: 2)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

#Preview {
    NavigationStack {
        WorkoutsView()
    }
    .environment(WorkoutStore.preview)
}
