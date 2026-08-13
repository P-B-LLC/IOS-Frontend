//
//  WorkoutDayTile.swift
//  IOS Frontend
//
//  Shared compact day tile used on Home and the workout dashboard.
//

import SwiftUI

/// A compact, glanceable entry point into one day's workout workspace.
struct WorkoutDayTile: View {
    let day: Weekday
    let workout: Workout?
    let isToday: Bool
    var isSessionActive = false
    /// How many workouts the day holds, so a day with more than one says so.
    var workoutCount = 0

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tileFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 3) {
                        if isSessionActive {
                            Image(systemName: "bolt.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.green)
                        }

                        Text(workout?.name ?? "Add")
                            .font(.caption2)
                            .fontWeight(workout == nil ? .regular : .semibold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)
                            .foregroundStyle(workout == nil ? Color.secondary : Color.primary)
                    }
                    .padding(4)
                }
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
                            .background(Color.accentColor, in: Circle())
                            .offset(x: 4, y: -4)
                            .accessibilityLabel("^[\(workoutCount) workout](inflect: true) planned")
                    }
                }

            Text(day.shortName)
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
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
            return AnyShapeStyle(Color.green.opacity(0.14))
        }
        if workout != nil {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }

    private var borderColor: Color {
        if isSessionActive { return .green }
        return Color.accentColor.opacity(isToday ? 1 : 0)
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
