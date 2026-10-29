//
//  PlannerEntryEditorView.swift
//  IOS Frontend
//
//  Create or edit a task or event.
//

import SwiftUI

struct PlannerEntryEditorView: View {
    enum Mode: Identifiable {
        /// A new entry, already filled in with the day picked on the calendar.
        case create(PlannerKind, Date)
        case edit(PlannerEntry)

        var id: String {
            switch self {
            case .create(let kind, let date):
                return "create-\(kind.rawValue)-\(PlannerStore.dateString(date))"
            case .edit(let entry):
                return entry.id.uuidString
            }
        }
    }

    let mode: Mode
    /// Workouts the user already has, passed in rather than read from the
    /// environment so previews stand alone.
    var workouts: [WorkoutSummary] = []
    /// `nil` when the entry saved, and otherwise the reason to put on screen.
    /// It returned a Bool until a save started failing in the field and the
    /// only thing anyone could report was the sentence this view had made up.
    /// The steps written beside the task travel with it, because they can only
    /// be created once the task has an id to hang them on.
    var onSaved: ((PlannerEntry, [String]) async -> String?)?
    /// The second argument says whether the whole repeat should end, which a
    /// repeating task asks about before it is answered.
    var onDeleted: ((PlannerEntry, Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var draftSaved = false
    private struct Checkpoint: Codable, Equatable {
        var draft: PlannerEntry
        var date: Date
        var time: Date
        var hasTime: Bool
        // Optional so drafts written by earlier app versions still decode.
        var newSteps: [String]?
        var stepDraft: String?
        var repeatDays: Int?
        var repeatHasEnd: Bool?
        var repeatEnds: Date?
        var selectedRepeatWeekdays: Set<Int>?
        var customRepeatDays: Int?
    }
    private var checkpoint: Binding<Checkpoint> {
        Binding(get: {
            Checkpoint(draft: draft, date: date, time: time, hasTime: hasTime,
                       newSteps: newSteps, stepDraft: stepDraft, repeatDays: repeatDays,
                       repeatHasEnd: repeatHasEnd, repeatEnds: repeatEnds,
                       selectedRepeatWeekdays: selectedRepeatWeekdays, customRepeatDays: customRepeatDays)
        }, set: {
            draft = $0.draft; date = $0.date; time = $0.time; hasTime = $0.hasTime
            newSteps = $0.newSteps ?? []; stepDraft = $0.stepDraft ?? ""
            repeatDays = $0.repeatDays ?? 0; repeatHasEnd = $0.repeatHasEnd ?? false
            repeatEnds = $0.repeatEnds ?? Date()
            selectedRepeatWeekdays = $0.selectedRepeatWeekdays ?? []
            customRepeatDays = $0.customRepeatDays ?? 4
        })
    }
    @State private var draft: PlannerEntry
    @State private var date: Date
    @State private var time: Date
    @State private var hasTime: Bool
    /// The saved entry being shared, if Share was tapped.
    @State private var sharedEntry: SharedPostSource?
    /// Steps written here but not yet saved. They cannot be created until the
    /// task has an id, so they wait for it and are sent on straight after.
    @State private var newSteps: [String] = []
    @State private var stepDraft = ""
    /// 0 means it happens once, which is what most tasks are.
    @State private var repeatDays = 0
    @State private var repeatHasEnd = false
    @State private var repeatEnds = Date()
    /// Sentinel for "a number I will type", kept out of the range of real
    /// intervals so it can never be mistaken for one.
    private let customRepeatTag = -1
    private let weekdayRepeatTag = -2
    @State private var selectedRepeatWeekdays: Set<Int> = []
    @State private var customRepeatDays = 4
    @State private var isChoosingDeleteScope = false
    @State private var showsRepeatOptions = false
    @State private var showsNotes = false

    /// How often the task actually repeats, whichever way it was chosen.
    private var repeatInterval: Int {
        repeatDays == customRepeatTag ? customRepeatDays : repeatDays
    }

    /// Matches the server's bounds, which is what actually refuses anything
    /// outside them.
    private var isCustomRepeatValid: Bool {
        (1...365).contains(customRepeatDays)
    }

    /// The soonest a repeat may end: the day after it starts. A repeat that
    /// ends on the day it begins covers nothing.
    private var earliestEnd: Date {
        let first = repeatDays == weekdayRepeatTag
            ? PlannerRepeatWeekday.firstDate(onOrAfter: date, days: selectedRepeatWeekdays) : date
        return Calendar.current.date(byAdding: .day, value: 1, to: first) ?? first
    }

    init(
        mode: Mode,
        workouts: [WorkoutSummary] = [],
        onSaved: ((PlannerEntry, [String]) async -> String?)? = nil,
        onDeleted: ((PlannerEntry, Bool) -> Void)? = nil
    ) {
        self.mode = mode
        self.workouts = workouts
        self.onSaved = onSaved
        self.onDeleted = onDeleted

        switch mode {
        case .create(let kind, let day):
            _draft = State(
                initialValue: PlannerEntry(
                    kind: kind,
                    title: "",
                    date: PlannerStore.dateString(day)
                )
            )
            _date = State(initialValue: day)
            // An event happens at a time, so it starts with one filled in; a
            // task often only needs a day.
            _hasTime = State(initialValue: kind == .event)
            _time = State(initialValue: Self.defaultTime(on: day))
        case .edit(let entry):
            _draft = State(initialValue: entry)
            let day = Self.date(from: entry.date) ?? Date()
            _date = State(initialValue: day)
            _hasTime = State(initialValue: entry.time != nil)
            _time = State(
                initialValue: Self.time(from: entry.time, on: day) ?? Self.defaultTime(on: day)
            )
        }
    }

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorialFormHeader(
                        title: title,
                        leadingAction: .cancel,
                        saveTitle: "Save",
                        canSave: canSave,
                        onDismiss: { if !isSaving { dismiss() } },
                        onSave: save,
                        showsSaveAction: false
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.kind == .task ? "A little plan. A clearer day." : "Make time for what matters.")
                            .font(.community(.title2, weight: .bold))
                        Text(
                            draft.kind == .task
                                ? "Name it now. Add details only if you need them."
                                : "Events have a time, not a completion checkbox."
                        )
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    editorialNameAndType(timeOfDay: timeOfDay)
                    editorialDetails(timeOfDay: timeOfDay)
                    if draft.kind == .task {
                        editorialSteps(timeOfDay: timeOfDay)
                            .plannerSurface(soft: true)
                    }

                    advancedOptions(timeOfDay: timeOfDay)

                    if case .edit(let entry) = mode {
                        // Only an entry the server already knows about. A
                        // draft has no id for a post to point at, and the
                        // edits on screen are not saved until Save.
                        if let serverID = entry.serverID {
                            Button {
                                sharedEntry = SharedPostSource(id: serverID)
                            } label: {
                                Label(
                                    "Share to Feed",
                                    systemImage: "square.and.arrow.up"
                                )
                                .font(.community(.subheadline, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(timeOfDay.accent)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                        Button(role: .destructive) {
                            // A repeating task has two honest answers, so it
                            // asks rather than picking the wider one silently.
                            if entry.isRepeating {
                                isChoosingDeleteScope = true
                            } else {
                                onDeleted?(entry, false)
                                dismiss()
                            }
                        } label: {
                            Label("Delete \(draft.kind.title)", systemImage: "trash")
                                .font(.community(.subheadline, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .confirmationDialog(
                            "This task repeats",
                            isPresented: $isChoosingDeleteScope,
                            titleVisibility: .visible
                        ) {
                            Button("Delete this day only", role: .destructive) {
                                onDeleted?(entry, false)
                                dismiss()
                            }
                            Button("Delete this and stop repeating", role: .destructive) {
                                onDeleted?(entry, true)
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(
                                "Days you have already ticked off stay either way — "
                                + "ending a habit is not saying it never happened."
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .disabled(isSaving)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
            .safeAreaInset(edge: .bottom) {
                Button(isSaving ? "Saving…" : (isEditing ? "Save changes" : "Add \(draft.kind.title.lowercased())"), action: save)
                    .buttonStyle(EditorialPrimaryButtonStyle())
                    .disabled(!canSave || isSaving)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(timeOfDay.surface)
            }
            .saveFeedback(isSaving: isSaving, error: saveError)
            .recoverableDraft(key: "planner-\(mode.id)", value: checkpoint, saved: $draftSaved, error: $saveError)
            .fullScreenCover(item: $sharedEntry) { shared in
                NavigationStack {
                    PostComposerView(
                        kind: .planner,
                        sourceID: shared.id,
                        subject: draft.title.isEmpty
                            ? draft.kind.title
                            : draft.title
                    )
                }
            }
        }
    }

    private func editorialNameAndType(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Picker("Type", selection: $draft.kind) {
                ForEach(PlannerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.kind) { _, kind in
                if !draft.category.suits(kind) { draft.category = .other }
                if kind == .event { hasTime = true }
            }

            Text(draft.kind == .task ? "TASK NAME" : "EVENT NAME")
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            TextField(
                draft.kind == .task ? "What needs doing?" : "What is happening?",
                text: $draft.title
            )
            .font(.community(.title2, weight: .semibold))
            .foregroundStyle(timeOfDay.canvasPrimaryText)
            .textInputAutocapitalization(.sentences)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }

        }
    }

    private func advancedOptions(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.kind == .task, !isEditing {
                DisclosureGroup(isExpanded: $showsRepeatOptions) {
                    editorialRepeat(timeOfDay: timeOfDay)
                } label: {
                    settingLabel("Repeats", value: repeatSummary)
                }
            } else if draft.kind == .task, draft.isRepeating {
                Text("This task repeats. Edits affect this day; use Stop repeating to end future tasks.")
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            Picker("Priority", selection: $draft.priority) {
                ForEach(PlannerPriority.offered) { priority in Text(priority.title).tag(priority) }
            }
            .font(.community(.subheadline))
            .pickerStyle(.menu)
            .frame(minHeight: 44)

            DisclosureGroup(isExpanded: $showsNotes) {
                editorialNotes
            } label: {
                settingLabel("Notes", value: draft.notes.isEmpty ? "Add a note" : "Edit note")
            }
            NavigationLink {
                NotificationPreferencesView()
                    .navigationTitle("Reminders")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                HStack {
                    settingLabel("Reminder settings", value: "Manage")
                    Image(systemName: "chevron.right").font(.community(.caption))
                }
            }
            .buttonStyle(.plain)
            Text("Reminders follow your notification preferences.")
                .font(.community(.footnote))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .tint(PlannerStyle.accentText)
        .plannerSurface()
    }

    private func settingLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.community(.subheadline))
            Spacer(minLength: 12)
            Text(value).font(.community(.footnote)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var repeatSummary: String {
        switch repeatDays {
        case 0: return "Does not repeat"
        case weekdayRepeatTag: return "Selected weekdays"
        case customRepeatTag: return "Every \(customRepeatDays) days"
        default: return PlannerEntryRow.repeatLabel(repeatDays)
        }
    }

    private func editorialDetails(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("SCHEDULE").font(.community(.caption2, weight: .bold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            VStack(spacing: 0) {
                HStack {
                    Text("Category").font(.community(.subheadline))
                    Spacer()
                    Menu {
                        ForEach(PlannerCategory.available(for: draft.kind)) { category in
                            Button {
                                draft.category = category
                            } label: {
                                Label(category.title, systemImage: category.symbolName)
                            }
                        }
                    } label: {
                        Label(draft.category.title, systemImage: draft.category.symbolName)
                            .font(.community(.subheadline, weight: .bold))
                            .foregroundStyle(timeOfDay.accent)
                    }
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) { Divider() }


                if draft.category == .workout {
                    HStack {
                        Text("Workout").font(.community(.subheadline))
                        Spacer()
                        Picker("Workout", selection: $draft.workoutID) {
                            Text("None").tag(Int?.none)
                            ForEach(workouts) { workout in
                                Text(workout.name).tag(Int?.some(workout.id))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: draft.workoutID) { _, newValue in
                            guard draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
                                  let id = newValue,
                                  let match = workouts.first(where: { $0.id == id }) else { return }
                            draft.title = match.name
                        }
                    }
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) { Divider() }
                }

                HStack {
                    Text("Date").font(.community(.subheadline))
                    Spacer()
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) { Divider() }

                HStack {
                    Text("Set a time").font(.community(.subheadline))
                    Spacer()
                    Toggle("Set a time", isOn: $hasTime)
                        .labelsHidden()
                        .tint(timeOfDay.accent)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    if hasTime { Divider() }
                }

                if hasTime {
                    HStack {
                        Text(draft.kind == .task ? "Do it by" : "Starts").font(.community(.subheadline))
                        Spacer()
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) { Divider() }

                    // Only under a start time, because a length with nothing to
                    // start from describes nothing — and the server refuses the
                    // pair, so offering it here would only produce an error.
                    HStack {
                        Text("Length").font(.community(.subheadline))
                        Spacer()
                        Menu {
                            Button("No length") { draft.durationMinutes = nil }
                            ForEach(PlannerDuration.offered, id: \.self) { minutes in
                                Button(PlannerDuration.label(minutes)) {
                                    draft.durationMinutes = minutes
                                }
                            }
                        } label: {
                            Text(lengthLabel)
                                .font(.community(.subheadline, weight: .bold))
                                .foregroundStyle(timeOfDay.accent)
                        }
                    }
                    .padding(.vertical, 13)
                }
            }
            .plannerSurface()
        }
    }

    /// Breaking a task into the steps it is made of.
    ///
    /// Written here rather than only on the finished row, because this is the
    /// screen somebody is on when they realise a task is really six things.
    /// They cannot be created yet — a step carries its task's id and the task
    /// has none until it saves — so they are held and sent on straight after.
    private func editorialSteps(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Break it into steps",
                detail: draft.subtasks.isEmpty && newSteps.isEmpty ? "Optional" : nil
            )

            Text("A task with steps is done when they all are.")
                .font(.community(.footnote))
                .foregroundStyle(timeOfDay.canvasSecondaryText)

            // Steps this task already has, when an existing one is open. Shown
            // rather than edited: they are ticked off on the task's own row,
            // and a checkbox here would be a second place to get it wrong.
            ForEach(draft.subtasks) { step in
                HStack(spacing: 9) {
                    Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.community(.subheadline))
                        .foregroundStyle(
                            step.isComplete
                                ? Color(hex: 0x3FAE6A)
                                : timeOfDay.canvasSecondaryText.opacity(0.5)
                        )
                    Text(step.title)
                        .font(.community(.subheadline))
                        .strikethrough(step.isComplete, color: timeOfDay.canvasSecondaryText)
                        .foregroundStyle(
                            step.isComplete
                                ? timeOfDay.canvasSecondaryText
                                : timeOfDay.canvasPrimaryText
                        )
                    Spacer(minLength: 0)
                }
            }

            ForEach(Array(newSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 9) {
                    Image(systemName: "circle")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText.opacity(0.5))
                    Text(step)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                    Spacer(minLength: 0)
                    Button {
                        newSteps.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.canvasSecondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove step \(step)")
                }
            }

            HStack(spacing: 10) {
                TextField("Add a step", text: $stepDraft)
                    .font(.community(.subheadline))
                    .textFieldStyle(.plain)
                    .submitLabel(.next)
                    .onSubmit(addStep)

                Button("Add", action: addStep)
                    .font(.community(.footnote, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(timeOfDay.accent)
                    .disabled(stepDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .repbaseInsetSurface()
        }
    }

    private func addStep() {
        let title = stepDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newSteps.append(title)
        stepDraft = ""
    }

    /// The steps to save, including one still being typed.
    ///
    /// A step only joined the list when Add was pressed, so typing one and
    /// going straight to Save threw it away without saying so. Text somebody
    /// wrote in a box is text they meant, and a field is not a commitment
    /// ceremony.
    private var stepsToSave: [String] {
        let pending = stepDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return pending.isEmpty ? newSteps : newSteps + [pending]
    }

    /// How often a task comes back.
    ///
    /// Offered on creation only. Changing the rule behind days already written
    /// is a different act from editing one of them, and putting both on one
    /// screen would make it ambiguous which was meant.
    private func editorialRepeat(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Repeats",
                detail: repeatDays == 0 ? "Optional" : nil
            )

            Picker("Repeats", selection: $repeatDays) {
                Text("Does not repeat").tag(0)
                Text("Every day").tag(1)
                Text("Every other day").tag(2)
                Text("Every 3 days").tag(3)
                Text("Every week").tag(7)
                Text("Every 2 weeks").tag(14)
                Text("On selected weekdays…").tag(weekdayRepeatTag)
                // The menu covers the common answers; this is for the ones it
                // does not. Every four days is a real interval and a fixed
                // list has no room for it.
                Text("Every…").tag(customRepeatTag)
            }
            .pickerStyle(.menu)
            .tint(timeOfDay.accent)

            if repeatDays == weekdayRepeatTag {
                Text("Repeat each week on")
                    .font(.community(.subheadline))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 8) {
                    ForEach(PlannerRepeatWeekday.allCases) { day in
                        let selected = selectedRepeatWeekdays.contains(day.rawValue)
                        Button {
                            if selected { selectedRepeatWeekdays.remove(day.rawValue) }
                            else { selectedRepeatWeekdays.insert(day.rawValue) }
                            if repeatHasEnd { repeatEnds = max(repeatEnds, earliestEnd) }
                        } label: {
                            Text(day.shortTitle)
                                .font(.community(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? timeOfDay.accent : timeOfDay.canvasSecondaryText)
                                .background(timeOfDay.accent.opacity(selected ? 0.14 : 0.04), in: Capsule())
                                .overlay(Capsule().strokeBorder(timeOfDay.accent.opacity(selected ? 1 : 0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Text(selectedRepeatWeekdays.isEmpty ? "Choose at least one day." : PlannerRepeatWeekday.summary(Array(selectedRepeatWeekdays)))
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                if !selectedRepeatWeekdays.isEmpty {
                    Text("First task: \(PlannerRepeatWeekday.firstDate(onOrAfter: date, days: selectedRepeatWeekdays).formatted(date: .abbreviated, time: .omitted))")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            }

            if repeatDays == customRepeatTag {
                HStack(spacing: 8) {
                    Text("Every")
                        .font(.community(.subheadline))
                    TextField("", value: $customRepeatDays, format: .number)
                        .font(.community(.subheadline, weight: .semibold))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 58)
                        .padding(.vertical, 7)
                        .repbaseInsetSurface()
                    Text(customRepeatDays == 1 ? "day" : "days")
                        .font(.community(.subheadline))
                }

                if !isCustomRepeatValid {
                    Text("Between 1 and 365 days.")
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(RepbaseDesign.danger)
                }
            }

            if repeatDays != 0 {
                Toggle("Give it an end date", isOn: $repeatHasEnd)
                    .font(.community(.subheadline))
                    .tint(timeOfDay.accent)
                    // A DatePicker clamps what it *draws* to its range but
                    // leaves the binding alone, so an end date nobody touched
                    // stayed on today and was sent as the day the task starts
                    // -- which the server refuses, because a repeat has to end
                    // after it begins. The value is put in range here instead
                    // of being left for the picker to appear to fix.
                    .onChange(of: repeatHasEnd) { _, isOn in
                        if isOn { repeatEnds = max(repeatEnds, earliestEnd) }
                    }
                    .onChange(of: date) { _, _ in
                        repeatEnds = max(repeatEnds, earliestEnd)
                    }

                if repeatHasEnd {
                    DatePicker(
                        "Until",
                        selection: $repeatEnds,
                        in: earliestEnd...,
                        displayedComponents: .date
                    )
                    .font(.community(.subheadline))
                }

                Text(
                    repeatHasEnd
                        ? "The last day it appears is the day before this."
                        : "It keeps going until you stop it."
                )
                .font(.community(.footnote))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
        }
    }

    private var editorialNotes: some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(title: "Notes", detail: "Optional")
            TextField("Anything worth remembering", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Divider() }
        }
    }

    // MARK: - Saving

    /// "No length", or "1 hour · ends 18:30".
    ///
    /// The end time is the thing actually being decided. Working it out from a
    /// start and a length in your head is exactly the arithmetic a calendar
    /// ought to be doing for you.
    private var lengthLabel: String {
        guard let minutes = draft.durationMinutes else { return "No length" }
        let length = PlannerDuration.label(minutes)
        guard let end = previewEndTime(after: minutes) else { return length }
        return "\(length) · ends \(end)"
    }

    /// Read off the picker rather than the draft: the draft only learns the
    /// time when Save assembles it.
    private func previewEndTime(after minutes: Int) -> String? {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .minute, value: minutes, to: time) else {
            return nil
        }
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private var canSave: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // A custom interval outside the bounds is refused by the server, so
        // Save is not offered for one.
        if draft.kind == .task, !isEditing {
            if repeatDays == customRepeatTag, !isCustomRepeatValid { return false }
            if repeatDays == weekdayRepeatTag, selectedRepeatWeekdays.isEmpty { return false }
        }
        return true
    }

    private func save() {
        var saved = draft
        saved.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.date = PlannerStore.dateString(date)
        saved.time = hasTime ? Self.timeString(from: time) : nil
        // A length with no start is a row the server refuses, so turning the
        // time off has to take the length with it rather than leaving one
        // behind for Save to be rejected over.
        if !hasTime { saved.durationMinutes = nil }
        // Create-only, and only for a task. Sent as the day after the last one
        // wanted, because the server treats the end as the first day it no
        // longer applies.
        if saved.kind == .task, !isEditing, repeatDays != 0 {
            saved.repeatEveryDays = repeatDays == weekdayRepeatTag ? nil : repeatInterval
            saved.repeatOnWeekdays = repeatDays == weekdayRepeatTag ? selectedRepeatWeekdays.sorted() : nil
            saved.repeatEndsOn = repeatHasEnd ? PlannerStore.dateString(repeatEnds) : nil
        }
        if saved.kind == .event { saved.isComplete = false }
        if !saved.category.suits(saved.kind) { saved.category = .other }
        if saved.category != .workout { saved.workoutID = nil }
        guard !isSaving, let onSaved else { return }
        isSaving = true
        saveError = nil
        Task {
            defer { isSaving = false }
            if let problem = await onSaved(saved, saved.kind == .task ? stepsToSave : []) { saveError = problem }
            else { draftSaved = true; dismiss() }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String {
        switch mode {
        case .create: return "New \(draft.kind.title)"
        case .edit: return "Edit \(draft.kind.title)"
        }
    }

    // MARK: - Date and time conversion
    //
    // The API carries literal `YYYY-MM-DD` and `HH:mm:ss`, so these are built
    // from calendar components rather than a formatter, which would otherwise
    // drift with the device locale.

    private static func date(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    private static func time(from value: String?, on day: Date) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(
            bySettingHour: parts[0],
            minute: parts[1],
            second: 0,
            of: day
        )
    }

    private static func timeString(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func defaultTime(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
