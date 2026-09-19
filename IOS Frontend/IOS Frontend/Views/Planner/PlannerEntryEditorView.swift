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
    var onDeleted: ((PlannerEntry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var draftSaved = false
    private struct Checkpoint: Codable, Equatable {
        var draft: PlannerEntry
        var date: Date
        var time: Date
        var hasTime: Bool
    }
    private var checkpoint: Binding<Checkpoint> {
        Binding(get: { Checkpoint(draft: draft, date: date, time: time, hasTime: hasTime) }, set: {
            draft = $0.draft; date = $0.date; time = $0.time; hasTime = $0.hasTime
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

    init(
        mode: Mode,
        workouts: [WorkoutSummary] = [],
        onSaved: ((PlannerEntry, [String]) async -> String?)? = nil,
        onDeleted: ((PlannerEntry) -> Void)? = nil
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
                VStack(alignment: .leading, spacing: 22) {
                    EditorialFormHeader(
                        title: title,
                        leadingAction: .cancel,
                        saveTitle: "Save",
                        canSave: canSave,
                        onDismiss: { dismiss() },
                        onSave: save,
                        showsSaveAction: false
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.kind == .task ? "NEW TASK" : "NEW EVENT")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text(draft.kind == .task ? "Add something to your day." : "Put time on the calendar.")
                            .font(.community(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                        Text(
                            draft.kind == .task
                                ? "A quick reminder that lives beside your events."
                                : "Plan a moment with a clear start and finish."
                        )
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    editorialNameAndType(timeOfDay: timeOfDay)

                    // Above the schedule, because breaking the work up is part
                    // of saying what the task *is* -- the same thought as
                    // naming it. When it happens is a separate decision, made
                    // once you know what you are scheduling.
                    //
                    // Events do not have steps: they happen, and carry no
                    // checkbox for a step to tick off.
                    if draft.kind == .task {
                        editorialSteps(timeOfDay: timeOfDay)
                    }

                    editorialDetails(timeOfDay: timeOfDay)

                    // Creation only. Changing the rule behind days already
                    // written is a different act from editing one of them, and
                    // offering both here would make it ambiguous which was
                    // meant.
                    if draft.kind == .task, !isEditing {
                        editorialRepeat(timeOfDay: timeOfDay)
                    }

                    if !draft.notes.isEmpty || isEditing {
                        editorialNotes
                    }

                    Button(isEditing ? "Save changes" : "Add \(draft.kind.title.lowercased())") {
                        save()
                    }
                    .buttonStyle(EditorialPrimaryButtonStyle())
                    .disabled(!canSave)

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
                            onDeleted?(entry)
                            dismiss()
                        } label: {
                            Label("Delete \(draft.kind.title)", systemImage: "trash")
                                .font(.community(.subheadline, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
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
            TextField(
                draft.kind == .task ? "What needs doing?" : "What is happening?",
                text: $draft.title
            )
            .font(.community(.title2, weight: .semibold))
            .foregroundStyle(timeOfDay.canvasPrimaryText)
            .textInputAutocapitalization(.sentences)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }

            Picker("Type", selection: $draft.kind) {
                ForEach(PlannerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.kind) { _, kind in
                guard !draft.category.suits(kind) else { return }
                draft.category = .other
            }
        }
    }

    private func editorialDetails(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(title: "Schedule")
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

                // Sits with Category rather than under Schedule: both describe
                // the thing itself, where Date and Set a time describe when it
                // happens. Offered for events too — a flight matters more than
                // a coffee, and the request was tasks and events alike.
                HStack {
                    Text("Priority").font(.community(.subheadline))
                    Spacer()
                    Menu {
                        ForEach(PlannerPriority.offered) { priority in
                            Button {
                                draft.priority = priority
                            } label: {
                                Label(priority.title, systemImage: priority.symbolName)
                            }
                        }
                    } label: {
                        Label(draft.priority.title, systemImage: draft.priority.symbolName)
                            .font(.community(.subheadline, weight: .bold))
                            .foregroundStyle(
                                draft.priority == .high
                                    ? draft.priority.tint
                                    : timeOfDay.accent
                            )
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
                title: "Steps",
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
            }
            .pickerStyle(.menu)
            .tint(timeOfDay.accent)

            if repeatDays > 0 {
                Toggle("Give it an end date", isOn: $repeatHasEnd)
                    .font(.community(.subheadline))
                    .tint(timeOfDay.accent)

                if repeatHasEnd {
                    DatePicker(
                        "Until",
                        selection: $repeatEnds,
                        in: (date.addingTimeInterval(86_400))...,
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
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        if saved.kind == .task, !isEditing, repeatDays > 0 {
            saved.repeatEveryDays = repeatDays
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
            if let problem = await onSaved(saved, newSteps) { saveError = problem }
            else { draftSaved = true; dismiss() }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String {
        switch mode {
        case .create(let kind, _): return "New \(kind.title)"
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
