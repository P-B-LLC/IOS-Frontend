import Foundation
import UserNotifications

/// Says when a rest is over while Rytivo is not on screen.
///
/// A rest is often spent somewhere else -- the phone locked in a pocket, or a
/// playlist open -- which is exactly when the in-app countdown cannot be seen
/// or heard. One notification is scheduled for the end date the timer itself
/// counts towards, and replaced whenever that date moves: pausing, skipping or
/// adjusting the rest moves or removes it, so it can never fire for a rest
/// that is no longer running.
@MainActor
final class RestTimerNotifier {
    nonisolated static let identifier = "rytivo.rest-timer"

    private let centre = UNUserNotificationCenter.current()
    private var scheduled: (restID: UUID, endsAt: Date)?
    private var askedForPermission = false

    func sync(session: ActiveWorkoutSession?, enabled: Bool) {
        guard enabled,
              let session,
              let timer = session.restTimer,
              timer.phase() == .running,
              let endsAt = timer.endsAt else {
            cancel()
            return
        }
        if let scheduled, scheduled.restID == timer.id, scheduled.endsAt == endsAt { return }
        schedule(endsAt: endsAt, restID: timer.id, session: session)
    }

    private func schedule(endsAt: Date, restID: UUID, session: ActiveWorkoutSession) {
        scheduled = (restID, endsAt)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest is over", bundle: .app, locale: .app)
        content.body = Self.nextSetText(in: session)
        content.sound = .default
        content.threadIdentifier = Self.identifier
        content.relevanceScore = 1
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, endsAt.timeIntervalSinceNow),
                repeats: false
            )
        )
        // Adding under the same identifier replaces the previous request.
        centre.add(request) { _ in }
        requestPermissionIfNeeded()
    }

    func cancel() {
        guard scheduled != nil else { return }
        scheduled = nil
        centre.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        centre.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    /// Asks once, the first time a rest actually starts, rather than at
    /// launch: that is the moment the reason for asking is obvious.
    private func requestPermissionIfNeeded() {
        guard !askedForPermission else { return }
        askedForPermission = true
        centre.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// "Next: Bench press, set 3 of 4"
    private static func nextSetText(in session: ActiveWorkoutSession) -> String {
        let exercise = session.focusedExerciseID.flatMap { id in session.exercises.first { $0.id == id } }
            ?? session.exercises.first { !$0.isComplete }
        guard let exercise,
              let index = exercise.sets.firstIndex(where: { !$0.isLogged }) else {
            return String(localized: "Time for your next set.", bundle: .app, locale: .app)
        }
        return String(
            localized: "Next: \(exercise.displayName), set \(index + 1) of \(exercise.sets.count)",
            bundle: .app,
            locale: .app,
            comment: "Rest-over notification. The first placeholder is an exercise name"
        )
    }
}
