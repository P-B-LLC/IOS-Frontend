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
                            isSessionActive: store.activeSession?.day == day
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        NavigationLink {
            WorkoutsView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text("This Week")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
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
        .background(Color(uiColor: .systemGroupedBackground))
    }
    .environment(WorkoutStore.preview)
}
