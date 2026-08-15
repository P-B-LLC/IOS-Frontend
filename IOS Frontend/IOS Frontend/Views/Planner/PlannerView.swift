//
//  PlannerView.swift
//  IOS Frontend
//
//  The planner: a month to choose from, the week in focus, and the day's list.
//

import SwiftUI

struct PlannerView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(WorkoutStore.self) private var workoutStore

    @State private var editor: PlannerEntryEditorView.Mode?
    @State private var categoryFilter: PlannerCategory?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(spacing: 14) {
                    PlannerMonthCalendar()
                    PlannerWeekStrip(categoryFilter: $categoryFilter)
                    addButtons(timeOfDay: timeOfDay)
                    dayList(timeOfDay: timeOfDay)

                    if let error = store.persistenceError {
                        errorCard(error, timeOfDay: timeOfDay)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Planner")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
            .overlay {
                if store.isLoading {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .sheet(item: $editor) { mode in
            PlannerEntryEditorView(
                mode: mode,
                workouts: workoutStore.knownWorkouts
            ) { entry in
                store.save(entry)
            }
        }
        // Selecting another day can only narrow what is on screen; a filter
        // left over from yesterday would read as an empty day.
        .onChange(of: store.selectedDate) { categoryFilter = nil }
    }

    // MARK: - Adding

    private func addButtons(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 10) {
            addButton(
                "Add Task",
                systemImage: "checkmark.circle",
                kind: .task,
                timeOfDay: timeOfDay,
                isProminent: true
            )
            addButton(
                "Add Event",
                systemImage: "calendar",
                kind: .event,
                timeOfDay: timeOfDay,
                isProminent: false
            )
        }
    }

    private func addButton(
        _ title: String,
        systemImage: String,
        kind: PlannerKind,
        timeOfDay: HomeTimeOfDay,
        isProminent: Bool
    ) -> some View {
        Button {
            // The day picked on the calendar is carried into the editor, so a
            // task planned for a Thursday is not silently filed under today.
            editor = .create(kind, store.selectedDate)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isProminent ? Color(hex: 0xFFFFFF) : timeOfDay.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isProminent ? timeOfDay.accent : timeOfDay.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .overlay {
                    if !isProminent {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(timeOfDay.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!store.isEditingEnabled)
        .opacity(store.isEditingEnabled ? 1 : 0.5)
    }

    // MARK: - The day

    private func dayList(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                Text(store.selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.footnote)
                    .foregroundStyle(timeOfDay.secondaryText)
                Spacer(minLength: 0)
            }

            // On its own line: this message runs to two lines on a narrow
            // phone, and beside the date it collided with it.
            if let reason = store.editingBlockedReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if visibleEntries.isEmpty {
                emptyDay(timeOfDay: timeOfDay)
            } else {
                ForEach(visibleEntries) { entry in
                    PlannerEntryRow(entry: entry) {
                        editor = .edit(entry)
                    }
                }
            }
        }
    }

    private func emptyDay(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 7) {
            Image(systemName: categoryFilter == nil ? "checklist" : "line.3.horizontal.decrease")
                .font(.title3)
                .foregroundStyle(timeOfDay.accent)
            Text(
                categoryFilter == nil
                    ? "Nothing planned for this day yet."
                    : "Nothing in this category today."
            )
            .font(.footnote)
            .foregroundStyle(timeOfDay.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .repbaseCard(contentPadding: 12, cornerRadius: 18)
    }

    private var visibleEntries: [PlannerEntry] {
        let entries = store.entries(on: store.selectedDate)
        guard let categoryFilter else { return entries }
        return entries.filter { $0.category == categoryFilter }
    }

    private func errorCard(_ message: String, timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(timeOfDay.accent)
            VStack(alignment: .leading, spacing: 7) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(timeOfDay.primaryText)
                Button("Retry") { store.retry() }
                    .font(.footnote.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(timeOfDay.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One task or event in the day's list.
private struct PlannerEntryRow: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let entry: PlannerEntry
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            categoryBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .strikethrough(entry.isComplete, color: timeOfDay.secondaryText)
                HStack(spacing: 5) {
                    Text(entry.category.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(entry.category.tint)
                    if let time = entry.displayTime {
                        Text(time)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                    if entry.kind == .event {
                        Text("Event")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }
            }

            Spacer(minLength: 0)

            if entry.isCompletable {
                completionToggle
            }
        }
        .opacity(entry.isComplete ? 0.6 : 1)
        .padding(.vertical, 2)
        .repbaseCard(contentPadding: 12, cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        // Long press rather than swipe: these rows sit in a scroll view, not a
        // List, where swipe actions would never fire.
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(entry)
            }
        }
    }

    private var categoryBadge: some View {
        Image(systemName: entry.category.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(entry.category.tint)
            .frame(width: 34, height: 34)
            .background(entry.category.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
    }

    private var completionToggle: some View {
        Button {
            store.setComplete(entry, !entry.isComplete)
        } label: {
            Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(entry.isComplete ? Color(hex: 0x3FAE6A) : timeOfDay.secondaryText.opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isComplete ? "Mark not done" : "Mark done")
    }
}
