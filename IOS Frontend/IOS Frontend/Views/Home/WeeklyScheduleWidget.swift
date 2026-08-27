//
//  WeeklyScheduleWidget.swift
//  IOS Frontend
//
//  Home-screen widget: a compact weekly workout schedule strip.
//

import SwiftUI

/// A compact home-screen strip showing the user's workout schedule for the
/// current week. Each tile opens that day's complete workout workspace, while
/// the header opens the full weekly dashboard.
struct WeeklyScheduleWidget: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.workoutVisualPhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
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
        .repbaseCard(contentPadding: 14, cornerRadius: 17)
    }

    private var header: some View {
        NavigationLink {
            WorkoutsView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.community(.subheadline))
                    .foregroundStyle(phase.accent)
                Text("This Week")
                    .font(.community(.subheadline, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the weekly workout dashboard")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            WeeklyScheduleWidget()
                .padding()
            Spacer()
        }
        .repbaseScreen(.prepare)
    }
    .environment(WorkoutStore.preview)
}
