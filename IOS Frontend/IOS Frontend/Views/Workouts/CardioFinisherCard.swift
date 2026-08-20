//
//  CardioFinisherCard.swift
//  IOS Frontend
//
//  Starting, timing, and saving the cardio that follows a workout.
//

import SwiftUI

/// Shown on the summary after a lifting session. The finisher is timed here
/// and written onto the session that just ended, so the workout and the cardio
/// after it stay one training session.
struct CardioFinisherCard: View {
    let plannedMachine: CardioMachine?
    let sessionID: Int
    let phase: WorkoutVisualPhase

    @Environment(WorkoutStore.self) private var store
    @State private var machine: CardioMachine
    @State private var distanceText = ""
    @State private var isSaving = false

    init(
        plannedMachine: CardioMachine?,
        sessionID: Int,
        phase: WorkoutVisualPhase
    ) {
        self.plannedMachine = plannedMachine
        self.sessionID = sessionID
        self.phase = phase
        _machine = State(initialValue: plannedMachine ?? .treadmill)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let seconds = store.recordedCardioSeconds {
                saved(seconds: seconds)
            } else if store.isTimingCardio {
                running
            } else {
                idle
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.recordedCardioSeconds == nil ? "CARDIO FINISHER" : "CARDIO COMPLETE")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(phase.accent)
            Text(
                store.recordedCardioSeconds == nil
                    ? "Keep the momentum going."
                    : "Finisher saved."
            )
            .font(.title3.weight(.bold))
        }
    }

    // MARK: - States

    private var idle: some View {
        VStack(alignment: .leading, spacing: 11) {
            // A planned machine is preselected, but the user may have ended up
            // on a different one.
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(CardioMachine.allCases) { option in
                        Button {
                            machine = option
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(machine == option ? .semibold : .regular))
                                .padding(.vertical, 8)
                            .foregroundStyle(
                                machine == option ? phase.primaryText : phase.secondaryText
                            )
                            .overlay(alignment: .bottom) {
                                if machine == option {
                                    Capsule()
                                        .fill(phase.primaryText)
                                        .frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button {
                store.startCardio(machine: machine, sessionID: sessionID)
            } label: {
                HStack(spacing: 8) {
                    Text("Start \(machine.title.lowercased())")
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
            .disabled(!store.isEditingEnabled)
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(machineInProgress.title, systemImage: machineInProgress.symbolName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let started = store.cardioStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(from: started, to: context.date))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(phase.accent)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Distance")
                    .font(.caption)
                    .foregroundStyle(phase.secondaryText)
                TextField("Optional", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                Text("mi")
                    .font(.caption)
                    .foregroundStyle(phase.secondaryText)
            }

            Text("Read it off the machine if you want it recorded.")
                .font(.caption2)
                .foregroundStyle(phase.secondaryText)

            Button {
                Task {
                    isSaving = true
                    // Typed in miles, stored in kilometres like every other
                    // distance. Converting at the edge keeps one unit below
                    // the screen, which is the only way the sums stay right.
                    await store.finishCardio(
                        distanceKilometers: Double(
                            distanceText.trimmingCharacters(in: .whitespaces)
                        ).map { $0 * ImperialUnits.metersPerMile / 1000 }
                    )
                    isSaving = false
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        HStack(spacing: 8) {
                            Text("Finish cardio")
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                        }
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
            .disabled(isSaving)
        }
    }

    private func saved(seconds: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(machineInProgress.title)
                    .font(.subheadline.weight(.semibold))
                Text("Saved with your workout")
                    .font(.caption2)
                    .foregroundStyle(phase.secondaryText)
            }
            Spacer(minLength: 0)
            Text(durationText(seconds))
                .font(.title3.weight(.bold).monospacedDigit())
        }
    }

    private var machineInProgress: CardioMachine {
        store.cardioMachine ?? machine
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        durationText(max(0, Int(end.timeIntervalSince(start))))
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
