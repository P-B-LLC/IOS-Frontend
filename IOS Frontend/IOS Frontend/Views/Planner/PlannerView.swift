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
    @Environment(CycleStore.self) private var cycleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set when this was pushed rather than opened as its own tab. The page
    /// hides the navigation bar, which on a pushed copy removed the only way
    /// back, so it has to draw its own.
    var showsBackButton = false

    @State private var editor: PlannerEntryEditorView.Mode?
    @State private var categoryFilter: PlannerCategory?
    @State private var isMonthShown = false
    @State private var showsCompleted = false
    @State private var openingDay: Weekday?
    @State private var handledCompletionID: UUID?
    @State private var completedEntryID: PlannerEntry.ID?
    @State private var completionPulse = false
    @State private var completionMessage: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    RytivoBrandLockup(size: 24)
                    Spacer()
                    Text("Planner")
                        .font(.community(.title3, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                }

                HStack(alignment: .bottom) {
                    if showsBackButton {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.community(size: 17, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .accessibilityLabel("Back")
                        .padding(.trailing, 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Make room for your day.")
                            .font(.community(.title2, weight: .bold))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                        Text(store.selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }
                    Spacer(minLength: 0)
                }

                PlannerWeekStrip(
                    categoryFilter: $categoryFilter,
                    onToggleMonth: { isMonthShown = true }
                )

                addButtons(timeOfDay: timeOfDay)
                daySection(timeOfDay: timeOfDay)
                rotationStrip(timeOfDay: timeOfDay)
                pastDueSection(timeOfDay: timeOfDay)
                upcomingSection(timeOfDay: timeOfDay)

                if let error = store.persistenceError {
                    errorCard(error, timeOfDay: timeOfDay)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .minimizesBottomBarOnScroll()
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
        .sheet(isPresented: $isMonthShown, onDismiss: {
            // Browsing a month doesn't change the selected day. Restore its
            // data when the sheet is dismissed without choosing another day.
            store.select(store.selectedDate)
        }) {
            monthOverview(timeOfDay: timeOfDay)
        }
        .overlay(alignment: .top) {
            if let completionMessage {
                completionToast(completionMessage, timeOfDay: timeOfDay)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fullScreenCover(item: $editor) { mode in
            PlannerEntryEditorView(
                mode: mode,
                workouts: workoutStore.knownWorkouts,
                onSaved: { entry, steps in
                    await store.saveReportingFailure(entry, steps: steps)
                },
                onDeleted: { entry, endsRepeat in
                    store.delete(entry, endsRepeat: endsRepeat)
                }
            )
        }
        .navigationDestination(item: $openingDay) { day in
            DayWorkoutView(day: day)
        }
        // Selecting another day can only narrow what is on screen; a filter
        // left over from yesterday would read as an empty day.
        .onChange(of: store.selectedDate) {
            categoryFilter = nil
            showsCompleted = false
        }
        .onChange(of: store.latestCompletionEvent) { _, event in
            handleCompletion(event)
        }
        .onDisappear {
            feedbackTask?.cancel()
            feedbackTask = nil
            completionMessage = nil
            completedEntryID = nil
        }
    }

    // MARK: - Adding

    private func addButtons(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 16) {
            addButton(
                "Add Task",
                systemImage: "plus",
                kind: .task,
                primary: true,
                timeOfDay: timeOfDay
            )
            addButton(
                "Add Event",
                systemImage: "plus",
                kind: .event,
                primary: false,
                timeOfDay: timeOfDay
            )
        }
    }

    private func addButton(
        _ title: String,
        systemImage: String,
        kind: PlannerKind,
        primary: Bool,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        Button {
            // The day picked on the calendar is carried into the editor, so a
            // task planned for a Thursday is not silently filed under today.
            editor = .create(kind, store.selectedDate)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.community(size: 13, weight: .semibold))
                .foregroundStyle(primary ? timeOfDay.onPrimaryAction : timeOfDay.canvasPrimaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    primary ? timeOfDay.primaryActionSurface : timeOfDay.surfaceRaised,
                    in: Capsule()
                )
                .overlay { Capsule().strokeBorder(primary ? Color.clear : timeOfDay.canvasBorder) }
        }
        .buttonStyle(.plain)
        .disabled(!store.isEditingEnabled || store.isLoading)
        .opacity(store.isEditingEnabled ? 1 : 0.5)
    }

    // MARK: - The day

    /// Where the rotation is, above the day it is describing.
    ///
    /// Only while one is running and only on days it covers: a strip counting
    /// "day 3 of 6" over a date the rotation has nothing to say about would be
    /// answering a question nobody asked of that day.
    @ViewBuilder
    private func rotationStrip(timeOfDay: HomeTimeOfDay) -> some View {
        if let cycle = cycleStore.activeCycle,
           let position = cycle.position(on: store.selectedDate) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.community(size: 10, weight: .bold))
                    Text(cycle.displayName)
                        .font(.community(.footnote, weight: .semibold))
                    Spacer(minLength: 8)
                    Text("day \(position) of \(cycle.length)")
                        .font(.community(.caption2))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                if let slot = cycle.slot(on: store.selectedDate) {
                    Text(slot.displayName)
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func daySection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Your day")
                    .font(.community(.headline, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer(minLength: 0)
                if !completedTasks.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            showsCompleted.toggle()
                        }
                    } label: {
                        Label("Completed (\(completedTasks.count))",
                              systemImage: showsCompleted ? "chevron.up" : "chevron.down")
                            .font(.community(.footnote))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .accessibilityValue(showsCompleted ? "Expanded" : "Collapsed")
                }
            }

            if let categoryFilter {
                Text("Showing \(categoryFilter.title.lowercased()) items. Choose All to see the whole day.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            if let reason = store.editingBlockedReason {
                Text(reason)
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.isLoading {
                ProgressView("Loading your day…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if filtered.isEmpty {
                Text(categoryFilter == nil ? "Your day is open. Add a task or event to get started." : "Nothing in this category on this day.")
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plannerSurface(soft: true)
            } else {
                ForEach(dayAgenda) { entry in
                    agendaRow(entry)
                }
                if openTasks.isEmpty, !completedTasks.isEmpty {
                    Label(categoryFilter == nil ? "All tasks done. A little room to breathe." : "All tasks in this category are done.", systemImage: "checkmark.circle.fill")
                        .font(.community(.subheadline))
                        .foregroundStyle(PlannerStyle.success)
                        .padding(.vertical, 8)
                }
                if showsCompleted {
                    ForEach(completedTasks) { entry in
                        agendaRow(entry)
                    }
                }
            }
        }
    }

    private var openTasks: [PlannerEntry] { filtered.filter { $0.kind == .task && !$0.isComplete } }
    private var completedTasks: [PlannerEntry] { filtered.filter { $0.kind == .task && $0.isComplete } }
    /// One plan, not separate task/event modes. Events remain visible even
    /// when the day's tasks are finished; only completed tasks are tucked away.
    private var dayAgenda: [PlannerEntry] {
        PlannerAgendaOrder.ordered(filtered.filter { $0.kind == .event || !$0.isComplete }, time: { $0.time })
    }

    private func agendaRow(_ entry: PlannerEntry) -> some View {
        PlannerEntryRow(entry: entry, onEdit: { editor = .edit(entry) },
                        onOpenWorkout: { openingDay = $0 })
    }

    private func monthOverview(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.visibleMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.community(.title2, weight: .bold))
                    Text("Choose a date to see its tasks and events.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                    PlannerMonthCalendar(clearedDate: clearedDate, completionPulse: completionPulse)
                    if store.isLoading {
                        ProgressView("Loading this month…")
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if PlannerStore.isSameMonth(store.selectedDate, store.visibleMonth) {
                        Text(store.selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.community(.headline, weight: .bold))
                        let counts = store.taskCounts(on: store.selectedDate)
                        Text("\(counts.total) tasks · \(store.entries(on: store.selectedDate).filter { $0.kind == .event }.count) events")
                            .font(.community(.footnote))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                        ForEach(store.entries(on: store.selectedDate).prefix(3)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).font(.community(.headline))
                                Text(entry.displayTimeRange ?? "Anytime")
                                    .font(.community(.footnote))
                                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .plannerSurface()
                        }
                    }
                    if let error = store.persistenceError { errorCard(error, timeOfDay: timeOfDay) }
                }
                .padding(24)
            }
            .navigationTitle("Month overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isMonthShown = false } } }
            .safeAreaInset(edge: .bottom) {
                Button("Open this day") { isMonthShown = false }
                    .buttonStyle(EditorialPrimaryButtonStyle())
                    .disabled(store.isLoading || !PlannerStore.isSameMonth(store.selectedDate, store.visibleMonth))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(timeOfDay.surface)
            }
            .homeTimeScreen(timeOfDay)
        }
    }

    /// The day on screen, when every task on it is actually done.
    ///
    /// Read from the day rather than remembered from the moment it happened.
    /// This was state, set once when the last task of a day was ticked and
    /// never unset by anything -- so unticking that task left the badge, the
    /// banner and the calendar all still claiming a day that was no longer
    /// clear, while the counter beside them read 0/1.
    ///
    /// Counted through `taskCounts` rather than by filtering here, so that the
    /// claim and the "0/1 TASKS" figure can never come from two different
    /// ideas of what a task is.
    ///
    /// A day with nothing on it is not cleared. Clearing is something you do,
    /// and an empty day has had nothing done to it.
    private var clearedDate: String? {
        let counts = store.taskCounts(on: store.selectedDate)
        guard counts.total > 0, counts.done == counts.total else { return nil }
        return PlannerStore.dateString(store.selectedDate)
    }


    private func handleCompletion(_ event: PlannerCompletionEvent?) {
        guard let event,
              handledCompletionID != event.id,
              store.entries(on: store.selectedDate).contains(where: { $0.id == event.entryID })
        else { return }

        handledCompletionID = event.id
        feedbackTask?.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.72)) {
            completedEntryID = event.entryID
            completionMessage = event.clearedDay
                ? "You cleared \(store.selectedDate.formatted(.dateTime.weekday(.wide))). Everything planned is done."
                : "\(event.title) complete · \(event.completedTasks) of \(event.totalTasks)"
            if event.clearedDay {
                completionPulse.toggle()
            }
        }

        if event.clearedDay {
            RepbaseCelebrations.show(.dayCleared)
        }

        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(event.clearedDay ? 3.0 : 1.8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    completionMessage = nil
                    completedEntryID = nil
                }
            }
        }
    }

    private func completionToast(_ message: String, timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(RepbasePalette.sage)
            Text(message)
                .font(.community(size: 13, weight: .semibold))
                .foregroundStyle(timeOfDay.primaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, RepbaseDesign.pageInset)
        .accessibilityElement(children: .combine)
    }


    private var filtered: [PlannerEntry] {
        guard let categoryFilter else { return store.entries(on: store.selectedDate) }
        return store.entries(on: store.selectedDate)
            .filter { $0.category == categoryFilter }
    }

    // MARK: - Past due

    @ViewBuilder
    private func pastDueSection(timeOfDay: HomeTimeOfDay) -> some View {
        let entries = store.pastDue.filter { $0.date != PlannerStore.dateString(store.selectedDate) }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(
                    "Past due",
                    detail: "\(entries.count)",
                    tint: Color(hex: 0xD8557A),
                    timeOfDay: timeOfDay
                )
                ForEach(entries) { entry in
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
        let entries = store.upcomingEvents.filter { $0.date != PlannerStore.dateString(store.selectedDate) }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(
                    "Upcoming events",
                    detail: "next \(PlannerStore.upcomingHorizonDays) days",
                    tint: timeOfDay.accent,
                    timeOfDay: timeOfDay
                )
                ForEach(entries.prefix(6)) { entry in
                    PlannerEntryRow(
                        entry: entry,
                        showsDate: true,
                        onEdit: { editor = .edit(entry) },
                        onOpenWorkout: { openingDay = $0 }
                    )
                }
                if entries.count > 6 {
                    Text("+\(entries.count - 6) more")
                        .font(.community(.caption2))
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
                .font(.community(size: 15, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer(minLength: 0)
            Text(detail)
                .font(.community(size: 10, weight: .semibold))
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
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.primaryText)
                Button("Retry") { store.retry() }
                    .font(.community(.footnote, weight: .semibold))
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
    // Open while there is unfinished work in it: a checklist you are partway
    // through is the one worth seeing. Collapsed once it is done, because then
    // the heading says everything.
    @State private var showingSteps = false
    @State private var addingStep = false
    @State private var stepDraft = ""
    @State private var busyStep: Int?
    @State private var isAddingStep = false
    @State private var stepFailure: String?
    @State private var endingRepeat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.completionIsDerived {
                stepProgress
                if showingSteps {
                    stepList
                    stepControls
                }
            }
            if let stepFailure {
                Text(stepFailure)
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(RepbaseDesign.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, entry.completionIsDerived || entry.kind == .event ? 8 : 0)
        .background(
            entry.kind == .event ? PlannerStyle.soft : (entry.completionIsDerived ? timeOfDay.surfaceRaised : Color.clear),
            in: RoundedRectangle(cornerRadius: PlannerStyle.radius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PlannerStyle.radius)
                .strokeBorder(entry.completionIsDerived ? timeOfDay.canvasBorder : Color.clear)
        }
        .plannerWorkoutCompletionDialog(
            entry: $confirming,
            openableDay: { PlannerWorkoutCompletion.openableDay($0, workouts: workouts) },
            onOpen: { onOpenWorkout?($0) },
            onProceedAnyway: { store.setComplete($0, !$0.isComplete) }
        )
        // Fades and collapses when it leaves, which is what a finished overdue
        // task does once its line has been drawn.
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        // Long press rather than swipe: these rows sit in a scroll view, not a
        // List, where swipe actions would never fire.
        .contextMenu { entryActions }
        .confirmationDialog(
            "Stop this repeating task?",
            isPresented: $endingRepeat,
            titleVisibility: .visible
        ) {
            Button("Stop repeating", role: .destructive) {
                store.delete(entry, endsRepeat: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This day and every one after it goes. Days you have already "
                + "ticked off stay — ending a habit is not saying it never happened."
            )
        }
        .onAppear {
            showingSteps = entry.completionIsDerived && !entry.isComplete
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if entry.completionIsDerived {
                derivedMark.frame(width: 44, height: 44)
            } else if entry.isCompletable {
                completionToggle
            } else {
                categoryBadge.frame(width: 44, height: 44)
            }

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.community(.headline, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .strikethrough(entry.isComplete, color: timeOfDay.canvasSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge = entry.priority.badge {
                        Text(badge)
                            .font(.community(.caption2, weight: .bold))
                            .foregroundStyle(entry.priority.tint)
                    }
                    Text(subtitle)
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this \(entry.kind.title.lowercased())")

            Menu {
                entryActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.community(.body, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!store.isEditingEnabled || busyStep != nil || isAddingStep)
            .accessibilityLabel("Actions for \(entry.title)")
        }
    }

    @ViewBuilder
    private var entryActions: some View {
        Button("Edit", systemImage: "pencil", action: onEdit)
            .disabled(!store.isEditingEnabled || busyStep != nil || isAddingStep)
        if entry.isRepeating {
            Button("Delete this day", systemImage: "trash", role: .destructive) {
                store.delete(entry)
            }
            .disabled(!store.isEditingEnabled || busyStep != nil || isAddingStep)
            Button("Stop repeating", systemImage: "repeat.slash", role: .destructive) {
                endingRepeat = true
            }
            .disabled(!store.isEditingEnabled || busyStep != nil || isAddingStep)
        } else {
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(entry)
            }
            .disabled(!store.isEditingEnabled || busyStep != nil || isAddingStep)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsDate, let day = Self.date(from: entry.date) {
            parts.append(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        }
        parts.append(entry.displayTimeRange ?? "Anytime")
        parts.append(entry.category.title)
        if entry.kind == .event { parts.append("Event") }
        if let weekdays = entry.repeatWeekdays, !weekdays.isEmpty {
            parts.append(PlannerRepeatWeekday.summary(weekdays))
        } else if let every = entry.repeatIntervalDays { parts.append(Self.repeatLabel(every)) }
        return parts.joined(separator: " · ")
    }

    private var categoryBadge: some View {
        Image(systemName: entry.category.symbolName)
            .font(.community(size: 13, weight: .semibold))
            .foregroundStyle(entry.category.tint)
            .frame(width: 34, height: 34)
            .background(entry.category.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
    }

    // MARK: - Steps

    /// The heading's mark when it has steps.
    ///
    /// Not a button. The server refuses to tick a task while any step is
    /// outstanding -- the steps are the record of the work and the heading is
    /// only its account -- so a control here would fail every time it was
    /// pressed, which is worse than no control.
    private var derivedMark: some View {
        Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle.dotted")
            .font(.community(.title3))
            .foregroundStyle(
                entry.isComplete ? PlannerStyle.success : PlannerStyle.accentText
            )
            .accessibilityLabel(
                "\(entry.completedSubtaskCount) of \(entry.subtasks.count) steps done"
            )
    }

    /// How far through the checklist, readable without opening it.
    private var stepProgress: some View {
        let done = entry.completedSubtaskCount
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { showingSteps.toggle() }
        } label: {
            HStack {
                Text("\(done) of \(entry.subtasks.count) steps")
                    .monospacedDigit()
                Spacer()
                Text(showingSteps ? "Hide steps" : "Show steps")
                Image(systemName: showingSteps ? "chevron.up" : "chevron.down")
            }
            .font(.community(.footnote, weight: .semibold))
            .foregroundStyle(timeOfDay.canvasSecondaryText)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.leading, 44)
        .padding(.trailing, 12)
        .accessibilityHint("Complete all steps to complete this task automatically")
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entry.subtasks) { step in
                HStack(spacing: 9) {
                    Button {
                        Task { await toggle(step) }
                    } label: {
                        if busyStep == step.serverID {
                            ProgressView().controlSize(.small).frame(width: 18, height: 18)
                        } else {
                            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.community(.subheadline))
                                .foregroundStyle(
                                    step.isComplete
                                        ? PlannerStyle.success
                                        : timeOfDay.canvasSecondaryText
                                )
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .disabled(busyStep != nil || isAddingStep || !store.isEditingEnabled)
                    .accessibilityLabel("\(step.isComplete ? "Mark not done" : "Mark done"): \(step.title)")

                    Text(step.title)
                        .font(.community(.subheadline))
                        .strikethrough(step.isComplete, color: timeOfDay.secondaryText)
                        .foregroundStyle(
                            step.isComplete ? timeOfDay.secondaryText : timeOfDay.primaryText
                        )
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
                .contextMenu {
                    Button("Delete step", systemImage: "trash", role: .destructive) {
                        Task { await remove(step) }
                    }
                    .disabled(busyStep != nil || isAddingStep || !store.isEditingEnabled)
                }
            }
        }
        .padding(.leading, 24)
    }

    @ViewBuilder
    private var stepControls: some View {
        if addingStep {
            HStack(spacing: 8) {
                TextField("What is the next step?", text: $stepDraft)
                    .font(.community(.subheadline))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit { Task { await addStep() } }

                Button("Add") { Task { await addStep() } }
                    .font(.community(.footnote, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(timeOfDay.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(stepDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingStep || busyStep != nil)
            }
            .disabled(isAddingStep || !store.isEditingEnabled)
            .padding(.leading, 45)
        } else {
            Button(entry.subtasks.isEmpty ? "Break this into steps" : "Add another step") {
                addingStep = true
                showingSteps = true
            }
            .font(.community(.footnote, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.accent)
            .frame(minHeight: 44)
            .disabled(isAddingStep || busyStep != nil || !store.isEditingEnabled)
            .padding(.leading, 45)
        }
    }

    private func addStep() async {
        guard !isAddingStep, busyStep == nil, store.isEditingEnabled else { return }
        isAddingStep = true
        defer { isAddingStep = false }
        let title = stepDraft
        stepFailure = await store.addSubtask(to: entry, title: title)
        if stepFailure == nil {
            stepDraft = ""
            addingStep = false
        }
    }

    private func toggle(_ step: PlannerSubtask) async {
        guard busyStep == nil, !isAddingStep, store.isEditingEnabled else { return }
        busyStep = step.serverID
        stepFailure = await store.setSubtaskComplete(step, in: entry, !step.isComplete)
        busyStep = nil
    }

    private func remove(_ step: PlannerSubtask) async {
        guard busyStep == nil, !isAddingStep, store.isEditingEnabled else { return }
        busyStep = step.serverID
        stepFailure = await store.deleteSubtask(step, in: entry)
        busyStep = nil
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
            if store.isCompletionPending(entry) {
                ProgressView().controlSize(.small).frame(width: 20, height: 20)
            } else {
                Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.community(.title3))
                    .foregroundStyle(
                        entry.isComplete
                            ? PlannerStyle.success
                            : PlannerStyle.accentText
                    )
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(!store.isEditingEnabled || store.isSaving || store.isCompletionPending(entry))
        .accessibilityLabel(store.isCompletionPending(entry) ? "Saving task" : (entry.isComplete ? "Mark not done" : "Mark done"))
    }

    private static func date(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }
}

extension PlannerEntryRow {
    /// "every other day" reads better than "every 2 days", and "every week"
    /// better than "every 7". The rest fall back to the count.
    static func repeatLabel(_ days: Int) -> String {
        switch days {
        case 1: return "Every day"
        case 2: return "Every other day"
        case 7: return "Every week"
        case 14: return "Every 2 weeks"
        default: return "Every \(days) days"
        }
    }
}
