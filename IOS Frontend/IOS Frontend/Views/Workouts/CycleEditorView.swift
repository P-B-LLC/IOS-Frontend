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
                ForEach(draft.slots) { slot in
                    slotRow(slot)
                }
            } header: {
                Text("Each day")
            } footer: {
                Text(
                    "Set builds the workout for that day. Swipe a day to clear "
                        + "it back to rest — a rest day still counts towards the "
                        + "cycle length."
                )
            }

            // Both stores can fail here, and they fail at different moments:
            // the workout store when a day is set, the cycle store when the
            // rotation is saved. Showing only one leaves a day that quietly
            // stayed on Set with nothing on screen saying why.
            ForEach(errors, id: \.self) { error in
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
                // Also while a day's workout is still being written: saving
                // the rotation first would send a slot with no workout id.
                .disabled(!draft.hasAnyWorkout || store.isSaving || workoutStore.isSaving)
            }
        }
        .task {
            // Once: re-running this on every redraw would undo the user's
            // choices as they made them.
            guard !didLoad else { return }
            didLoad = true
            if case .edit(let cycle) = mode {
                draft = WorkoutCycleDraft(cycle)
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var errors: [String] {
        [workoutStore.persistenceError, store.persistenceError].compactMap { $0 }
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

    /// A day, and the way into building what goes on it.
    ///
    /// The builder is pushed rather than presented, so its Cancel is the way
    /// back to this list and saving lands the user here too, with the day
    /// filled in — rather than dropping them somewhere else mid-rotation.
    private func slotRow(_ slot: WorkoutCycleSlot) -> some View {
        NavigationLink {
            WorkoutEditorView(
                mode: .create,
                // The workouts already saved, offered as chips inside the
                // builder. An eight-day split usually repeats three or four
                // workouts, so reuse has to be a tap and not a retype.
                suggestions: workoutStore.knownWorkouts
            ) { built in
                Task { await assign(built, at: slot.position) }
            }
        } label: {
            LabeledContent("Day \(slot.position)") {
                Text(slot.isRest ? "Set" : slot.displayName)
                    .foregroundStyle(slot.isRest ? Color.accentColor : .primary)
            }
        }
        .swipeActions(edge: .trailing) {
            if !slot.isRest {
                Button("Rest") { clear(at: slot.position) }
                    .tint(.gray)
            }
        }
    }

    /// Saves what was built and puts it on this day.
    ///
    /// The workout has to exist on the server before a slot can name it, and
    /// the id it gets back is the only thing that identifies it — so the day
    /// stays on rest if the save fails, rather than pointing at nothing.
    private func assign(_ built: Workout, at position: Int) async {
        guard let id = await workoutStore.createTemplate(built) else { return }
        guard let index = draft.slots.firstIndex(where: { $0.position == position })
        else { return }
        draft.slots[index].workoutID = id
        draft.slots[index].workoutName = built.name
    }

    private func clear(at position: Int) {
        guard let index = draft.slots.firstIndex(where: { $0.position == position })
        else { return }
        draft.slots[index].workoutID = nil
        draft.slots[index].workoutName = nil
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
    ///
    /// Named rather than memberwise: the four stored properties in order are
    /// exactly the synthesized initializer, and this one has to run `resize`
    /// afterwards to hold the slots-match-length invariant.
    init(_ cycle: WorkoutCycle) {
        self.init()
        name = cycle.name
        anchorDate = cycle.anchorDate
        slots = cycle.orderedSlots
        resize(to: cycle.length)
    }
}
