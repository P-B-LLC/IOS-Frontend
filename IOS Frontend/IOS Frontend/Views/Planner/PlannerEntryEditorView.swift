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
    var onSaved: ((PlannerEntry) -> Void)?
    var onDeleted: ((PlannerEntry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlannerEntry
    @State private var date: Date
    @State private var time: Date
    @State private var hasTime: Bool

    init(
        mode: Mode,
        workouts: [WorkoutSummary] = [],
        onSaved: ((PlannerEntry) -> Void)? = nil,
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
        NavigationStack {
            Form {
                nameSection
                categorySection
                whenSection
                if !draft.notes.isEmpty || isEditing {
                    notesSection
                }
                deleteSection
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField(
                draft.kind == .task ? "What needs doing?" : "What is happening?",
                text: $draft.title
            )
            .textInputAutocapitalization(.sentences)

            Picker("Type", selection: $draft.kind) {
                ForEach(PlannerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.kind) { _, newKind in
                // The two kinds draw from different halves of the category
                // list, so switching can strand the one already chosen. Fall
                // back to Other, which both share, rather than sending the
                // server something it will refuse.
                guard !draft.category.suits(newKind) else { return }
                draft.category = .other
            }
        } footer: {
            Text(
                draft.kind == .task
                    ? "A task gets a checkbox you can tick off."
                    : "An event happens at a time and is not ticked off."
            )
        }
    }

    private var categorySection: some View {
        Section("Category") {
            // Only the half that fits what is being planned. A birthday is not
            // something to tick off, and a habit is not an occasion.
            Picker("Category", selection: $draft.category) {
                ForEach(PlannerCategory.available(for: draft.kind)) { category in
                    Label(category.title, systemImage: category.symbolName)
                        .tag(category)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            // Only a workout entry links to a workout, which is what ties this
            // page to the workout page.
            if draft.category == .workout {
                Picker("Workout", selection: $draft.workoutID) {
                    Text("None").tag(Int?.none)
                    ForEach(workouts) { workout in
                        Text(workout.name).tag(Int?.some(workout.id))
                    }
                }
                .onChange(of: draft.workoutID) { _, newValue in
                    // Naming it after the workout saves typing the same thing
                    // twice, but never overwrites a title already written.
                    guard draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
                          let id = newValue,
                          let match = workouts.first(where: { $0.id == id }) else { return }
                    draft.title = match.name
                }
            }
        }
    }

    private var whenSection: some View {
        Section("When") {
            DatePicker(
                "Date",
                selection: $date,
                displayedComponents: .date
            )

            Toggle("Set a time", isOn: $hasTime)

            if hasTime {
                DatePicker(
                    draft.kind == .task ? "Do it by" : "Starts",
                    selection: $time,
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Anything worth remembering", text: $draft.notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    /// Only when there is something to delete. A draft that has never been
    /// saved is discarded with Cancel.
    ///
    /// Acts on the first tap: the button names the thing it removes, and no
    /// destructive action in this app asks first.
    @ViewBuilder
    private var deleteSection: some View {
        if case .edit(let entry) = mode {
            Section {
                Button(role: .destructive) {
                    onDeleted?(entry)
                    dismiss()
                } label: {
                    // The destructive role reddens the text but leaves the
                    // icon on the accent tint, which reads as two different
                    // controls. Tinting the button does not reach it either.
                    Label("Delete \(draft.kind.title)", systemImage: "trash")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Saving

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        var saved = draft
        saved.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.date = PlannerStore.dateString(date)
        saved.time = hasTime ? Self.timeString(from: time) : nil
        if saved.kind == .event { saved.isComplete = false }
        if !saved.category.suits(saved.kind) { saved.category = .other }
        if saved.category != .workout { saved.workoutID = nil }
        onSaved?(saved)
        dismiss()
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
