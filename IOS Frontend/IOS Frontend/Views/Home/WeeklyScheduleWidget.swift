//
//  WeeklyScheduleWidget.swift
//  IOS Frontend
//
//  Home-screen widget: the user's workout schedule for the current week.
//

import SwiftUI

/// A home-screen widget showing the user's workout schedule for the current
/// week (Monday–Sunday). Each day is an inner tile: the workout name is the
/// primary content, with the weekday as a secondary label beneath it. Days
/// with no workout stay visually clean. Tapping anywhere on the widget opens
/// the Workouts page.
struct WeeklyScheduleWidget: View {
    @Environment(WorkoutStore.self) private var store

    /// Adaptive columns keep the whole week visible: 2 across on every iPhone in
    /// portrait, scaling up toward the full week per row on iPad / landscape.
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationLink {
            WorkoutsView()
        } label: {
            card
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week's workout schedule")
        .accessibilityHint("Opens the Workouts page")
        .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Weekday.allCases) { day in
                    DayTile(
                        day: day,
                        workout: store.workout(on: day),
                        isToday: store.today == day
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        )
        // Theme-independent separation: the shadow fades in dark mode, the hairline doesn't.
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("This Week")
                    .font(.headline)
                Text("Your workout schedule")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// A single day within the weekly widget: workout name on top (primary),
/// weekday label pinned toward the bottom (secondary).
private struct DayTile: View {
    let day: Weekday
    let workout: Workout?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Primary: the workout name. Empty days stay clean (no placeholder).
            ZStack {
                if let workout {
                    Text(workout.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Secondary: the weekday, toward the bottom of the tile.
            Text(day.fullName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        // maxHeight lets every tile fill its grid row so the bottom-pinned
        // weekday labels stay aligned, even under large Dynamic Type.
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isToday ? 2 : 0)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Scheduled days get a subtle accent tint so workout days are easy to spot;
    /// rest days use a faint neutral fill. Both adapt to light / dark.
    private var tileFill: AnyShapeStyle {
        workout == nil
            ? AnyShapeStyle(Color.primary.opacity(0.04))
            : AnyShapeStyle(Color.accentColor.opacity(0.12))
    }

    private var accessibilityText: String {
        let base = workout.map { "\(day.fullName): \($0.name)" } ?? "\(day.fullName): no workout"
        return isToday ? "\(base), today" : base
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            WeeklyScheduleWidget()
                .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    .environment(WorkoutStore())
}
