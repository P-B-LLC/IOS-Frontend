//
//  PlannerDaySchedule.swift
//  IOS Frontend
//
//  The selected day as an hour-by-hour schedule.
//

import SwiftUI

/// The day laid out against the clock: an hour column down the left, and each
/// timed entry sitting at the hour it happens.
///
/// Entries with no time are not placed here. Putting them at an arbitrary hour
/// would say something the user never said, so they are listed underneath.
struct PlannerDaySchedule: View {
    @Environment(PlannerStore.self) private var store
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let onSelect: (PlannerEntry) -> Void
    /// Where to send someone who says they have not trained yet. Nil leaves
    /// the tick as a plain tick, with no offer to open anything.
    var onOpenWorkout: ((Weekday) -> Void)?

    /// The workout tick waiting on an answer, if one is.
    @State private var confirming: PlannerEntry?

    /// Spelled out rather than left to the memberwise one, which a private
    /// stored property takes out of reach of the other file that builds this.
    init(
        onSelect: @escaping (PlannerEntry) -> Void,
        onOpenWorkout: ((Weekday) -> Void)? = nil
    ) {
        self.onSelect = onSelect
        self.onOpenWorkout = onOpenWorkout
    }

    /// The height of one hour. Blocks are a fixed height rather than sized to
    /// a duration: an entry records when it starts and nothing about how long
    /// it runs, and inventing a length would be inventing data.
    private let hourHeight: CGFloat = 58
    private let gutterWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !timed.isEmpty {
                grid
            }
            if !untimed.isEmpty {
                anytimeSection
            }
            if timed.isEmpty && untimed.isEmpty {
                emptyDay
            }
        }
        .plannerWorkoutCompletionDialog(
            entry: $confirming,
            openableDay: { PlannerWorkoutCompletion.openableDay($0, workouts: workouts) },
            onOpen: { onOpenWorkout?($0) },
            onTickAnyway: { store.setComplete($0, true) }
        )
    }

    // MARK: - The hour grid

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            hourLines
            ForEach(timed) { entry in
                block(entry)
                    .padding(.leading, gutterWidth)
                    .offset(y: offset(for: entry))
            }
        }
        .frame(height: CGFloat(hours.count) * hourHeight)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(Self.label(for: hour))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .frame(width: gutterWidth - 8, alignment: .leading)
                    VerticalDashedRule()
                        .stroke(
                            timeOfDay.canvasSecondaryText.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                        )
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private func block(_ entry: PlannerEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .strikethrough(entry.isComplete, color: timeOfDay.canvasSecondaryText)
                    .lineLimit(1)
                Text(subtitle(entry))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if entry.isCompletable {
                completionToggle(entry, onCanvas: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(height: hourHeight - 8, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Heavier on a dark canvas, where a wash this faint disappears into
        // the gradient and takes the text with it.
        .background(
            entry.category.tint.opacity(blockOpacity(entry)),
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(entry.category.tint.opacity(0.45), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(entry) }
    }

    // MARK: - Anytime

    private var anytimeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ANYTIME")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .padding(.leading, 2)

            ForEach(untimed) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.category.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.category.tint)
                        .frame(width: 28, height: 28)
                        .background(
                            entry.category.tint.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(timeOfDay.primaryText)
                            .strikethrough(entry.isComplete, color: timeOfDay.secondaryText)
                            .lineLimit(1)
                        Text(subtitle(entry))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if entry.isCompletable {
                        completionToggle(entry, onCanvas: false)
                    }
                }
                .padding(.vertical, 2)
                .repbaseCard(contentPadding: 11, cornerRadius: 15)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(entry) }
            }
        }
    }

    private var emptyDay: some View {
        Text("Nothing planned for this day yet.")
            .font(.footnote)
            .foregroundStyle(timeOfDay.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .accessibilityLabel("Nothing planned for this day yet")
    }

    // MARK: - Pieces

    private func blockOpacity(_ entry: PlannerEntry) -> Double {
        if entry.isComplete { return timeOfDay.hasDarkCanvas ? 0.18 : 0.10 }
        return timeOfDay.hasDarkCanvas ? 0.38 : 0.22
    }

    /// `onCanvas` because the same control appears both on a block, drawn
    /// straight on the gradient, and inside an Anytime card, which stays light
    /// at every hour.
    private func completionToggle(_ entry: PlannerEntry, onCanvas: Bool) -> some View {
        Button {
            // A planned workout that has not been trained asks first: the tick
            // alone records no session, so nothing about the workout is kept.
            if onOpenWorkout != nil,
               PlannerWorkoutCompletion.needsConfirmation(entry, workouts: workouts) {
                confirming = entry
            } else {
                store.setComplete(entry, !entry.isComplete)
            }
        } label: {
            Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(
                    entry.isComplete
                        ? Color(hex: 0x3FAE6A)
                        : (onCanvas ? timeOfDay.canvasSecondaryText : timeOfDay.secondaryText)
                            .opacity(0.6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isComplete ? "Mark not done" : "Mark done")
    }

    private func subtitle(_ entry: PlannerEntry) -> String {
        var parts: [String] = []
        // First, because it is the reason this row sits where it does. The
        // Anytime list arrives in server order, which is already priority-first.
        if let badge = entry.priority.badge { parts.append(badge.capitalized) }
        parts.append(entry.category.title)
        if let time = entry.displayTime { parts.append(time) }
        if entry.kind == .event { parts.append("Event") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data

    private var timed: [PlannerEntry] { store.timedEntries(on: store.selectedDate) }
    private var untimed: [PlannerEntry] { store.untimedEntries(on: store.selectedDate) }

    /// One row per hour, from an hour before the first entry to an hour after
    /// the last, so nothing sits flush against the edge.
    private var hours: [Int] {
        let stamps = timed.compactMap { Self.hour(from: $0.time) }
        guard let earliest = stamps.min(), let latest = stamps.max() else { return [] }
        return Array(max(0, earliest - 1)...min(23, latest + 1))
    }

    /// Where a block sits, from the top of the grid: whole hours plus the
    /// minutes into its own hour.
    private func offset(for entry: PlannerEntry) -> CGFloat {
        guard let first = hours.first,
              let hour = Self.hour(from: entry.time) else { return 0 }
        let minute = Self.minute(from: entry.time)
        return CGFloat(hour - first) * hourHeight
            + CGFloat(minute) / 60 * hourHeight
    }

    private static func hour(from time: String?) -> Int? {
        guard let time, let value = Int(time.prefix(2)) else { return nil }
        return value
    }

    private static func minute(from time: String?) -> Int {
        guard let time, time.count >= 5,
              let value = Int(time.dropFirst(3).prefix(2)) else { return 0 }
        return value
    }

    /// "9 AM", "12 PM", matching the clock rather than the API's 24-hour times.
    private static func label(for hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let shown = hour % 12 == 0 ? 12 : hour % 12
        return "\(shown) \(suffix)"
    }
}

/// A horizontal rule, drawn as a path so it can be dashed.
private struct VerticalDashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
