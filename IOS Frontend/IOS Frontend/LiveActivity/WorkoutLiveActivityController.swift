//
//  WorkoutLiveActivityController.swift
//  IOS Frontend
//
//  Starts, updates and ends the Lock Screen activity for a lifting session.
//

import ActivityKit
import Foundation

/// Keeps one Live Activity in step with the session in progress.
///
/// Driven entirely from the session's state: it is told what the session looks
/// like after every change and works out the rest. That is what keeps the Lock
/// Screen and the app from drifting -- there is no second record of "where the
/// workout is" to fall out of step, only a picture of the one the app checkpoints.
///
/// Updates are coalesced. Typing a weight changes the session on every
/// keystroke, and the Lock Screen only needs the value somebody stopped at.
@MainActor
final class WorkoutLiveActivityController {
    private typealias State = WorkoutActivityAttributes.ContentState

    private var activity: Activity<WorkoutActivityAttributes>?
    private var activitySessionID: Int?
    private var lastState: State?
    private var pending: Task<Void, Never>?

    func sync(
        session: ActiveWorkoutSession?,
        enabled: Bool,
        unit: WorkoutWeightUnit,
        previous: (SessionExerciseDraft, Int) -> PreviousSet?
    ) {
        guard enabled, let session else {
            endActivity()
            return
        }
        let state = Self.state(for: session, unit: unit, previous: previous)
        guard state != lastState || activitySessionID != session.serverID else { return }
        lastState = state
        let attributes = WorkoutActivityAttributes(workoutName: session.workoutName, startedAt: session.startedAt)
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.apply(state, attributes: attributes, sessionID: session.serverID)
        }
    }

    /// Waits for the latest change to reach the Lock Screen, for an intent
    /// that must not return before the screen it was tapped on is updated.
    func flush() async {
        await pending?.value
    }

    private func apply(_ state: State, attributes: WorkoutActivityAttributes, sessionID: Int) async {
        let content = ActivityContent(
            state: state,
            // A rest that runs out while the app is suspended still has to
            // say so. Past this date the system marks the activity stale and
            // the view shows the rest as over, with no update needed.
            staleDate: state.phase == .resting ? state.restEndsAt : nil,
            relevanceScore: 100
        )
        if activity == nil || activitySessionID != sessionID {
            adoptExisting(sessionID: sessionID)
        }
        if let activity, activitySessionID == sessionID {
            await activity.update(content)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activitySessionID = sessionID
        } catch {
            // Only possible while the app is in front, and refused when the
            // person has turned Live Activities off. Either way the next
            // change tries again, and the workout itself is unaffected.
            lastState = nil
        }
    }

    /// An activity outlives the process that started it, so after a relaunch
    /// the one already on the Lock Screen is picked up rather than a second
    /// started beside it. Any belonging to a different session are ended.
    private func adoptExisting(sessionID: Int) {
        for existing in Activity<WorkoutActivityAttributes>.activities {
            if existing.content.state.sessionID == sessionID, activity == nil {
                activity = existing
                activitySessionID = sessionID
            } else if existing.id != activity?.id {
                Task { await existing.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    private func endActivity() {
        pending?.cancel()
        pending = nil
        lastState = nil
        let ending = Activity<WorkoutActivityAttributes>.activities
        activity = nil
        activitySessionID = nil
        guard !ending.isEmpty else { return }
        Task {
            for activity in ending {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// A tap that arrived before the session could be restored -- the app was
    /// launched in the background to run it, and is still signing in. The
    /// countdown is changed on the Lock Screen directly so the tap visibly
    /// worked; the restored session's own timer is what counts once it loads.
    func applyWithoutSession(_ action: WorkoutActivityAction) async {
        guard let current = Activity<WorkoutActivityAttributes>.activities.first(where: {
            $0.content.state.sessionID == action.sessionID
        }) else { return }
        var state = current.content.state
        let now = Date()
        switch action {
        case .completeSet:
            return
        case .skipRest:
            state.phase = .lifting
            state.restEndsAt = nil
            state.restStartedAt = nil
            state.restPausedRemaining = nil
        case .toggleRest:
            if let left = state.restPausedRemaining {
                state.phase = .resting
                state.restPausedRemaining = nil
                state.restEndsAt = now.addingTimeInterval(left)
                state.restStartedAt = state.restEndsAt?.addingTimeInterval(-(state.restTotalSeconds ?? left))
            } else if let end = state.restEndsAt {
                state.phase = .paused
                state.restPausedRemaining = max(0, end.timeIntervalSince(now))
                state.restEndsAt = nil
            }
        case .addRest(_, _, let seconds):
            if let end = state.restEndsAt {
                state.restEndsAt = end.addingTimeInterval(TimeInterval(seconds))
                state.restTotalSeconds = (state.restTotalSeconds ?? 0) + TimeInterval(seconds)
            } else if let left = state.restPausedRemaining {
                state.restPausedRemaining = left + TimeInterval(seconds)
            }
        }
        await current.update(ActivityContent(
            state: state,
            staleDate: state.phase == .resting ? state.restEndsAt : nil,
            relevanceScore: 100
        ))
    }

    // MARK: - What the Lock Screen shows

    private static func state(
        for session: ActiveWorkoutSession,
        unit: WorkoutWeightUnit,
        previous: (SessionExerciseDraft, Int) -> PreviousSet?
    ) -> State {
        let exercise = session.focusedExerciseID.flatMap { id in session.exercises.first { $0.id == id } }
            ?? session.exercises.first { !$0.isComplete }
            ?? session.exercises.first
        let position = exercise.flatMap { current in session.exercises.firstIndex { $0.id == current.id } } ?? 0
        let setIndex = exercise?.sets.firstIndex { !$0.isLogged }
        let set = setIndex.flatMap { exercise?.sets[$0] }
        let hint = exercise.flatMap { exercise in setIndex.flatMap { previous(exercise, $0) } }
        let allDone = session.totalSetCount > 0 && session.loggedSetCount == session.totalSetCount

        var phase: State.Phase = allDone ? .done : .lifting
        let timer = session.restTimer
        switch timer?.phase() {
        case .running?: phase = .resting
        case .paused?: phase = .paused
        default: break
        }

        let setTitle: String = {
            guard let exercise, let setIndex, let set else {
                return String(localized: "Every set is in", bundle: .app, locale: .app)
            }
            let base = String(
                localized: "Set \(setIndex + 1) of \(exercise.sets.count)",
                bundle: .app,
                locale: .app
            )
            guard set.setType != .normal else { return base }
            return String(
                localized: "\(set.setType.title) · \(base)",
                bundle: .app,
                locale: .app,
                comment: "A set's kind, then its place, such as “Warm-up set · Set 1 of 4”"
            )
        }()

        let weight = set.flatMap { $0.weightKilograms.isEmpty ? nil : Decimal(string: $0.weightKilograms) }
            ?? set.flatMap { set in exercise?.targetWeightKilograms(for: set) }.flatMap { Decimal(string: $0) }
            ?? hint?.weightKilograms
        let reps = set.flatMap { Int($0.reps) } ?? set.flatMap { set in exercise?.targetReps(for: set) } ?? hint?.reps
        let target: String? = switch (weight, reps) {
        case let (weight?, reps?): "\(unit.formatted(kilograms: weight)) × \(reps)"
        case let (nil, reps?): String(localized: "\(reps) reps", bundle: .app, locale: .app)
        case let (weight?, nil): unit.formatted(kilograms: weight)
        case (nil, nil): nil
        }

        let next: String? = {
            guard let exercise else { return nil }
            let after = session.exercises[(position + 1)...].first { !$0.isComplete && $0.id != exercise.id }
                ?? session.exercises.first { !$0.isComplete && $0.id != exercise.id }
            return after.map {
                String(localized: "Next: \(ExerciseLibrary.displayName($0.name))", bundle: .app, locale: .app, comment: "The exercise after the current one")
            }
        }()

        return State(
            phase: phase,
            sessionID: session.serverID,
            exerciseName: exercise.map { ExerciseLibrary.displayName($0.name) } ?? session.workoutName,
            exercisePosition: String(
                localized: "Exercise \(position + 1) of \(session.exercises.count)",
                bundle: .app,
                locale: .app
            ),
            setTitle: setTitle,
            setBadge: set?.setType.badge,
            targetText: target,
            previousText: hint?.summary(in: unit).map {
                String(localized: "Last time \($0)", bundle: .app, locale: .app, comment: "What was lifted last time, such as “Last time 60 × 8”")
            },
            nextText: next,
            loggedSets: session.loggedSetCount,
            totalSets: session.totalSetCount,
            progressText: String(
                localized: "\(session.loggedSetCount) of \(session.totalSetCount) sets",
                bundle: .app,
                locale: .app
            ),
            restEndsAt: phase == .resting ? timer?.endsAt : nil,
            restStartedAt: phase == .resting ? timer?.startedAt : nil,
            restPausedRemaining: phase == .paused ? timer?.remaining() : nil,
            restTotalSeconds: timer?.totalSeconds,
            exerciseID: exercise?.id.uuidString,
            setID: set?.id.uuidString,
            restID: timer?.id.uuidString,
            canCompleteSet: set != nil && reps != nil && (set?.isWeightValid ?? false),
            labels: labels
        )
    }

    private static var labels: WorkoutActivityAttributes.Labels {
        WorkoutActivityAttributes.Labels(
            rest: String(localized: "Rest", bundle: .app, locale: .app, comment: "Live Activity: the rest timer is running"),
            restPaused: String(localized: "Rest paused", bundle: .app, locale: .app),
            restOver: String(localized: "Rest is over", bundle: .app, locale: .app),
            completeSet: String(localized: "Complete set", bundle: .app, locale: .app),
            pause: String(localized: "Pause", bundle: .app, locale: .app),
            resume: String(localized: "Resume", bundle: .app, locale: .app),
            skip: String(localized: "Skip", bundle: .app, locale: .app, comment: "Ends the rest timer now"),
            addTime: String(localized: "+15s", bundle: .app, locale: .app, comment: "Adds fifteen seconds to the rest timer"),
            workoutDone: String(localized: "Every set is in. Finish in Rytivo.", bundle: .app, locale: .app),
            openToContinue: String(localized: "Open Rytivo to log this set", bundle: .app, locale: .app),
            restEndsAt: String(localized: "Rest ends at", bundle: .app, locale: .app, comment: "Live Activity, above the time a rest ends, such as 9:41")
        )
    }
}
