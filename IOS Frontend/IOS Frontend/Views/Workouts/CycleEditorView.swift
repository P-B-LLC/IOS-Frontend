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
    @Environment(\.homeTimeOfDay) private var timeOfDay

    @State private var draft = WorkoutCycleDraft()
    @State private var didLoad = false
    /// The workouts in this rotation that already come back every week, held
    /// while the question about them is on screen.
    @State private var clashingRepeats: [String] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text("TRAINING ROTATION")
                        .font(.community(.caption2, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(timeOfDay.accent)
                    Text(isEditing ? "Refine your rhythm." : "Build your rhythm.")
                        .font(.community(.largeTitle, weight: .bold))
                        .tracking(-0.8)
                    Text("Create a cycle that repeats around your schedule.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                .padding(.bottom, 8)

                TextField("Name your rotation", text: $draft.name)
                    .font(.community(.title3, weight: .semibold))
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 8)
            } footer: {
                Text("A short name makes this rotation easy to recognize later.")
            }

            Section {
                Stepper(value: lengthBinding, in: 2...31) {
                    LabeledContent("Cycle length") {
                        Text("\(draft.length) days")
                            .font(.community(.body, weight: .semibold))
                            .foregroundStyle(timeOfDay.accent)
                    }
                }
                DatePicker(
                    "Starts on",
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Your cycle")
                        .font(.community(.title3, weight: .bold))
                        .textCase(nil)
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                    Spacer()
                    Text("\(plannedSlotCount) of \(draft.length) planned")
                        .font(.community(.caption))
                        .textCase(nil)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            } footer: {
                Text("Choose a workout for each training day. Swipe a planned day to return it to rest.")
            }

            // Both stores can fail here, and they fail at different moments:
            // the workout store when a day is set, the cycle store when the
            // rotation is saved. Showing only one leaves a day that quietly
            // stayed on Set with nothing on screen saying why.
            ForEach(errors, id: \.self) { error in
                Section {
                    Text(error)
                        .font(.community(.footnote))
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 22, for: .scrollContent)
        .navigationTitle(isEditing ? "Edit rotation" : "New rotation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Asked before saving rather than after being refused. The
                    // app knows which workouts already repeat weekly, so there
                    // is no reason to send a rotation that cannot be stored and
                    // then explain the error.
                    let clashing = workoutStore.weeklyRepeatNames(
                        among: Set(draft.slots.compactMap(\.workoutID))
                    )
                    if !clashing.isEmpty {
                        clashingRepeats = clashing
                        return
                    }
                    Task {
                        await save()
                        // Only when it worked. Dismissing either way is how a
                        // refused rotation came to look like a saved one: the
                        // server rejects a workout that already repeats
                        // weekly, the store recorded why, and this sheet shut
                        // over the top of the message before it could be read.
                        if store.persistenceError == nil { dismiss() }
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
        .homeTimeScreen(timeOfDay)
        // A rotation and a weekly repeat both write the same days, so one of
        // them has to go. Offering to stop the repeat is the answer somebody
        // wanted anyway -- they have just put the workout in a rotation.
        .confirmationDialog(
            clashingRepeats.count == 1
                ? "\(clashingRepeats[0]) already repeats weekly"
                : "Some of these already repeat weekly",
            isPresented: Binding(
                get: { !clashingRepeats.isEmpty },
                set: { if !$0 { clashingRepeats = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop the weekly repeat and save") {
                clashingRepeats = []
                Task {
                    await save(stoppingWeeklyRepeats: true)
                    guard store.persistenceError == nil else { return }
                    // The repeat is gone on the server, so the week the
                    // workout screens are holding is now wrong about it.
                    workoutStore.retryPersistence()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { clashingRepeats = [] }
        } message: {
            Text(
                clashingRepeats.count == 1
                    ? "A workout cannot be on a weekly repeat and in a rotation at once. The rotation will take over from here; weeks already planned stay as they are."
                    : "\(clashingRepeats.joined(separator: ", ")) cannot be on a weekly repeat and in a rotation at once. The rotation will take over from here; weeks already planned stay as they are."
            )
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var errors: [String] {
        [workoutStore.persistenceError, store.persistenceError].compactMap { $0 }
    }

    private var plannedSlotCount: Int {
        draft.slots.filter { !$0.isRest }.count
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
                await assign(built, at: slot.position)
            }
        } label: {
            HStack(spacing: 12) {
                Text("\(slot.position)")
                    .font(.community(.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(slot.isRest ? timeOfDay.accent : RepbasePalette.cream)
                    .frame(width: 30, height: 30)
                    .background(
                        slot.isRest ? timeOfDay.accent.opacity(0.12) : timeOfDay.accent,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.isRest ? "Rest day" : slot.displayName)
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                    Text(slot.isRest ? "Choose a workout or keep recovery" : "Workout planned")
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }

                Spacer()

                Text(slot.isRest ? "Set" : "Edit")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
            }
            .padding(.vertical, 5)
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
    /// `nil` when the built workout took the slot, and otherwise why it did
    /// not -- the editor shows this rather than inventing a reason.
    private func assign(_ built: Workout, at position: Int) async -> String? {
        guard let id = await workoutStore.createTemplate(built) else {
            return workoutStore.persistenceError ?? SaveFailure.unexplained
        }
        // The rotation changed under the editor, so there is no longer a slot
        // to put this in. The workout itself was created and is not lost.
        guard let index = draft.slots.firstIndex(where: { $0.position == position }) else {
            return "Day \(position) is no longer part of this rotation. The workout was saved and is in your list."
        }
        draft.slots[index].workoutID = id
        draft.slots[index].workoutName = built.name
        return nil
    }

    private func clear(at position: Int) {
        guard let index = draft.slots.firstIndex(where: { $0.position == position })
        else { return }
        draft.slots[index].workoutID = nil
        draft.slots[index].workoutName = nil
    }

    private func save(stoppingWeeklyRepeats: Bool = false) async {
        switch mode {
        case .create:
            await store.create(draft, stoppingWeeklyRepeats: stoppingWeeklyRepeats)
        case .edit(let cycle):
            var updated = cycle
            updated.name = draft.name
            updated.length = draft.length
            updated.anchorDate = draft.anchorDate
            updated.slots = draft.slots
            await store.update(updated, stoppingWeeklyRepeats: stoppingWeeklyRepeats)
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
