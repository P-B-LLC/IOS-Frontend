//
//  SavedWorkoutsView.swift
//  IOS Frontend
//
//  The workouts already built, ready to be put on another day.
//
//  Reusing one schedules it. The template is not copied, rewritten, or moved:
//  its exercises, the rows joining them to it, and their target sets stay
//  exactly as they are, and it keeps whatever other days it is already
//  planned on.
//

import SwiftUI

struct SavedWorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var scheduling: Int?
    @State private var failureMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RepbaseScreenHeader(
                    eyebrow: "YOUR LIBRARY",
                    title: "Saved workouts",
                    detail: "Choose a plan and place it on your week."
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PLAN FOR")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(RepbasePalette.caramel)
                        Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.community(.headline))
                    }
                    Spacer()
                    DatePicker("Add to", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityHint("The day the workout you pick will be added to")

                if let failureMessage {
                    Text(failureMessage)
                        .font(.community(.footnote))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The server's refusal, which names the rotation in the way.
                if let message = store.persistenceError {
                    Text(message)
                        .font(.community(.footnote))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.knownWorkouts.isEmpty {
                    empty
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.knownWorkouts.enumerated()), id: \.element.id) { index, workout in
                            row(workout)
                            if index < store.knownWorkouts.count - 1 { Divider().opacity(0.45) }
                        }
                    }

                    Text("Deleting a saved workout also removes the days it is planned on. Training you have already done stays in your history, and a workout a rotation is built from cannot be deleted until the rotation changes.")
                        .font(.community(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .repbaseScreen(.prepare)
        .navigationTitle("Saved workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No saved workouts yet")
                .font(.community(.subheadline, weight: .semibold))
            Text("Build a workout on any day and it will be here to reuse.")
                .font(.community(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func row(_ workout: WorkoutSummary) -> some View {
        HStack(spacing: 14) {
            ActivityIconArtwork(
                kind: workout.type.activityIcon,
                size: 22,
                color: RepbasePalette.caramel
            )
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(workout.name)
                    .font(.community(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text(detail(workout))
                    .font(.community(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await add(workout) }
            } label: {
                Group {
                    if scheduling == workout.serverID {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                            .font(.community(.footnote, weight: .semibold))
                    }
                }
                .frame(minWidth: 52, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            // One at a time. Two taps in flight would schedule the same
            // workout on the same day twice.
            .disabled(scheduling != nil || store.isSaving)

            // Set apart from Add rather than beside it. The two do opposite
            // things and a thumb that misses by a few points should not
            // delete the workout it meant to plan.
            Button {
                Task { await store.deleteSavedWorkout(workout) }
            } label: {
                Image(systemName: "trash")
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(RepbaseDesign.danger)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isSaving)
            .padding(.leading, 6)
            .accessibilityLabel("Delete \(workout.name)")
            .accessibilityLabel("Add \(workout.name)")
            .accessibilityHint("Schedules it on \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        .padding(.vertical, 12)
    }

    private func detail(_ workout: WorkoutSummary) -> String {
        guard !workout.exercises.isEmpty else { return workout.type.title }
        let sets = workout.exercises.reduce(0) { $0 + $1.sets }
        return "\(workout.exercises.count) exercises · \(sets) target sets"
    }

    private func add(_ workout: WorkoutSummary) async {
        guard scheduling == nil else { return }
        scheduling = workout.serverID
        failureMessage = nil
        defer { scheduling = nil }

        if await store.scheduleKnownWorkout(workout, on: date) {
            dismiss()
        } else {
            // Stays open, saying so. Closing on a failure would look like it
            // worked until the day was opened and found empty.
            failureMessage = store.persistenceError
                ?? "That workout could not be added to the day."
        }
    }
}
