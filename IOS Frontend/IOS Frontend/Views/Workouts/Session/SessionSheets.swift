//
//  SessionSheets.swift
//  IOS Frontend
//
//  Reordering and adding exercises while a session is in progress.
//

import SwiftUI

/// Every exercise of the session as one compact row, to drag into a new order.
///
/// Collapsed on purpose: dragging a card full of set rows past a dozen others
/// is how a long-press reorder loses its place. Here each exercise is a single
/// line with its progress, and the drag is the system list's own, with its
/// lift, gap and haptics. Sets, logged or not, move with their exercise.
struct SessionReorderSheet: View {
    let day: Weekday
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let session = store.activeSession(on: day) {
                    Section {
                        ForEach(session.exercises) { exercise in
                            HStack(spacing: 12) {
                                if let group = exercise.supersetGroup {
                                    Capsule().fill(SupersetPalette.color(for: group)).frame(width: 4, height: 30)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.displayName).font(.community(.subheadline, weight: .semibold))
                                    Text("\(exercise.loggedCount) of \(exercise.sets.count) sets logged")
                                        .font(.community(.caption))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if exercise.isComplete {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RepbaseDesign.success)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                        .onMove { source, destination in
                            store.moveSessionExercises(on: day, fromOffsets: source, toOffset: destination)
                        }
                    } footer: {
                        Text("Drag to change the order. Logged sets and your rest timer are kept.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Adds exercises to the session in progress. Each one is added as it is
/// chosen, so there is nothing to lose by closing the sheet half way.
struct AddSessionExerciseSheet: View {
    let day: Weekday
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var added: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Added exercises go to the end of today’s workout with three sets. You decide at Finish whether your saved workout keeps them.")
                        .font(.community(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = store.persistenceError {
                        Text(error).font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
                    }
                    ExerciseCatalogPicker(
                        isSelected: isInSession,
                        onToggle: { option in
                            // Checked means it is already in the session. A
                            // second card for it is never what tapping that
                            // row asks for; removing one is the card's menu.
                            guard !isInSession(option) else { return }
                            add(Exercise(
                                serverID: option.serverID,
                                serverName: option.serverID == nil ? nil : option.name,
                                name: option.name,
                                sets: 3
                            ))
                        },
                        onCreate: { name in add(Exercise(name: name, sets: 3)) },
                        phase: .focus,
                        pendingCustomNames: added
                    )
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) {
                if !store.addingExerciseNames.isEmpty {
                    ProgressView("Adding…")
                        .padding(14)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
            }
            .repbaseScreen(.focus)
        }
    }

    private func isInSession(_ option: ExerciseOption) -> Bool {
        added.contains { WorkoutSummary.matches($0, option.name) }
            || store.activeSession(on: day)?.exercises.contains {
                option.matches(serverID: $0.exerciseServerID, name: $0.name)
            } == true
    }

    private func add(_ exercise: Exercise) {
        guard !added.contains(where: { WorkoutSummary.matches($0, exercise.name) }) else { return }
        added.append(exercise.name)
        Task {
            if !(await store.addSessionExercise(exercise, on: day)) {
                added.removeAll { WorkoutSummary.matches($0, exercise.name) }
            }
        }
    }
}
