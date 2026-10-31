//
//  UpcomingDayView.swift
//  IOS Frontend
//
//  Planning a day after this week, up to a week from today.
//

import SwiftUI

/// A day after this week that a workout can be planned on.
///
/// The week strip ends on Sunday, so from a Friday most of the next seven
/// days are next week's. They open here, for planning only: nothing can be
/// started or logged on a day that has not come yet. When the day's week
/// arrives it opens in `DayWorkoutView` like every other day, with whatever
/// was planned here already on it.
struct UpcomingDayView: View {
    let date: Date

    @Environment(WorkoutStore.self) private var store
    @State private var editor: WorkoutEditorView.Mode?
    @State private var choosingSaved = false
    @State private var confirmation: String?
    @State private var highlightedWorkoutID: Workout.ID?

    private let phase = WorkoutVisualPhase.prepare

    private var workouts: [Workout] { store.workouts(onDate: date) }

    private var weekday: Weekday? {
        Weekday(calendarWeekday: Calendar.current.component(.weekday, from: date))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(RepbaseDesign.success)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RepbaseDesign.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("upcoming-day-confirmation")
                }
                if let error = store.persistenceError {
                    errorCard(error)
                }
                ForEach(workouts) { workout in
                    plannedWorkout(workout)
                }
                actions
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.vertical, 12)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .repbaseScreen(.prepare)
        .navigationTitle(date.formatted(.dateTime.weekday(.wide).locale(.app)))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $editor) { mode in
            WorkoutEditorView(
                mode: mode,
                suggestions: store.knownWorkouts,
                recoveryContext: WorkoutStore.dateString(date),
                onSaved: save
            )
        }
        .sheet(isPresented: $choosingSaved) {
            SavedWorkoutChooser(date: date) { confirmation = $0 }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(.app)).uppercased(with: .app))
                .font(.community(.caption2, weight: .bold))
                .tracking(1)
                .foregroundStyle(phase.accent)
                .accessibilityIdentifier("upcoming-day-date")
            Text("Your workouts.")
                .font(.community(.largeTitle, weight: .bold))
            Text("Plan it now and start it on the day.")
                .font(.community(.subheadline))
                .foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func plannedWorkout(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: workout.activity.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(phase.accent)
                    .frame(width: 42, height: 42)
                    .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                Text(workout.activity.title.uppercased(with: .app))
                    .font(.community(.caption2, weight: .bold))
                    .foregroundStyle(phase.secondaryText)
                Spacer(minLength: 8)
                Label("Planned", systemImage: "calendar.badge.checkmark")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(RepbaseDesign.success)
            }
            Text(workout.name)
                .font(.community(.title2, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                        PlannedExerciseRow(position: index + 1, exercise: exercise)
                        if index < workout.exercises.count - 1 { Divider() }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Edit") { editor = .edit(workout) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Edit \(workout.name)")
                Button(role: .destructive) {
                    confirmation = nil
                    store.removeWorkout(workout, onDate: date)
                } label: {
                    Label("Remove from this day", systemImage: "calendar.badge.minus")
                }
                .buttonStyle(.bordered)
            }
            .font(.community(.subheadline, weight: .semibold))
            .disabled(!store.isEditingEnabled)
            Text("Your saved workout and recorded training are kept.")
                .font(.community(.caption2))
                .foregroundStyle(phase.secondaryText)
        }
        .modifier(DayWorkoutCardSurface(highlighted: workout.id == highlightedWorkoutID))
        .accessibilityIdentifier("upcoming-workout-\(workout.name)")
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                confirmation = nil
                editor = .create
            } label: {
                Label("Create a workout", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: .prepare))
            .accessibilityIdentifier("upcoming-day-create")

            Button {
                confirmation = nil
                choosingSaved = true
            } label: {
                Label("Add a saved workout", systemImage: "clock.arrow.circlepath")
                    .font(.community(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(store.knownWorkouts.isEmpty)
            .accessibilityIdentifier("upcoming-day-add-saved")

            if let reason = store.editingBlockedReason {
                Text(reason).font(.community(.caption)).foregroundStyle(phase.secondaryText)
            } else {
                Text("Plan up to 7 days ahead.")
                    .font(.community(.caption))
                    .foregroundStyle(phase.secondaryText)
            }
        }
        .disabled(!store.isEditingEnabled)
        .padding(.top, 6)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.community(.footnote))
                .foregroundStyle(Color.orange)
            Button("Retry") { store.retryPersistence() }
                .font(.community(.footnote, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func save(_ workout: Workout) async -> String? {
        let problem = await store.saveWorkoutReportingFailure(workout, onDate: date)
        if problem == nil {
            highlightedWorkoutID = store.lastSavedWorkoutID
            if let weekday {
                confirmation = DayWorkoutView.savedMessage(workout.name, on: weekday)
            }
        }
        return problem
    }
}

/// The saved workouts, to put one on an upcoming day as it is.
private struct SavedWorkoutChooser: View {
    let date: Date
    let onAdded: (String) -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var adding: Int?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Text(failure)
                        .font(.community(.footnote))
                        .foregroundStyle(RepbaseDesign.warning)
                }
                if store.knownWorkouts.isEmpty {
                    Text("Your saved workouts will appear here.")
                        .font(.community(.subheadline))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.knownWorkouts) { workout in
                    Button {
                        Task { await add(workout) }
                    } label: {
                        HStack {
                            Label(workout.name, systemImage: workout.activity.symbol)
                            Spacer()
                            if adding == workout.serverID { ProgressView() }
                        }
                    }
                    .disabled(adding != nil || store.isSaving)
                }
            }
            .navigationTitle("Your saved workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ workout: WorkoutSummary) async {
        guard adding == nil else { return }
        adding = workout.serverID
        failure = nil
        defer { adding = nil }
        if await store.scheduleKnownWorkout(workout, on: date) {
            onAdded(String(
                localized: "\(workout.name) added to \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(.app))).",
                bundle: .app,
                locale: .app
            ))
            dismiss()
        } else {
            failure = store.persistenceError
                ?? String(localized: "That workout could not be added to the day.", bundle: .app, locale: .app)
        }
    }
}
