//
//  CycleEditorView.swift
//  IOS Frontend
//
//  Building a rotation: how many days it runs, and what falls on each.
//
//  Rest days are slots like any other. A six-workout, two-rest split is an
//  eight-day rotation, and leaving the rest days out would make it a six-day
//  one that lands wrong from the second turn onwards.
//

import SwiftUI

struct CycleEditorView: View {
    enum Mode: Identifiable, Hashable {
        case create
        case edit(WorkoutCycle)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let cycle): "edit-\(cycle.id)"
            }
        }
    }

    let mode: Mode

    @Environment(CycleStore.self) private var store
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = WorkoutCycleDraft()
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $draft.name)
            } footer: {
                Text("Something to recognise it by, like \"PPL + rest\".")
            }

            Section {
                Stepper(value: lengthBinding, in: 2...31) {
                    LabeledContent("Cycle length") {
                        Text("\(draft.length) days")
                            .foregroundStyle(.secondary)
                    }
                }
                DatePicker(
                    "Day 1 falls on",
                    selection: $draft.anchorDate,
                    displayedComponents: .date
                )
            } footer: {
                Text(anchorFooter)
            }

            Section {
                if workoutStore.knownWorkouts.isEmpty {
                    Text("Save a workout first, then you can put it in the rotation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draft.slots) { slot in
                        slotRow(slot)
                    }
                }
            } header: {
                Text("Each day")
            } footer: {
                Text("Leave a day on Rest to keep it in the cycle without a workout.")
            }

            if let error = store.persistenceError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit rotation" : "New rotation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await save()
                        dismiss()
                    }
                }
                .disabled(!draft.hasAnyWorkout || store.isSaving)
            }
        }
        .task {
            // Once: re-running this on every redraw would undo the user's
            // choices as they made them.
            guard !didLoad else { return }
            didLoad = true
            if case .edit(let cycle) = mode {
                draft = WorkoutCycleDraft(
                    name: cycle.name,
                    length: cycle.length,
                    anchorDate: cycle.anchorDate,
                    slots: cycle.orderedSlots
                )
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Resizing keeps the days already chosen, so shortening a cycle by one
    /// does not clear the other seven.
    private var lengthBinding: Binding<Int> {
        Binding(
            get: { draft.length },
            set: { draft.resize(to: $0) }
        )
    }

    private var anchorFooter: String {
        let day = draft.anchorDate.formatted(
            .dateTime.weekday(.wide).month(.wide).day()
        )
        return "The cycle counts from \(day). After that it repeats every "
            + "\(draft.length) days, which means it will not land on the same "
            + "weekday twice."
    }

    private func slotRow(_ slot: WorkoutCycleSlot) -> some View {
        LabeledContent("Day \(slot.position)") {
            Menu {
                Button("Rest") { choose(nil, at: slot.position) }
                Divider()
                ForEach(workoutStore.knownWorkouts) { workout in
                    Button(workout.name) {
                        choose(workout, at: slot.position)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(slot.displayName)
                        .foregroundStyle(slot.isRest ? .secondary : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func choose(_ workout: WorkoutSummary?, at position: Int) {
        guard let index = draft.slots.firstIndex(where: { $0.position == position })
        else { return }
        draft.slots[index].workoutID = workout?.serverID
        draft.slots[index].workoutName = workout?.name
    }

    private func save() async {
        switch mode {
        case .create:
            await store.create(draft)
        case .edit(let cycle):
            var updated = cycle
            updated.name = draft.name
            updated.length = draft.length
            updated.anchorDate = draft.anchorDate
            updated.slots = draft.slots
            await store.update(updated)
        }
    }
}

extension WorkoutCycleDraft {
    /// Builds a draft from a rotation already saved, so editing starts from
    /// what is there rather than from the default eight blank days.
    init(name: String, length: Int, anchorDate: Date, slots: [WorkoutCycleSlot]) {
        self.init()
        self.name = name
        self.anchorDate = anchorDate
        self.slots = slots
        resize(to: length)
    }
}
