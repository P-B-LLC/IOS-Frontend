import Foundation
import ActivityKit
import WidgetKit
import UIKit

@MainActor
enum ActiveWorkoutWidgetPublisher {
    static private(set) var current: ActiveWorkoutWidgetState?
    private static var updateTask: Task<Void, Never>?
    static func flush() async { await updateTask?.value }

    static func refresh(_ store: WorkoutStore) {
        var next: ActiveWorkoutWidgetState?
        if let session = store.activeSession, !session.tracksDistance, store.isConnected {
            let position = WorkoutWidgetControls.nextSet(in: session.exercises.map { $0.sets.map(\.isLogged) })
            let exercise = position.map { session.exercises[$0.exercise] }
            let set = position.map { session.exercises[$0.exercise].sets[$0.set] }
            next = .init(
                revision: UUID().uuidString, sessionID: session.id.uuidString,
                workout: String(session.workoutName.prefix(80)),
                exercise: String((exercise?.name ?? "Ready to finish").prefix(80)),
                setID: set?.id.uuidString ?? "", setNumber: set?.setNumber ?? 0,
                setCount: exercise?.sets.count ?? 0,
                weight: set?.weightKilograms ?? "", reps: set?.reps ?? "",
                startedAt: session.startedAt, updatedAt: Date(),
                logged: session.loggedSetCount, total: session.totalSetCount,
                busy: store.isSaving || !store.pendingSetIDs.isEmpty,
                message: store.persistenceError.map { String($0.prefix(160)) }
            )
        }
        if var comparable = next, let current {
            comparable.revision = current.revision
            comparable.updatedAt = current.updatedAt
            if comparable == current && Date().timeIntervalSince(current.updatedAt) < 900 { return }
        }
        current = next
        if let file = ActiveWorkoutWidgetState.file {
            if let next, let data = try? JSONEncoder().encode(next) {
                try? data.write(to: file, options: [.atomic, .completeFileProtection])
            } else {
                try? Data().write(to: file, options: [.atomic, .completeFileProtection])
                try? FileManager.default.removeItem(at: file)
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "com.pbllc.rytivo.activeWorkout")
        // Serialize ActivityKit updates, including teardown, so older updates
        // cannot resurrect a previous session after logout or a new workout.
        let previous = updateTask
        updateTask = Task {
            await previous?.value
            for activity in Activity<WorkoutActivityAttributes>.activities {
                if let next, activity.attributes.sessionID == next.sessionID {
                    await activity.update(ActivityContent(state: next, staleDate: next.updatedAt.addingTimeInterval(3600)))
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            guard let next, current?.revision == next.revision,
                  UIApplication.shared.applicationState == .active,
                  ActivityAuthorizationInfo().areActivitiesEnabled,
                  !Activity<WorkoutActivityAttributes>.activities.contains(where: { $0.attributes.sessionID == next.sessionID }) else { return }
            _ = try? Activity<WorkoutActivityAttributes>.request(attributes: WorkoutActivityAttributes(sessionID: next.sessionID),
                content: ActivityContent(state: next, staleDate: next.updatedAt.addingTimeInterval(3600)), pushType: nil)
        }
    }
}
