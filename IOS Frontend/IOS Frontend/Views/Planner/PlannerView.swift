//
//  PlannerView.swift
//  IOS Frontend
//
//  The planner: the week in focus, the day against the clock, and what is
//  overdue or coming.
//

import SwiftUI

struct PlannerView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(WorkoutStore.self) private var workoutStore

    @State private var editor: PlannerEntryEditorView.Mode?
    @State private var categoryFilter: PlannerCategory?
    /// The approved calendar opens on the month; the compact week remains one
    /// tap away when the user wants a tighter planning view.
    @State private var isMonthShown = true
    @State private var openingDay: Weekday?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CALENDAR")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(timeOfDay.accent)
                            Text(store.visibleMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.system(size: 32, weight: .bold))
                                .tracking(-0.7)
                                .foregroundStyle(timeOfDay.canvasPrimaryText)
                        }
                        Spacer(minLength: 0)
                    }

                    if isMonthShown {
                        PlannerMonthCalendar {
                            withAnimation(.easeOut(duration: 0.2)) { isMonthShown = false }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !isMonthShown {
                        PlannerWeekStrip(
                            categoryFilter: $categoryFilter,
                            isMonthShown: isMonthShown,
                            onToggleMonth: {
                                withAnimation(.easeOut(duration: 0.2)) { isMonthShown.toggle() }
                            }
                        )
                    }

                    addButtons(timeOfDay: timeOfDay)
                    daySection(timeOfDay: timeOfDay)
                    pastDueSection(timeOfDay: timeOfDay)
                    upcomingSection(timeOfDay: timeOfDay)

                    if let error = store.persistenceError {
                        errorCard(error, timeOfDay: timeOfDay)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 16)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
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
                workouts: workoutStore.knownWorkouts,
                onSaved: { store.save($0) },
                onDeleted: { store.delete($0) }
            )
        }
        .navigationDestination(item: $openingDay) { day in
            DayWorkoutView(day: day)
        }
        // Selecting another day can only narrow what is on screen; a filter
        // left over from yesterday would read as an empty day.
        .onChange(of: store.selectedDate) { categoryFilter = nil }
    }

    // MARK: - Adding

    /// Two peers, not a primary and a secondary.
    ///
    /// A filled button beside a plain one says one of them is the main thing to
    /// do. Adding a task and adding an event are the same size of decision, so
    /// they carry the same weight and differ by hue instead: the accent for a
    /// task, sage for an event, both from the app's own palette.
    private func addButtons(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 10) {
            addButton(
                "Add Task",
                systemImage: "checkmark.circle",
                kind: .task,
                fill: timeOfDay.accent
            )
            addButton(
                "Add Event",
                systemImage: "calendar",
                kind: .event,
                fill: RepbasePalette.sage
            )
        }
    }

    private func addButton(
        _ title: String,
        systemImage: String,
        kind: PlannerKind,
        fill: Color
    ) -> some View {
        Button {
            // The day picked on the calendar is carried into the editor, so a
            // task planned for a Thursday is not silently filed under today.
            editor = .create(kind, store.selectedDate)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RepbasePalette.paper)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    fill,
                    in: RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius)
                )
        }
        .buttonStyle(.plain)
        .disabled(!store.isEditingEnabled)
        .opacity(store.isEditingEnabled ? 1 : 0.5)
    }

    // MARK: - The day

    private func daySection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Text(store.selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.footnote)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                Spacer(minLength: 0)
            }

            if let reason = store.editingBlockedReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if categoryFilter == nil {
                PlannerDaySchedule(
                    onSelect: { editor = .edit($0) },
                    onOpenWorkout: { openingDay = $0 }
                )
            } else {
                filteredList(timeOfDay: timeOfDay)
            }
        }
    }

    /// A filtered day is a plain list, not a schedule.
    ///
    /// A grid with one block in it and eleven empty hours around it says the
    /// day is mostly empty, when in fact the rest of it was filtered out.
    private func filteredList(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 8) {
            if filtered.isEmpty {
                Text("Nothing in this category today.")
                    .font(.footnote)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .repbaseCard(contentPadding: 12, cornerRadius: 18)
            } else {
                ForEach(filtered) { entry in
                    PlannerEntryRow(
                        entry: entry,
                        showsDate: false,
                        onEdit: { editor = .edit(entry) },
                        onOpenWorkout: { openingDay = $0 }
                    )
                }
            }
        }
    }

    private var filtered: [PlannerEntry] {
        guard let categoryFilter else { return store.entries(on: store.selectedDate) }
        return store.entries(on: store.selectedDate)
            .filter { $0.category == categoryFilter }
    }

    // MARK: - Past due

    @ViewBuilder
    private func pastDueSection(timeOfDay: HomeTimeOfDay) -> some View {
        if !store.pastDue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(
                    "Past due",
                    detail: "\(store.pastDue.count)",
                    tint: Color(hex: 0xD8557A),
                    timeOfDay: timeOfDay
                )
                ForEach(store.pastDue) { entry in
                    PlannerEntryRow(
                        entry: entry,
                        showsDate: true,
                        onEdit: { editor = .edit(entry) },
                        onOpenWorkout: { openingDay = $0 }
                    )
                }
            }
        }
    }

    // MARK: - Upcoming

    @ViewBuilder
    private func upcomingSection(timeOfDay: HomeTimeOfDay) -> some View {
        if !store.upcomingEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(
                    "Upcoming events",
                    detail: "next \(PlannerStore.upcomingHorizonDays) days",
                    tint: timeOfDay.accent,
                    timeOfDay: timeOfDay
                )
                ForEach(store.upcomingEvents.prefix(6)) { entry in
                    PlannerEntryRow(
                        entry: entry,
                        showsDate: true,
                        onEdit: { editor = .edit(entry) },
                        onOpenWorkout: { openingDay = $0 }
                    )
                }
                if store.upcomingEvents.count > 6 {
                    Text("+\(store.upcomingEvents.count - 6) more")
                        .font(.caption2)
                        .foregroundStyle(timeOfDay.secondaryText)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        detail: String,
        tint: Color,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer(minLength: 0)
            Text(detail)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .padding(.top, 4)
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

/// One task or event as a row, for the lists that are not a schedule.
struct PlannerEntryRow: View {
    @Environment(PlannerStore.self) private var store
    @Environment(WorkoutStore.self) private var workouts
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let entry: PlannerEntry
    /// Shown for entries that are not on the day being looked at, where "when"
    /// is the whole point.
    var showsDate: Bool = false
    let onEdit: () -> Void
    var onOpenWorkout: ((Weekday) -> Void)?

    @State private var confirming: PlannerEntry?

    var body: some View {
        HStack(spacing: 11) {
            categoryBadge

            VStack(alignment: .leading, spacing: 2) {
                // The line is drawn rather than switched on, so ticking a task
                // off reads as crossing it out. `.strikethrough` appears whole
                // in one frame, which a fade straight afterwards turns into a
                // blink.
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)
                    .overlay {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(timeOfDay.secondaryText)
                                .frame(width: proxy.size.width, height: 1.2)
                                .scaleEffect(
                                    x: entry.isComplete ? 1 : 0,
                                    anchor: .leading
                                )
                                .position(
                                    x: proxy.size.width / 2,
                                    y: proxy.size.height / 2
                                )
                        }
                    }
                    .animation(.easeOut(duration: 0.28), value: entry.isComplete)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if entry.isCompletable {
                completionToggle
            }
        }
        .opacity(entry.isComplete ? 0.6 : 1)
        .padding(.vertical, 2)
        .repbaseCard(contentPadding: 12, cornerRadius: 16)
        .plannerWorkoutCompletionDialog(
            entry: $confirming,
            openableDay: { PlannerWorkoutCompletion.openableDay($0, workouts: workouts) },
            onOpen: { onOpenWorkout?($0) },
            onTickAnyway: { store.setComplete($0, true) }
        )
        // Fades and collapses when it leaves, which is what a finished overdue
        // task does once its line has been drawn.
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
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

    private var subtitle: String {
        var parts: [String] = []
        if showsDate, let day = Self.date(from: entry.date) {
            parts.append(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        }
        parts.append(entry.category.title)
        if let time = entry.displayTime { parts.append(time) }
        if entry.kind == .event { parts.append("Event") }
        return parts.joined(separator: " · ")
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
            if onOpenWorkout != nil,
               PlannerWorkoutCompletion.needsConfirmation(entry, workouts: workouts) {
                confirming = entry
            } else {
                store.setComplete(entry, !entry.isComplete)
            }
        } label: {
            Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    entry.isComplete
                        ? Color(hex: 0x3FAE6A)
                        : timeOfDay.secondaryText.opacity(0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isComplete ? "Mark not done" : "Mark done")
    }

    private static func date(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }
}
