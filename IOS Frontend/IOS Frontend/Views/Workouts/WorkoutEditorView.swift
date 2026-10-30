//
//  WorkoutEditorView.swift
//  IOS Frontend
//
//  Create or edit a workout plan.
//

import SwiftUI

struct WorkoutEditorView: View {
    enum Mode: Identifiable {
        case create
        case build(Workout)
        case edit(Workout)

        var id: String {
            switch self {
            case .create: return "create"
            case .build(let workout): return "build-\(workout.id.uuidString)"
            case .edit(let workout): return workout.id.uuidString
            }
        }
    }

    let mode: Mode
    private let recoveryContext: String
    /// Existing workout names, passed in rather than read from the
    /// environment so previews stand alone.
    var suggestions: [WorkoutSummary] = []
    var onSaved: ((Workout) async -> String?)?
    /// Logging a finished activity straight to history, where there is a day
    /// to log it on. Answers a problem to show, or nil once it is saved.
    var onLogged: ((ActivityLogEntry) async -> String?)?
    var logDefaultEnd = Date()
    var logFinishedRange: ClosedRange<Date> = Date.distantPast...Date()
    var logDistanceUnit: ActivityLogDraft.DistanceUnit = .kilometers

    @State private var isSaving = false
    @State private var saveError: String?
    @State private var draftSaved = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Workout

    init(
        mode: Mode,
        suggestions: [WorkoutSummary] = [],
        recoveryContext: String = "library",
        onSaved: ((Workout) async -> String?)? = nil,
        onLogged: ((ActivityLogEntry) async -> String?)? = nil,
        logDefaultEnd: Date = Date(),
        logFinishedRange: ClosedRange<Date> = Date.distantPast...Date(),
        logDistanceUnit: ActivityLogDraft.DistanceUnit = .kilometers
    ) {
        self.mode = mode
        self.suggestions = suggestions
        self.recoveryContext = recoveryContext
        self.onSaved = onSaved
        self.onLogged = onLogged
        self.logDefaultEnd = logDefaultEnd
        self.logFinishedRange = logFinishedRange
        self.logDistanceUnit = logDistanceUnit
        switch mode {
        case .create:
            _draft = State(initialValue: Workout(name: "", exercises: []))
        case .build(let workout):
            _draft = State(initialValue: workout)
        case .edit(let workout):
            _draft = State(initialValue: workout)
        }
    }


    private var recoveryKey: String {
        switch mode {
        case .create, .build:
            return "workout-new-\(recoveryContext)"
        case .edit(let workout):
            return "workout-edit-\(workout.serverID.map(String.init) ?? workout.id.uuidString)"
        }
    }


    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            GuidedWorkoutBuilder(
                draft: $draft,
                suggestions: suggestions,
                startsAtReview: { if case .edit = mode { return true }; return false }(),
                isSaving: isSaving,
                onSave: save,
                logging: logging
            )
            .saveFeedback(isSaving: isSaving, error: saveError)
            .recoverableDraft(key: recoveryKey, value: $draft, saved: $draftSaved, error: $saveError,
                              confirmRestoration: true)
        }
    }


    /// Only when creating: editing a saved plan is never a log.
    private var logging: ActivityLogging? {
        if case .edit = mode { return nil }
        guard onLogged != nil else { return nil }
        return ActivityLogging(defaultEnd: logDefaultEnd, finishedRange: logFinishedRange, distanceUnit: logDistanceUnit, onLog: log)
    }

    private func log(_ entry: ActivityLogEntry) {
        guard !isSaving, let onLogged else { return }
        isSaving = true
        saveError = nil
        Task {
            defer { isSaving = false }
            if let problem = await onLogged(entry) { saveError = problem }
            else { draftSaved = true; dismiss() }
        }
    }

    private func save() {
        guard !isSaving, canSave, let onSaved else { return }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.exercises = draft.exercises.compactMap { exercise in
            var exercise = exercise
            exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return exercise.name.isEmpty ? nil : exercise
        }
        isSaving = true
        saveError = nil
        let savedDraft = draft
        Task {
            defer { isSaving = false }
            if let problem = await onSaved(savedDraft) { saveError = problem }
            else { draftSaved = true; dismiss() }
        }
    }
}

#Preview("Create") {
    WorkoutEditorView(mode: .create)
        .environment(WorkoutStore.previewWithLibrary)
}

#Preview("Edit") {
    WorkoutEditorView(mode: .edit(WorkoutStore.previewWorkouts[0]))
        .environment(WorkoutStore.previewWithLibrary)
}
