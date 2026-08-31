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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSelect: (PlannerEntry) -> Void
    /// Where to send someone who says they have not trained yet. Nil leaves
    /// the tick as a plain tick, with no offer to open anything.
    var onOpenWorkout: ((Weekday) -> Void)?
    var recentlyCompletedEntryID: PlannerEntry.ID?
    var dayIsCleared = false

    /// The workout tick waiting on an answer, if one is.
    @State private var confirming: PlannerEntry?

    /// Spelled out rather than left to the memberwise one, which a private
    /// stored property takes out of reach of the other file that builds this.
    init(
        onSelect: @escaping (PlannerEntry) -> Void,
        onOpenWorkout: ((Weekday) -> Void)? = nil,
        recentlyCompletedEntryID: PlannerEntry.ID? = nil,
        dayIsCleared: Bool = false
    ) {
        self.onSelect = onSelect
        self.onOpenWorkout = onOpenWorkout
        self.recentlyCompletedEntryID = recentlyCompletedEntryID
        self.dayIsCleared = dayIsCleared
    }

    /// The height of one hour.
    ///
    /// Blocks used to be a fixed hour tall, because an entry recorded when it
    /// started and nothing about how long it ran — and inventing a length
    /// would have been inventing data. An entry can now say, so a block is
    /// drawn at the size of the time it actually takes.
    private let hourHeight: CGFloat = 58
    private let gutterWidth: CGFloat = 52

    /// Room for both lines and the padding the design uses everywhere else.
    /// A block of an hour or more gets this.
    private static let roomyBlockHeight: CGFloat = 48

    /// Room for both lines if the padding gives way. Three quarters of an hour
    /// lands here, and losing the line that says when a meeting ends would be
    /// a poor trade for four points of margin.
    private static let snugBlockHeight: CGFloat = 34

    /// The floor. A quarter of an hour is fourteen points at this scale, which
    /// is a stripe, not something with a name on it.
    private static let minimumBlockHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dayIsCleared {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(RepbasePalette.sage)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Day cleared")
                            .font(.community(size: 13, weight: .bold))
                        Text("Everything you planned is complete.")
                            .font(.community(size: 10, weight: .medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }
                .foregroundStyle(timeOfDay.primaryText)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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
                        .font(.community(size: 11, weight: .medium))
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
        let height = blockHeight(entry)
        let isRoomy = height >= Self.roomyBlockHeight
        let showsSubtitle = height >= Self.snugBlockHeight

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: isRoomy ? 2 : 0) {
                Text(entry.title)
                    .font(.community(size: 13, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .strikethrough(entry.isComplete, color: timeOfDay.canvasSecondaryText)
                    .lineLimit(1)
                if showsSubtitle {
                    Text(subtitle(entry))
                        .font(.community(size: 10, weight: .medium))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if entry.isCompletable {
                completionToggle(entry, onCanvas: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isRoomy ? 9 : 2)
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Heavier on a dark canvas, where a wash this faint disappears into
        // the gradient and takes the text with it.
        .background(
            blockTint(entry),

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
                .font(.community(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .padding(.leading, 2)

            ForEach(untimed) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.category.symbolName)
                        .font(.community(size: 11, weight: .semibold))
                        .foregroundStyle(entry.category.tint)
                        .frame(width: 28, height: 28)
                        .background(
                            entry.category.tint.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(.community(size: 13, weight: .semibold))
                            .foregroundStyle(timeOfDay.primaryText)
                            .strikethrough(entry.isComplete, color: timeOfDay.secondaryText)
                            .lineLimit(1)
                        Text(subtitle(entry))
                            .font(.community(size: 9, weight: .medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if entry.isCompletable {
                        completionToggle(entry, onCanvas: false)
                    }
                }
                .padding(.vertical, 2)
                .repbaseCard(contentPadding: 11, cornerRadius: 15)
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(RepbasePalette.sage.opacity(entry.id == recentlyCompletedEntryID ? 0.16 : 0))
                        .allowsHitTesting(false)
                }
                .scaleEffect(entry.id == recentlyCompletedEntryID ? 1.015 : 1)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.36, dampingFraction: 0.74),
                    value: recentlyCompletedEntryID
                )
                .contentShape(Rectangle())
                .onTapGesture { onSelect(entry) }
            }
        }
    }

    private var emptyDay: some View {
        Text("Nothing planned for this day yet.")
            .font(.community(.footnote))
            .foregroundStyle(timeOfDay.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .accessibilityLabel("Nothing planned for this day yet")
    }

    // MARK: - Pieces

    /// The wash behind a planned block, at the weight its state calls for.
    ///
    /// Returns the colour rather than the opacity so the appearance decision
    /// travels inside a dynamic colour instead of being made while this body
    /// runs. The category tint is fixed, so it is safe to wrap.
    private func blockTint(_ entry: PlannerEntry) -> Color {
        let tint = entry.category.tint
        return entry.isComplete
            ? .repbaseDynamic(light: tint.opacity(0.10), dark: tint.opacity(0.18))
            : .repbaseDynamic(light: tint.opacity(0.22), dark: tint.opacity(0.38))
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
                .font(.community(size: 17, weight: .regular))
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
        if let when = entry.displayTimeRange { parts.append(when) }
        if entry.kind == .event { parts.append("Event") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data

    private var timed: [PlannerEntry] { store.timedEntries(on: store.selectedDate) }
    private var untimed: [PlannerEntry] { store.untimedEntries(on: store.selectedDate) }

    /// One row per hour, from an hour before the first entry to an hour after
    /// the last, so nothing sits flush against the edge.
    ///
    /// The far end is measured from where blocks *finish*, not where they
    /// start: a two-hour block beginning in the last hour of the grid would
    /// otherwise be drawn off the bottom of it.
    private var hours: [Int] {
        let starts = timed.compactMap { Self.hour(from: $0.time) }
        let finishes = timed.compactMap { entry -> Int? in
            guard let start = PlannerDuration.minutesPastMidnight(entry.time) else {
                return nil
            }
            let end = start + (entry.durationMinutes ?? 60)
            // The hour holding its last minute, so a block ending exactly on
            // the hour does not claim the one after it.
            return min(23, max(0, (end - 1) / 60))
        }
        guard let earliest = starts.min(), let latest = finishes.max() else { return [] }
        return Array(max(0, earliest - 1)...min(23, latest + 1))
    }

    /// How tall a block is drawn: the time it actually takes.
    ///
    /// An hour when nothing said how long, which is what every block used to
    /// be. Clamped to the bottom of the grid, because a block running past
    /// midnight has nowhere further to go on this day — the range in the
    /// subtitle still tells the truth about when it ends.
    private func blockHeight(_ entry: PlannerEntry) -> CGFloat {
        let minutes = entry.durationMinutes ?? 60
        var drawn = minutes
        if let start = PlannerDuration.minutesPastMidnight(entry.time),
           let first = hours.first {
            drawn = min(minutes, (hours.count * 60) - (start - first * 60))
        }
        return max(
            Self.minimumBlockHeight,
            CGFloat(drawn) / 60 * hourHeight - 8
        )
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
