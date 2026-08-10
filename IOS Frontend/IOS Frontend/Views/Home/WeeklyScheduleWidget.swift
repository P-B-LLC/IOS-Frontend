//
//  WeeklyScheduleWidget.swift
//  IOS Frontend
//
//  Home-screen widget: a compact weekly workout schedule strip.
//

import SwiftUI

/// A compact home-screen strip showing the user's workout schedule for the
/// current week. All seven days sit in a single row across the width of the
/// screen; each tile shows the workout name (primary) with the weekday below
/// (secondary). Days with no workout stay clean. Tapping anywhere on the strip
/// opens the Workouts page.
struct WeeklyScheduleWidget: View {
    @Environment(WorkoutStore.self) private var store

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
        VStack(alignment: .leading, spacing: 10) {
            header
            // One row across the full width: all seven days always visible,
            // each tile an equal share of the width.
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    DayTile(
                        day: day,
                        workout: store.workout(on: day),
                        isToday: store.today == day
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
        // Theme-independent separation: the shadow fades in dark mode, the hairline doesn't.
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
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
    }
}

/// A single day within the weekly strip: workout name on top (primary),
/// short weekday label pinned to the bottom (secondary).
private struct DayTile: View {
    let day: Weekday
    let workout: Workout?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Primary: the workout name. Empty days stay clean (no placeholder).
            // In a narrow tile long names scale down / wrap to 2 lines / truncate
            // rather than breaking the row.
            ZStack {
                if let workout {
                    Text(workout.name)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Secondary: short weekday label, toward the bottom of the tile.
            Text(day.shortName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isToday ? 1.5 : 0)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Scheduled days get a subtle accent tint so workout days are easy to spot;
    /// rest days use a faint neutral fill. Both adapt to light / dark.
    private var tileFill: AnyShapeStyle {
        workout == nil
            ? AnyShapeStyle(Color.primary.opacity(0.04))
            : AnyShapeStyle(Color.accentColor.opacity(0.14))
    }

    private var accessibilityText: String {
        // Uses the full weekday name for VoiceOver even though the tile shows the short label.
        let base = workout.map { "\(day.fullName): \($0.name)" } ?? "\(day.fullName): no workout"
        return isToday ? "\(base), today" : base
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
    .environment(WorkoutStore())
}
