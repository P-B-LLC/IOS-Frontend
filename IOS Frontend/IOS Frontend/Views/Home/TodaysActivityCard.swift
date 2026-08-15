//
//  TodaysActivityCard.swift
//  IOS Frontend
//
//  Today's tasks on the home page, tickable without leaving it.
//

import SwiftUI

/// Today's tasks as a timeline, in the order they come due.
///
/// Tasks only. Events live in `TodaysEventsCard` beside the calendar, because
/// an event is not something to tick off and a checkbox next to a birthday
/// reads as a chore.
struct TodaysActivityCard: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    /// How many rows fit before the card starts dominating the page. The rest
    /// are reported as a count rather than silently dropped.
    private let visibleLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if tasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                        row(task, isLast: index == shown.count - 1)
                    }
                }
                if tasks.count > visibleLimit {
                    Text("+\(tasks.count - visibleLimit) more in the planner")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .padding(.leading, 30)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
        .shadow(color: timeOfDay.shadow, radius: 12, x: 5, y: 8)
    }

    // MARK: - Header

    private var header: some View {
        NavigationLink {
            PlannerView()
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Activity")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.primaryText)
                Spacer(minLength: 6)
                if !tasks.isEmpty {
                    Text("\(done) of \(tasks.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the planner")
    }

    // MARK: - Rows

    private func row(_ task: PlannerEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            timelineColumn(task, isLast: isLast)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .strikethrough(task.isComplete, color: timeOfDay.secondaryText)
                    .lineLimit(1)
                Text(subtitle(task))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .lineLimit(1)
            }
            .padding(.top, 1)

            Spacer(minLength: 6)

            trailing(task)
                .padding(.top, 2)
        }
        .padding(.bottom, isLast ? 0 : 14)
        .opacity(task.isComplete ? 0.55 : 1)
    }

    /// The dot doubles as the checkbox: it is where the eye already is, and it
    /// is what the row is about.
    private func timelineColumn(_ task: PlannerEntry, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                store.setComplete(task, !task.isComplete)
            } label: {
                ZStack {
                    Circle()
                        .fill(task.isComplete ? Color(hex: 0x3FAE6A) : timeOfDay.surface)
                        .frame(width: 18, height: 18)
                    Circle()
                        .strokeBorder(
                            task.isComplete ? Color.clear : task.category.tint,
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)
                    if task.isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.isConnected)
            .accessibilityLabel(
                task.isComplete ? "Mark \(task.title) not done" : "Mark \(task.title) done"
            )

            if !isLast {
                VerticalDashedLine()
                    .stroke(
                        timeOfDay.secondaryText.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .frame(width: 30)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 30)
    }

    @ViewBuilder
    private func trailing(_ task: PlannerEntry) -> some View {
        if task.id == dueNow?.id {
            Text("Now")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: 0x0E2C18))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(hex: 0x53D276), in: Capsule())
        } else if let time = task.displayTime {
            Text(time)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private func subtitle(_ task: PlannerEntry) -> String {
        if let name = task.workoutName, task.category == .workout {
            return "\(task.category.title) · \(name)"
        }
        return task.category.title
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 30, height: 30)
                .background(timeOfDay.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            Text("Nothing to do today. Add a task in the planner.")
                .font(.system(size: 12))
                .foregroundStyle(timeOfDay.secondaryText)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Data

    /// Today's tasks. Unfinished first, so the card answers "what is left"
    /// before it answers "what happened", then in the order they come due.
    private var tasks: [PlannerEntry] {
        store.entries(on: Date())
            .filter(\.isCompletable)
            .sorted { lhs, rhs in
                if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
                return (lhs.time ?? "") < (rhs.time ?? "")
            }
    }

    private var shown: [PlannerEntry] { Array(tasks.prefix(visibleLimit)) }

    private var done: Int { tasks.filter(\.isComplete).count }

    /// The task that should be happening: the latest one whose time has come
    /// and which is still unfinished.
    ///
    /// Only one carries the pill. Marking every overdue task "Now" would say
    /// four things are happening at once, and none of them would stand out.
    private var dueNow: PlannerEntry? {
        let now = Self.currentTimeString()
        return tasks
            .filter { !$0.isComplete }
            .compactMap { task -> (PlannerEntry, String)? in
                guard let time = task.time, time <= now else { return nil }
                return (task, time)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// `HH:mm:ss`, to compare against the API's literal times without building
    /// a Date for each row.
    private static func currentTimeString() -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d:59", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// A vertical line down the middle, for the dashes between timeline dots.
private struct VerticalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
