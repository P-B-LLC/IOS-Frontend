//
//  SessionFeedbackCard.swift
//  IOS Frontend
//
//  "How did it feel?", asked once a session recorded live has finished.
//

import SwiftUI

/// Effort, and the activity's own questions, for a session that has just
/// been recorded live.
///
/// The time is already known -- the session measured it -- so this asks only
/// what the phone could not: how hard it felt, the activity's details, and
/// for an indoor ride or a pool swim the distance nothing measured. All of it
/// optional; the session is saved whether or not this is.
struct SessionFeedbackCard: View {
    let sessionID: Int
    let activity: WorkoutActivity
    /// True only where no GPS or Health distance exists to be typed over.
    let asksDistance: Bool
    var phase: WorkoutVisualPhase = .recover
    @Environment(WorkoutStore.self) private var store
    @State private var draft: ActivityLogDraft
    @State private var isSaving = false
    @State private var problem: String?
    @State private var savedDraft: ActivityLogDraft?

    init(sessionID: Int, activity: WorkoutActivity, asksDistance: Bool, phase: WorkoutVisualPhase = .recover) {
        self.sessionID = sessionID
        self.activity = activity
        self.asksDistance = asksDistance
        self.phase = phase
        _draft = State(initialValue: ActivityLogDraft(activity: activity))
    }

    private var questions: Set<ActivityLogFields.Question> {
        // Lifting is rated, not described: its sets already say what it was.
        var asks: Set<ActivityLogFields.Question> = activity.usesSets ? [.effort, .notes] : [.effort, .details, .calories, .notes]
        if asksDistance { asks.insert(.distance) }
        return asks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How did it feel?")
                    .font(.community(.title3, weight: .bold))
                Text("Optional. Rate the session while it’s fresh.")
                    .font(.community(.caption))
                    .foregroundStyle(phase.secondaryText)
            }

            ActivityLogFields(draft: $draft, asks: questions, phase: phase)

            if let problem {
                Text(problem).font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
            }

            Button(action: save) {
                HStack {
                    if isSaving { ProgressView() }
                    Text(savedDraft == draft ? "Saved" : "Save")
                    Spacer()
                    Image(systemName: savedDraft == draft ? "checkmark.circle.fill" : "checkmark")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
            .disabled(isSaving || savedDraft == draft || !hasAnswers)
            .accessibilityIdentifier("session-feedback-save")
        }
        .padding(16)
        .workoutOutline(radius: 20)
        .onChange(of: draft) { problem = nil }
    }

    private var hasAnswers: Bool {
        draft.perceivedEffort != nil || !draft.calories.isEmpty || !draft.notes.isEmpty
            || !draft.distance.isEmpty || !draft.details.isEmpty
    }

    private func save() {
        var feedback = SessionFeedback(perceivedEffort: draft.perceivedEffort, details: draft.details.sanitized(for: activity))
        feedback.notes = String(draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ActivityLogDraft.maximumNotesLength))
        let caloriesText = draft.calories.trimmingCharacters(in: .whitespaces)
        if !caloriesText.isEmpty {
            guard let calories = Int(caloriesText), ActivityLogDraft.caloriesRange.contains(calories) else {
                problem = ActivityLogDraft.Problem.invalidCalories.message
                return
            }
            feedback.caloriesKilocalories = calories
        }
        if asksDistance {
            switch draft.distanceKilometers {
            case .blank: break
            case .invalid:
                problem = ActivityLogDraft.Problem.invalidDistance.message
                return
            case .value(let kilometers): feedback.distanceKilometers = kilometers
            }
        }
        isSaving = true
        problem = nil
        let attempted = draft
        Task {
            defer { isSaving = false }
            if let failure = await store.saveSessionFeedback(feedback, sessionID: sessionID) {
                problem = failure
            } else {
                savedDraft = attempted
            }
        }
    }
}
