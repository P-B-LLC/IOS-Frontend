//
//  WorkoutsView.swift
//  IOS Frontend
//
//  Compact day-first weekly workout dashboard.
//

import SwiftUI

struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    private let phase = WorkoutVisualPhase.prepare

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro

                if let persistenceError = store.persistenceError {
                    persistenceErrorCard(persistenceError)
                }

                if store.isLoading {
                    ProgressView("Loading this week from Repbase...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .workoutCard()
                } else {
                    weekCard
                    focusCard
                    weeklySummary
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background { WorkoutPhaseBackground(phase: phase) }
        .workoutVisualPhase(phase)
        .tint(phase.accent)
        .preferredColorScheme(.light)
        .navigationTitle("Workouts")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Week")
                .font(.title2.weight(.bold))
                .foregroundStyle(phase.primaryText)
            Text("Choose any day to plan, customize, or log a workout.")
                .font(.subheadline)
                .foregroundStyle(phase.secondaryText)
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
                    .foregroundStyle(phase.secondaryText)
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
                            isSessionActive: store.activeSession?.day == day,
                            workoutCount: store.workoutCount(on: day)
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
                        .foregroundStyle(WorkoutVisualPhase.focus.onAccent)
                        .frame(width: 48, height: 48)
                        .background(WorkoutVisualPhase.focus.accent, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SESSION IN PROGRESS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WorkoutVisualPhase.focus.accent)
                        Text(session.workoutName)
                            .font(.headline)
                            .foregroundStyle(WorkoutVisualPhase.focus.primaryText)
                        Text("\(session.loggedSetCount) of \(session.totalSetCount) sets logged")
                            .font(.caption)
                            .foregroundStyle(WorkoutVisualPhase.focus.secondaryText)
                    }

                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkoutVisualPhase.focus.secondaryText)
                }
                .workoutCard()
                .workoutVisualPhase(.focus)
            }
            .buttonStyle(.plain)
        } else if let focusDay = store.today ?? Weekday.allCases.first {
            NavigationLink {
                DayWorkoutView(day: focusDay)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: store.workout(on: focusDay) == nil ? "plus" : "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(phase.accent)
                        .frame(width: 48, height: 48)
                        .background(phase.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(hex: 0xFDC094))
                        Text(store.workout(on: focusDay)?.name ?? "Plan today's workout")
                            .font(.headline)
                            .foregroundStyle(Color(hex: 0xF7F7F8))
                        Text(focusDescription(for: focusDay))
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0xCFCFD0))
                    }

                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xFDC094))
                }
                .padding(16)
                .background {
                    WorkoutHeroBackground(phase: phase)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: phase.shadow, radius: 14, x: 5, y: 8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
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
                WeekStat(value: workouts.count, label: "Planned", icon: "calendar.badge.checkmark", accent: phase.accent)
                WeekStat(value: exerciseCount, label: "Exercises", icon: "list.bullet", accent: phase.accent)
                WeekStat(value: setCount, label: "Target Sets", icon: "checklist", accent: phase.accent)
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
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(accent)
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

#Preview {
    NavigationStack {
        WorkoutsView()
    }
    .environment(WorkoutStore.preview)
}
