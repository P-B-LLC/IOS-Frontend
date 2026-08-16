//
//  TodaysTasksList.swift
//  IOS Frontend
//
//  Today's to-do list at the foot of the home page.
//

import SwiftUI

/// Today's tasks as a plain list, not a card.
///
/// Deliberately without the surface, border and shadow the widgets above it
/// carry: a to-do list is something to work down, and boxing it made it read
/// as another summary tile.
///
/// Tasks only. Events belong to `HomeCalendarCard`, where they are not offered
/// a checkbox.
struct TodaysTasksList: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    @State private var editor: PlannerEntryEditorView.Mode?

    /// How many rows fit before the list takes over the page. The rest are
    /// reported as a count rather than silently dropped.
    private let visibleLimit = 5

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            dayColumn

            Rectangle()
                .fill(timeOfDay.canvasBorder)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                header
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { rowDivider }
                        row(task)
                    }
                    if tasks.count > visibleLimit {
                        rowDivider
                        Text("+\(tasks.count - visibleLimit) more in the planner")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                            .padding(.vertical, 11)
                    }
                }
                addRow
            }
        }
        .sheet(item: $editor) { mode in
            PlannerEntryEditorView(
                mode: mode,
                onSaved: { store.save($0) },
                onDeleted: { store.delete($0) }
            )
        }
    }

    // MARK: - The date down the left

    private var dayColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Calendar.current.component(.day, from: Date()))")
                .font(.system(size: 34, weight: .light, design: .serif))
                .italic()
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(Date().formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .frame(width: 38, alignment: .trailing)
        .padding(.top, 2)
    }

    // MARK: - Rows

    private var header: some View {
        NavigationLink {
            PlannerView()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("To-do")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer(minLength: 0)
                if !tasks.isEmpty {
                    Text("\(done) of \(tasks.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the planner")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(timeOfDay.canvasBorder)
            .frame(height: 1)
    }

    private func row(_ task: PlannerEntry) -> some View {
        HStack(spacing: 10) {
            checkbox(task)

            HStack(spacing: 6) {
                timeLabel(task)
                Text(task.title)
                    .font(.system(size: 13, weight: isDue(task) ? .semibold : .medium))
                    .foregroundStyle(
                        task.isComplete ? timeOfDay.canvasSecondaryText : timeOfDay.canvasPrimaryText
                    )
                    .strikethrough(task.isComplete, color: timeOfDay.canvasSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: task.category.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(task.category.tint.opacity(task.isComplete ? 0.4 : 1))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editor = .edit(task) }
    }

    private func checkbox(_ task: PlannerEntry) -> some View {
        Button {
            store.setComplete(task, !task.isComplete)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        task.isComplete ? Color.clear : timeOfDay.canvasSecondaryText.opacity(0.55),
                        lineWidth: 1.5
                    )
                    .frame(width: 17, height: 17)
                if task.isComplete {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: 0x3FAE6A))
                        .frame(width: 17, height: 17)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.isConnected)
        .accessibilityLabel(
            task.isComplete ? "Mark \(task.title) not done" : "Mark \(task.title) done"
        )
    }

    /// The task that is due wears its time filled in, the way the design marks
    /// the thing you should be on.
    ///
    /// Filled rather than merely tinted: this list has no card behind it, so it
    /// sits straight on the canvas, and accent-coloured text on the dusk
    /// palette was almost unreadable. White on the accent holds up on all four.
    @ViewBuilder
    private func timeLabel(_ task: PlannerEntry) -> some View {
        if isDue(task) {
            Text(task.displayTime ?? "Now")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFFFFF))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(timeOfDay.accent, in: Capsule())
        } else if let time = task.displayTime {
            Text(time)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    task.isComplete ? timeOfDay.canvasSecondaryText : timeOfDay.canvasPrimaryText
                )
        }
    }

    /// Only one task is ever due: marking every overdue one would say four
    /// things are happening at once and none would stand out.
    private func isDue(_ task: PlannerEntry) -> Bool {
        task.id == dueNow?.id
    }

    private var addRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                editor = .create(.task, Date())
            } label: {
                // Outlined rather than bare: with no card behind the list, a
                // plain glyph in the secondary colour all but disappeared on
                // the warmer palettes.
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().strokeBorder(timeOfDay.canvasBorder, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.isEditingEnabled)
            .accessibilityLabel("Add a task")
        }
        .padding(.top, 2)
    }

    private var emptyState: some View {
        Text("Nothing to do today.")
            .font(.system(size: 13))
            .foregroundStyle(timeOfDay.canvasSecondaryText)
            .padding(.vertical, 11)
    }

    // MARK: - Data

    /// Unfinished first, so the list answers "what is left" before it answers
    /// "what happened", then in the order they come due.
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

    /// The latest task whose time has come and which is still unfinished.
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
