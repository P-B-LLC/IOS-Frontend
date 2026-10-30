import Foundation
import SwiftUI
import UIKit

/// The review of a lifting session just finished: time, sets, volume, and
/// every exercise with the sets it logged, in the order they were trained.
///
/// The live session itself is `ActiveLiftingSessionView`.
struct WorkoutCompletionSummary: View {
    let completed: CompletedWorkoutSession
    let onDone: () -> Void
    @Environment(WorkoutStore.self) private var store
    private let phase = WorkoutVisualPhase.recover
    private var session: ActiveWorkoutSession { completed.session }
    private var unit: WorkoutWeightUnit { store.preferences.weightUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Workout complete").font(.community(.headline))
                Spacer()
                Button("Done", action: onDone).foregroundStyle(phase.accent)
            }
            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundStyle(phase.accent)
            Text("You showed up.\nThat counts.").font(.community(.largeTitle, weight: .bold))
            Text("\(session.workoutName) · \(session.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app)))")
                .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
            HStack(spacing: 12) {
                metric("Workout time", duration)
                metric("Sets logged", "\(session.loggedSetCount) / \(session.totalSetCount)")
                if session.loggedVolumeKilograms > 0 {
                    metric("Volume", unit.formatted(kilograms: session.loggedVolumeKilograms))
                }
            }
            HStack {
                Text("Your effort, logged.").font(.community(.title3, weight: .bold))
                Spacer()
                WeightUnitToggle(compact: true)
            }
            ForEach(session.exercises) { exercise in
                let count = exercise.sets.filter(\.isLogged).count
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: count == exercise.sets.count && count > 0 ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .foregroundStyle(count == exercise.sets.count && count > 0 ? RepbaseDesign.success : phase.secondaryText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.community(.headline))
                        Text("\(count) of \(exercise.sets.count) sets logged").font(.community(.caption)).foregroundStyle(phase.secondaryText)
                        if let line = loggedLine(exercise) {
                            Text(line)
                                .font(.community(.caption, weight: .medium).monospacedDigit())
                                .foregroundStyle(phase.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Label("Workout saved to your history.", systemImage: "checkmark")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            Button(action: onDone) {
                HStack { Text("Back to workouts"); Spacer(); Image(systemName: "arrow.forward") }
            }.buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
        }
    }

    /// "W 40 × 10 · 60 × 8 · 60 × 8", the logged sets in the unit shown.
    private func loggedLine(_ exercise: SessionExerciseDraft) -> String? {
        let parts = exercise.sets.filter(\.isLogged).compactMap { set -> String? in
            let weight = Decimal(string: set.weightKilograms)
            let summary = PreviousSet(setNumber: set.setNumber, weightKilograms: weight, reps: Int(set.reps)).summary(in: unit)
            guard let summary else { return nil }
            return set.setType.badge.map { "\($0) \(summary)" } ?? summary
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private var duration: String {
        let seconds = max(0, Int(completed.endedAt.timeIntervalSince(session.startedAt)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.community(.title2, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.community(.caption)).foregroundStyle(phase.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).workoutOutline(radius: 16)
    }
}
