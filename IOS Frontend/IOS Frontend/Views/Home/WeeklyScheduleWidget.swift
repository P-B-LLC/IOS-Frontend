//
//  WeeklyScheduleWidget.swift
//  IOS Frontend
//
//  Home-screen widget: a compact weekly workout schedule strip.
//

import SwiftUI

/// A compact home-screen strip showing the user's workout schedule for the
/// current week. All seven days sit in a single row across the width of the
/// screen. Each day is a square tile holding the workout name, with the
/// weekday label below the square (outside it). Days with no workout show an
/// add prompt; the current day is subtly highlighted. Tapping the strip opens
/// the day-first Workouts page.
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
            // each an equal share of the width.
            HStack(alignment: .top, spacing: 6) {
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

/// A single day within the weekly strip: a square tile holding the workout
/// name (primary), with the short weekday label below the square (secondary).
private struct DayTile: View {
    let day: Weekday
    let workout: Workout?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 6) {
            // The square tile. Scheduled days show the workout name; unscheduled
            // days show an add prompt. Long names scale down / wrap /
            // truncate rather than stretching the square.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tileFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // Scheduled days show the workout name; unscheduled days show
                    // a muted add prompt (tapping the strip opens Workouts).
                    Text(workout?.name ?? "Add")
                        .font(.caption2)
                        .fontWeight(workout == nil ? .regular : .semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(workout == nil ? Color.secondary : Color.primary)
                        .padding(4)
                }
                // Subtle "today" highlight: a thin accent ring on the square.
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isToday ? 1 : 0), lineWidth: 1)
                }

            // The weekday label sits below the square (outside the tile).
            // The current day is subtly highlighted in the accent color.
            Text(day.shortName)
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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
    .environment(WorkoutStore.preview)
}
