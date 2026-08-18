//
//  WorkoutsView.swift
//  IOS Frontend
//
//  Compact day-first weekly workout dashboard.
//

import SwiftUI

struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store

    private var phase: WorkoutVisualPhase {
        store.activeSession == nil ? .prepare : .focus
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RepbaseDesign.sectionSpacing) {
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
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .repbaseScreen(phase)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TRAINING")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(phase.accent)
            Text("Your week")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.65)
                .foregroundStyle(phase.primaryText)
            Text("Choose any day to plan, customize, or log a workout.")
                .font(.system(size: 14, weight: .medium))
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
                WorkoutReferenceHero(
                    eyebrow: "SESSION IN PROGRESS",
                    title: session.workoutName,
                    detail: "\(session.loggedSetCount) of \(session.totalSetCount) sets logged",
                    isActive: true
                )
            }
            .buttonStyle(.plain)
        } else if let focusDay = store.today ?? Weekday.allCases.first {
            NavigationLink {
                DayWorkoutView(day: focusDay)
            } label: {
                WorkoutReferenceHero(
                    eyebrow: "TODAY",
                    title: store.workout(on: focusDay)?.name ?? "Plan today's workout",
                    detail: focusDescription(for: focusDay),
                    isActive: false
                )
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

/// A data-backed version of the product centerpiece in the supplied vehicle
/// reference: the workout is the object, while the rail exposes its states.
private struct WorkoutReferenceHero: View {
    let eyebrow: String
    let title: String
    let detail: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.25)
                        .foregroundStyle(isActive ? RepbaseDesign.accent : Color.secondary)
                    Text(title)
                        .font(.system(size: 23, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(RepbaseDesign.ink)
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RepbasePalette.cream)
                    .frame(width: 34, height: 34)
                    .background(RepbaseDesign.ink, in: Circle())
            }

            ZStack(alignment: .trailing) {
                DumbbellObject()
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 28)

                VStack(spacing: 5) {
                    railButton("figure.strengthtraining.traditional", selected: true)
                    railButton("list.bullet", selected: false)
                    railButton(isActive ? "bolt.fill" : "plus", selected: false)
                    railButton("chart.line.uptrend.xyaxis", selected: false)
                }
                .padding(5)
                .background(RepbasePalette.paper.opacity(0.96), in: Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
            }
            .frame(height: 158)
        }
        .padding(18)
        .background(RepbasePalette.paper, in: RoundedRectangle(cornerRadius: RepbaseDesign.featureRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RepbaseDesign.featureRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.09), radius: 18, x: 0, y: 9)
    }

    private func railButton(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(selected ? RepbasePalette.cream : RepbaseDesign.ink)
            .frame(width: 30, height: 30)
            .background(selected ? RepbaseDesign.ink : Color.clear, in: Circle())
    }
}

private struct DumbbellObject: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x4A4D52), Color(hex: 0x111214), Color(hex: 0x62666C)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 206, height: 28)

            HStack(spacing: 104) {
                weightStack
                weightStack
            }
        }
        .rotationEffect(.degrees(-7))
        .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 12)
        .overlay(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.12))
                .frame(width: 230, height: 18)
                .blur(radius: 8)
                .offset(y: 30)
        }
    }

    private var weightStack: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x747980), Color(hex: 0x161719), Color(hex: 0x3D4044)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 76, height: 76)
            Circle().stroke(Color.white.opacity(0.30), lineWidth: 2).frame(width: 62, height: 62)
            Circle().fill(Color(hex: 0x0C0D0E)).frame(width: 29, height: 29)
            Circle().fill(Color(hex: 0xA6AAB0)).frame(width: 12, height: 12)
        }
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
