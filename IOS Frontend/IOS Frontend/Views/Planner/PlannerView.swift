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
    /// The approved calendar opens on the month; the compact week remains one
    /// tap away when the user wants a tighter planning view.
    @State private var isMonthShown = true
    @State private var openingDay: Weekday?
    @State private var handledCompletionID: UUID?
    @State private var completedEntryID: PlannerEntry.ID?
    @State private var clearedDate: String?
    @State private var completionPulse = false
    @State private var completionMessage: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(spacing: 14) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CALENDAR")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(timeOfDay.accent)
                        Text(store.visibleMonth.formatted(.dateTime.month(.wide).year()))
                            .font(.community(size: 32, weight: .bold))
                            .tracking(-0.7)
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                    }
                    Spacer(minLength: 0)
                }

                if isMonthShown {
                    PlannerMonthCalendar(
                        clearedDate: clearedDate,
                        completionPulse: completionPulse
                    ) {
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
                rotationStrip(timeOfDay: timeOfDay)
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
        .minimizesBottomBarOnScroll()
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
        .overlay(alignment: .top) {
            if let completionMessage {
                completionToast(completionMessage, timeOfDay: timeOfDay)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if store.isLoading {
                ProgressView()
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .fullScreenCover(item: $editor) { mode in
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
        .onChange(of: store.latestCompletionEvent) { _, event in
            handleCompletion(event)
        }
        .onDisappear { feedbackTask?.cancel() }
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
                .font(.community(size: 13, weight: .semibold))
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

    /// Where the rotation is, above the day it is describing.
    ///
    /// Only while one is running and only on days it covers: a strip counting
    /// "day 3 of 6" over a date the rotation has nothing to say about would be
    /// answering a question nobody asked of that day.
    @ViewBuilder
    private func rotationStrip(timeOfDay: HomeTimeOfDay) -> some View {
        if let cycle = cycleStore.activeCycle,
           let position = cycle.position(on: store.selectedDate) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.community(size: 10, weight: .bold))
                    Text(cycle.displayName.uppercased())
                        .font(.community(size: 10, weight: .bold))
                        .tracking(1.1)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("day \(position) of \(cycle.length)")
                        .font(.community(.caption2))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                .foregroundStyle(timeOfDay.accent)

                // One dot per day of the turn, filled up to where this date
                // sits. A six-day block is a shape you can take in at a
                // glance; "day 3 of 6" is a sentence you have to read.
                HStack(spacing: 5) {
                    ForEach(1...max(cycle.length, 1), id: \.self) { day in
                        Circle()
                            .fill(
                                day <= position
                                    ? timeOfDay.accent
                                    : timeOfDay.canvasBorder
                            )
                            .frame(width: 5, height: 5)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func daySection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.community(.title3, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Text(store.selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                Spacer(minLength: 0)
            }

            // What the rotation puts here, named. The strip above says where
            // you are in the block; this says why this particular day has the
            // workout it has, and that changing the rotation changes it.
            if let cycle = cycleStore.activeCycle,
               let position = cycle.position(on: store.selectedDate),
               let slot = cycle.slot(on: store.selectedDate) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.community(size: 9, weight: .bold))
                    Text("\(slot.displayName) · \(cycle.displayName) · day \(position)")
                        .font(.community(.caption2))
                        .lineLimit(1)
                }
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            if let reason = store.editingBlockedReason {
                Text(reason)
                    .font(.community(.caption2))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            dayOverview(timeOfDay: timeOfDay)

            if categoryFilter == nil {
                PlannerDaySchedule(
                    onSelect: { editor = .edit($0) },
                    onOpenWorkout: { openingDay = $0 },
                    recentlyCompletedEntryID: completedEntryID,
                    dayIsCleared: clearedDate == PlannerStore.dateString(store.selectedDate)
                )
            } else {
                filteredList(timeOfDay: timeOfDay)
            }
        }
    }

    private func dayOverview(timeOfDay: HomeTimeOfDay) -> some View {
        let entries = store.entries(on: store.selectedDate)
        let counts = store.taskCounts(on: store.selectedDate)
        let events = entries.filter { $0.kind == .event }.count
        let next = store.timedEntries(on: store.selectedDate).first {
            guard Calendar.current.isDateInToday(store.selectedDate),
                  let time = $0.time else { return true }
            let now = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            return String(time.prefix(5)) >= now
        }

        return HStack(spacing: 0) {
            dayMetric("\(counts.done)/\(counts.total)", "TASKS", tint: timeOfDay.accent)
            Divider().frame(height: 30)
            dayMetric("\(events)", "EVENTS", tint: RepbasePalette.sage)
            Divider().frame(height: 30)
            dayMetric(next?.displayTime ?? "Clear", "NEXT", tint: timeOfDay.canvasPrimaryText)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.38), value: counts.done)
        .overlay(alignment: .bottomLeading) {
            if clearedDate == PlannerStore.dateString(store.selectedDate) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("DAY CLEARED")
                }
                .font(.community(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(RepbasePalette.sage)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RepbasePalette.sage.opacity(0.12),
                    in: Capsule()
                )
                .offset(y: 11)
                .transition(.scale.combined(with: .opacity))
            }
        }
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
                clearedDate = event.date
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

    private func dayMetric(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.community(.subheadline, weight: .bold)).foregroundStyle(tint)
            Text(label)
                .font(.community(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    /// A filtered day is a plain list, not a schedule.
    ///
    /// A grid with one block in it and eleven empty hours around it says the
    /// day is mostly empty, when in fact the rest of it was filtered out.
    private func filteredList(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 8) {
            if filtered.isEmpty {
                Text("Nothing in this category today.")
                    .font(.community(.footnote))
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

    var body: some View {
        HStack(spacing: 11) {
            categoryBadge

            VStack(alignment: .leading, spacing: 2) {
                // The line is drawn rather than switched on, so ticking a task
                // off reads as crossing it out. `.strikethrough` appears whole
                // in one frame, which a fade straight afterwards turns into a
                // blink.
                Text(entry.title)
                    .font(.community(.subheadline, weight: .semibold))
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
                HStack(spacing: 5) {
                    // Before the subtitle, not inside it: joined into that
                    // dotted list it read as one more attribute, when the whole
                    // point is that it outranks them.
                    if let badge = entry.priority.badge {
                        Text(badge)
                            .font(.community(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(entry.priority.tint)
                            .fixedSize()
                    }
                    Text(subtitle)
                        .font(.community(size: 9, weight: .medium))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
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
        if let when = entry.displayTimeRange { parts.append(when) }
        if entry.kind == .event { parts.append("Event") }
        return parts.joined(separator: " · ")
    }

    private var categoryBadge: some View {
        Image(systemName: entry.category.symbolName)
            .font(.community(size: 13, weight: .semibold))
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
                .font(.community(.title3))
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
