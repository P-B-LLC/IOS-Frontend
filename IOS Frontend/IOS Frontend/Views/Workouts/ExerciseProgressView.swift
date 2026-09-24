//
//  ExerciseProgressView.swift
//  IOS Frontend
//
//  Whether a lift is actually going anywhere, asked whenever you want to know.
//
//  The chart this shows already existed. It appeared when a session ended and
//  was cleared when the next one started, so seeing whether your bench press
//  had moved meant finishing a workout and not navigating away. The endpoint
//  behind it takes an optional workout name and had only ever been called with
//  one, which also meant the same lift trained under two workout names looked
//  like two shorter histories.
//
//  So: pick a lift, see all of it.
//

import SwiftUI

struct ExerciseProgressView: View {
    @Environment(WorkoutStore.self) private var store

    /// Opened straight onto one lift when the caller already knows which.
    var initialExercise: Exercise?

    @State private var selected: Exercise?

    var body: some View {
        let phase = WorkoutVisualPhase.recover

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(phase: phase)

                if store.trainedExercises.isEmpty {
                    empty(
                        "Nothing to plot yet",
                        detail: "Save a workout with exercises in it, then train it. Progress needs at least two sessions of the same lift before a line means anything."
                    )
                } else {
                    picker(phase: phase)
                    chart(phase: phase)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        // Keyed on the lifts, not run once. The saved workouts these are read
        // from may still be loading when this opens, and a plain `.task` would
        // find nothing, return, and never look again -- leaving the page
        // permanently empty on a cold start while the data sat right there.
        .task(id: store.trainedExercises.map(\.serverID)) {
            guard selected == nil else { return }
            // Whatever the caller asked for, else the first lift, so the page
            // opens on something rather than on a prompt to choose.
            guard let opening = initialExercise ?? store.trainedExercises.first else { return }
            selected = opening
            await store.loadProgress(for: opening)
        }
    }

    private func header(phase: WorkoutVisualPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR LIFTS")
                .font(.community(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(RepbaseDesign.warning)
            Text("Is it moving?")
                .font(.community(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(phase.primaryText)
            Text("Every session you have logged for one lift, across every workout it appears in.")
                .font(.community(.subheadline))
                .foregroundStyle(phase.secondaryText)
        }
    }

    private func picker(phase: WorkoutVisualPhase) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.trainedExercises) { exercise in
                    let isSelected = exercise.serverID == selected?.serverID
                    Button {
                        guard !isSelected else { return }
                        selected = exercise
                        Task { await store.loadProgress(for: exercise) }
                    } label: {
                        Text(exercise.name)
                            .font(.community(.subheadline, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                isSelected ? RepbaseDesign.ink : RepbasePalette.oatmeal.opacity(0.7),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? RepbasePalette.paper : phase.primaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func chart(phase: WorkoutVisualPhase) -> some View {
        if store.isLoadingBrowsedProgress {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, 60)
        } else if let message = store.browsedProgressError {
            empty("Couldn't load this lift", detail: message)
        } else if let series = store.browsedProgress {
            if series.hasEnoughToPlot {
                // The same chart the end of a session draws. One series,
                // because one lift is the whole question here.
                LiftProgressChart(series: [series], phase: phase)
                summary(series, phase: phase)
            } else {
                empty(
                    "Only one session so far",
                    detail: "\(series.exerciseName) needs a second session before there is a line to draw. Train it again and it will appear here."
                )
            }
        }
    }

    /// The two numbers the chart implies but does not state.
    private func summary(_ series: LiftProgressSeries, phase: WorkoutVisualPhase) -> some View {
        let heaviest = series.days.map(\.heaviestKilograms).max() ?? 0
        let first = series.days.first?.heaviestKilograms ?? 0
        let latest = series.days.last?.heaviestKilograms ?? 0
        let change = latest - first

        return HStack(spacing: 22) {
            stat("SESSIONS", value: "\(series.days.count)", phase: phase)
            stat("BEST SET", value: "\(Int(heaviest.rounded())) kg", phase: phase)
            stat(
                "SINCE THE FIRST",
                // Signed, because "+5 kg" and "5 kg" say different things and
                // only one of them is the answer to "is it moving".
                value: "\(change >= 0 ? "+" : "")\(Int(change.rounded())) kg",
                phase: phase
            )
        }
        .padding(.top, 4)
    }

    private func stat(_ label: String, value: String, phase: WorkoutVisualPhase) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.community(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(phase.secondaryText)
            Text(value)
                .font(.community(.title3, weight: .bold))
                .foregroundStyle(phase.primaryText)
        }
    }

    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.community(.headline))
            Text(detail)
                .font(.community(.subheadline))
                .foregroundStyle(WorkoutVisualPhase.recover.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .repbaseCard(contentPadding: 0, cornerRadius: 16)
    }
}
