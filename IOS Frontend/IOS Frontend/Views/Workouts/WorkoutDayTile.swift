//
//  WorkoutDayTile.swift
//  IOS Frontend
//
//  Shared compact day tile used on Home and the workout dashboard.
//

import SwiftUI

/// A compact, glanceable entry point into one day's workout workspace.
struct WorkoutDayTile: View {
    @Environment(\.workoutVisualPhase) private var phase

    let day: Weekday
    let workout: Workout?
    let isToday: Bool
    var isSessionActive = false
    /// How many workouts the day holds, so a day with more than one says so.
    var workoutCount = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(phase.shadow)
                    .offset(y: 3)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(phase.surfaceStart)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tileFill)

                Capsule()
                    .fill(Color.white.opacity(phase == .focus ? 0.12 : 0.42))
                    .frame(maxWidth: 28, maxHeight: 1.5)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)

                VStack(spacing: 3) {
                    if isSessionActive {
                        Image(systemName: "bolt.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WorkoutVisualPhase.focus.accent)
                    }

                    Text(workout?.name ?? "Add")
                        .font(.caption2)
                        .fontWeight(workout == nil ? .regular : .semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(workout == nil ? phase.secondaryText : phase.primaryText)
                }
                .padding(4)
            }
            .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isSessionActive ? 2 : 1)
                }
                // A badge rather than a second name: the tile is too small to
                // list them, but the day must not look like it holds only one.
                .overlay(alignment: .topTrailing) {
                    if workoutCount > 1 {
                        Text("\(workoutCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(WorkoutVisualPhase.prepare.accent, in: Circle())
                            .offset(x: 4, y: -4)
                            .accessibilityLabel("^[\(workoutCount) workout](inflect: true) planned")
                    }
                }

            Text(day.shortName)
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(
                    isToday ? WorkoutVisualPhase.prepare.accent : Color.secondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the \(day.fullName) workout")
    }

    private var tileFill: AnyShapeStyle {
        if isSessionActive {
            return AnyShapeStyle(WorkoutVisualPhase.focus.accent.opacity(0.14))
        }
        if workout != nil {
            return AnyShapeStyle(WorkoutVisualPhase.prepare.accent.opacity(0.14))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }

    private var borderColor: Color {
        if isSessionActive { return .green }
        return WorkoutVisualPhase.prepare.accent.opacity(isToday ? 1 : 0)
    }

    private var accessibilityText: String {
        var value = workout.map { "\(day.fullName): \($0.name)" } ?? "\(day.fullName): add a workout"
        if isToday { value += ", today" }
        if isSessionActive { value += ", session in progress" }
        return value
    }
}

/// The full workout-planning treatment. Wider than the compact home tile so
/// the card can explain both its content and its action without truncation.
struct WorkoutPlannerDayCard: View {
    @Environment(\.workoutVisualPhase) private var phase

    let day: Weekday
    let dateLabel: String
    let workout: Workout?
    let isToday: Bool
    var isSessionActive = false
    var workoutCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 5) {
                Text(day.shortName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(isToday ? phase.accent : phase.secondaryText)

                Spacer(minLength: 2)

                if isToday {
                    Text("TODAY")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(phase.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(phase.accent.opacity(0.12), in: Capsule())
                }
            }

            Text(dateLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(phase.secondaryText)
                .padding(.top, 3)

            Spacer(minLength: 10)

            Image(systemName: cardSymbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(workout == nil ? phase.accent : iconForeground)
                .frame(width: 34, height: 34)
                .background(iconBackground, in: Circle())

            Text(workout?.name ?? "Add workout")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(phase.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .padding(.top, 9)

            Text(detailText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(phase.secondaryText)
                .lineLimit(1)
                .padding(.top, 3)
        }
        .padding(12)
        .frame(width: 112, height: 146, alignment: .topLeading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(borderColor, style: borderStyle)
        }
        .shadow(color: shadowColor, radius: isToday ? 9 : 4, x: 0, y: isToday ? 5 : 2)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(workout == nil ? "Adds a workout on \(day.fullName)" : "Opens the \(day.fullName) workout")
    }

    private var cardSymbol: String {
        if isSessionActive { return "bolt.fill" }
        return workout?.type.symbolName ?? "plus"
    }

    private var detailText: String {
        if isSessionActive { return "Session active" }
        if workoutCount > 1 { return "\(workoutCount) workouts planned" }
        if workout != nil { return "Workout scheduled" }
        return "Plan this day"
    }

    private var iconForeground: Color {
        phase.usesDarkAppearance ? RepbasePalette.charcoal : RepbasePalette.cream
    }

    private var iconBackground: Color {
        workout == nil ? phase.accent.opacity(0.12) : phase.accent
    }

    private var cardBackground: Color {
        if workout != nil { return phase.surfaceStart }
        return phase.usesDarkAppearance ? phase.surfaceEnd : RepbasePalette.oatmeal.opacity(0.42)
    }

    private var borderColor: Color {
        if isSessionActive { return phase.accent }
        if workout != nil { return phase.accent.opacity(isToday ? 0.82 : 0.28) }
        return phase.secondaryText.opacity(0.24)
    }

    private var borderStyle: StrokeStyle {
        workout == nil
            ? StrokeStyle(lineWidth: 1, dash: [5, 4])
            : StrokeStyle(lineWidth: isToday || isSessionActive ? 1.5 : 1)
    }

    private var shadowColor: Color {
        if isToday { return phase.accent.opacity(0.16) }
        return phase.shadow.opacity(workout == nil ? 0.25 : 0.55)
    }

    private var accessibilityText: String {
        var value = workout.map { "\(day.fullName): \($0.name)" } ?? "\(day.fullName): add a workout"
        if isToday { value += ", today" }
        if isSessionActive { value += ", session in progress" }
        return value
    }
}

#Preview {
    HStack {
        WorkoutDayTile(day: .monday, workout: WorkoutStore.previewWorkouts[0], isToday: true)
        WorkoutDayTile(day: .tuesday, workout: nil, isToday: false)
        WorkoutDayTile(
            day: .wednesday,
            workout: WorkoutStore.previewWorkouts[1],
            isToday: false,
            isSessionActive: true
        )
    }
    .padding()
}
