//
//  NotificationScheduler.swift
//  IOS Frontend
//
//  Every local notification the app raises, in one place.
//
//  Local rather than pushed, and that is a constraint rather than a choice:
//  these builds carry no APNs entitlement, so anything that arrives while the
//  app is closed has to have been scheduled on the device beforehand. That
//  works for reminders, which are all about a time already known. It does not
//  work for anything another person does, which is why the social side is a
//  page you open rather than something that buzzes.
//
//  Two different words that are easy to confuse:
//
//  * **Off** is a setting. Tasks, food or workouts stop raising notifications
//    entirely until it is turned back on.
//  * **Muted** is temporary and comes from the notification itself -- this one
//    task, or food for the rest of today. Tomorrow it is back.
//
//  Muting never turns the category off. That distinction is the whole reason
//  the mute state is kept separately from the settings toggles below.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: NSObject {
    static let shared = NotificationScheduler()

    // MARK: - What the settings page writes

    enum Setting {
        static let workouts = "notifications.training"
        static let food = "notifications.nutrition"
        static let tasks = "notifications.planner"
    }

    // MARK: - Categories and their actions

    enum Category {
        static let task = "rytivo.task"
        static let food = "rytivo.food"
        static let workout = "rytivo.workout"
    }

    private enum Action {
        static let muteTask = "rytivo.mute-task"
        static let muteFood = "rytivo.mute-food-today"
        static let muteWorkout = "rytivo.mute-workout-today"
    }

    private enum Key {
        static let owner = "notifications.accountID"
        static let mutedTasks = "notifications.mutedTaskIDs"
        static let foodMutedOn = "notifications.foodMutedOn"
        static let workoutMutedOn = "notifications.workoutMutedOn"
    }

    /// How long before a task or event each warning lands.
    ///
    /// Five of them, which is a lot for one thing -- but they are cheap while
    /// the day is still far off and the last two are the ones that actually
    /// move somebody. Anything already in the past when this runs is skipped
    /// rather than fired late.
    static let ladder: [Int] = [60, 30, 15, 5, 1]

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest, so the ladder cannot simply be scheduled for every task
    /// somebody has. The nearest few get the full ladder and the horizon moves
    /// forward each time this runs.
    private enum Budget {
        static let food = 3
        static let workoutDays = 7
        static let ladderedEntries = 10
    }

    private let defaults = UserDefaults.standard
    private let centre = UNUserNotificationCenter.current()
    private var accountID: Int?
    private var generation = UUID()
    @TaskLocal private static var schedulingGeneration: UUID?

    /// Invalidates all in-flight schedule writes before removing account data.
    func setAccount(_ id: Int?) {
        guard accountID != id || id == nil else { return }
        let previousOwner = defaults.object(forKey: Key.owner) as? Int
        accountID = id
        generation = UUID()
        if id == nil || previousOwner != id {
            centre.removeAllPendingNotificationRequests()
            centre.removeAllDeliveredNotifications()
            defaults.removeObject(forKey: Key.mutedTasks)
            defaults.removeObject(forKey: Key.foodMutedOn)
            defaults.removeObject(forKey: Key.workoutMutedOn)
        }
        if let id { defaults.set(id, forKey: Key.owner) }
        else { defaults.removeObject(forKey: Key.owner) }
        Task { await setBadge(0) }
    }

    // MARK: - Setting up

    /// Registers the categories and takes delivery of taps. Call once.
    func start() {
        centre.delegate = self
        centre.setNotificationCategories([
            category(
                Category.task,
                actionID: Action.muteTask,
                title: "Mute this task"
            ),
            category(
                Category.food,
                actionID: Action.muteFood,
                title: "Mute for today"
            ),
            category(
                Category.workout,
                actionID: Action.muteWorkout,
                title: "Mute for today"
            ),
        ])
    }

    private func category(
        _ id: String,
        actionID: String,
        title: String
    ) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: id,
            actions: [
                UNNotificationAction(
                    identifier: actionID,
                    title: title,
                    // Nothing is destroyed and nothing needs the app opened:
                    // the answer is recorded and the rest of the day is
                    // quieter.
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    // MARK: - Rebuilding the schedule

    /// Replaces everything this app had pending with what is true now.
    ///
    /// Rebuilt wholesale rather than patched. A task can move, be finished, be
    /// deleted or be muted, and reconciling each of those against what is
    /// already pending is far more code than simply saying what the schedule
    /// should be.
    func reschedule(
        entries: [PlannerEntry],
        untimedWorkouts: [PlannerEntry],
        now: Date = Date()
    ) async {
        guard accountID != nil, !Task.isCancelled else { return }
        let run = UUID()
        generation = run
        let settings = await centre.notificationSettings()
        guard generation == run, !Task.isCancelled else { return }
        // Checked before anything is torn down. Clearing first and then
        // discovering there is no permission to write replacements leaves the
        // schedule empty for no reason.
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }
        centre.removeAllPendingNotificationRequests()

        await Self.$schedulingGeneration.withValue(run) {
            if isOn(Setting.food) { await scheduleFood(now: now) }
            if isOn(Setting.workouts) {
                await scheduleWorkouts(untimedWorkouts, now: now)
            }
            if isOn(Setting.tasks) { await scheduleTasks(entries, now: now) }
        }
    }

    // MARK: - Tasks and events

    private func scheduleTasks(_ entries: [PlannerEntry], now: Date) async {
        // Keyed on the server id rather than the local one. Muting has to
        // outlive a refetch, and an entry with no server id has no identity
        // that would survive being asked for again -- so it is not scheduled
        // rather than scheduled under a name that changes.
        let muted = mutedTaskIDs
        let upcoming = entries
            .filter { !$0.isComplete || !$0.isCompletable }
            .compactMap { entry -> (Int, PlannerEntry, Date)? in
                guard let serverID = entry.serverID,
                      !muted.contains(serverID),
                      let due = Self.due(entry),
                      due > now
                else { return nil }
                return (serverID, entry, due)
            }
            .sorted { $0.2 < $1.2 }
            .prefix(Budget.ladderedEntries)

        for (serverID, entry, due) in upcoming {
            for minutes in Self.ladder {
                let fires = due.addingTimeInterval(TimeInterval(-minutes * 60))
                guard fires > now else { continue }
                await add(
                    id: "rytivo.task.\(serverID).\(minutes)",
                    title: Self.headline(for: entry),
                    body: Self.detail(for: entry, minutesAway: minutes),
                    at: fires,
                    category: Category.task,
                    userInfo: ["taskID": serverID]
                )
            }
        }
    }

    /// What the notification is about, named by what kind of thing it is.
    ///
    /// The title used to be the entry's own title and nothing else, which on a
    /// lock screen is a bare word with no way to tell what it belongs to --
    /// "Morning Run" could as easily have been a message. Saying which of the
    /// app's things it is costs a couple of words and answers that.
    static func headline(for entry: PlannerEntry) -> String {
        switch entry.kind {
        case .task: return "Upcoming Task: \(entry.title)"
        case .event: return "Upcoming Event: \(entry.title)"
        }
    }

    /// The line under it: how long, then the clock, then anything unusual.
    ///
    /// Ordered by what somebody glancing at it needs first. The countdown is
    /// the reason it arrived; the clock time is what they will check it
    /// against; the priority only appears when it is the one worth saying.
    static func detail(for entry: PlannerEntry, minutesAway: Int) -> String {
        var parts = [countdown(minutesAway)]
        if let when = entry.displayTimeRange ?? entry.displayTime {
            parts.append(when)
        }
        if entry.priority == .high { parts.append("High priority") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private static func countdown(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "In 1 hour"
        case 1: return "In 1 minute"
        default: return "In \(minutes) minutes"
        }
    }

    /// When a planner entry is actually due, as a moment.
    ///
    /// Nil for an untimed one: those sit under "Anytime" precisely because
    /// nobody chose an hour for them, and inventing one to count down from
    /// would be inventing the thing the user declined to say.
    static func due(_ entry: PlannerEntry) -> Date? {
        guard let time = entry.time, let day = entry.dayValue else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(
            bySettingHour: parts[0], minute: parts[1], second: 0, of: day
        )
    }

    // MARK: - Food

    /// Morning, afternoon and evening, every day.
    ///
    /// Repeating rather than one per day: three rules cost three of the
    /// sixty-four slots instead of twenty-one, and eating happens on the same
    /// rhythm whatever the calendar says.
    private func scheduleFood(now: Date) async {
        guard !isMutedToday(Key.foodMutedOn, now: now) else { return }
        let times: [(hour: Int, meal: String, body: String)] = [
            (9, "Breakfast", "Log what you had while it is still fresh."),
            (14, "Lunch", "Log it before the afternoon runs away."),
            (20, "Dinner", "Round off the day, and anything after it."),
        ]
        for (hour, meal, body) in times.prefix(Budget.food) {
            await addRepeatingDaily(
                id: "rytivo.food.\(hour)",
                title: "Food Check-In: \(meal)",
                body: body,
                hour: hour,
                category: Category.food
            )
        }
    }

    // MARK: - Workouts

    /// One in the morning, on days holding a workout nobody gave a time.
    ///
    /// A workout with a time is a planner entry with a time, and it already
    /// gets the full ladder above. Reminding about it here as well would be
    /// two notifications for one session.
    private func scheduleWorkouts(_ entries: [PlannerEntry], now: Date) async {
        guard !isMutedToday(Key.workoutMutedOn, now: now) else { return }
        let calendar = Calendar.current
        let days = entries
            .compactMap { entry -> (Date, PlannerEntry)? in
                guard let day = entry.dayValue else { return nil }
                return (day, entry)
            }
            .sorted { $0.0 < $1.0 }
            .prefix(Budget.workoutDays)

        for (day, entry) in days {
            guard let fires = calendar.date(
                bySettingHour: 8, minute: 0, second: 0, of: day
            ), fires > now else { continue }
            // Named, because "you have training planned" is the same sentence
            // every morning and says nothing about which session it is.
            let name = entry.workoutName ?? entry.title
            await add(
                id: "rytivo.workout.\(Self.dayKey(day))",
                title: "Training Session Today: \(name)",
                body: "No time set for it, so it is yours to place in the day.",
                at: fires,
                category: Category.workout,
                userInfo: [:]
            )
        }
    }

    // MARK: - The number on the icon

    /// Sets the badge, or clears it at zero.
    ///
    /// It counts unread notifications and deliberately nothing else. The
    /// reminders this class schedules are about a moment -- a task starting in
    /// five minutes -- and a badge left over from one is a number that cannot
    /// be cleared by doing the thing it was about, because the thing has
    /// already happened. Unread notifications are the opposite: they stay true
    /// until somebody reads them, which is exactly what a badge should track.
    ///
    /// Lives here rather than in the social store because this class owns the
    /// notification centre, and the badge needs the same permission as the
    /// rest of it.
    func setBadge(_ count: Int) async {
        let owner = accountID
        try? await centre.setBadgeCount(owner == nil ? 0 : max(count, 0))
        if accountID != owner { try? await centre.setBadgeCount(0) }
    }

    // MARK: - Muting

    var mutedTaskIDs: Set<Int> {
        Set(defaults.array(forKey: Key.mutedTasks) as? [Int] ?? [])
    }

    func muteTask(_ id: Int) {
        var muted = mutedTaskIDs
        muted.insert(id)
        defaults.set(Array(muted), forKey: Key.mutedTasks)
        removeToday(prefix: "rytivo.task.\(id).")
    }

    func unmuteTask(_ id: Int) {
        var muted = mutedTaskIDs
        muted.remove(id)
        defaults.set(Array(muted), forKey: Key.mutedTasks)
    }

    /// Lets every muted task speak again.
    ///
    /// Muting happens from a notification, in a second, often to find out what
    /// the button does -- and until this existed there was no way back from
    /// it. A task silenced by a stray tap stayed silent, with nothing on any
    /// screen to say it had happened or that a mute was why.
    func unmuteEveryTask() {
        defaults.removeObject(forKey: Key.mutedTasks)
    }

    /// Whether food or workouts are quiet for the rest of today, and the way
    /// back from that too. Both come from the same kind of tap.
    var isFoodMutedToday: Bool { isMutedToday(Key.foodMutedOn, now: Date()) }
    var isWorkoutMutedToday: Bool { isMutedToday(Key.workoutMutedOn, now: Date()) }

    func clearTodaysMutes() {
        defaults.removeObject(forKey: Key.foodMutedOn)
        defaults.removeObject(forKey: Key.workoutMutedOn)
    }

    /// Quiet until tomorrow, not off.
    ///
    /// Stored as the day it was asked for rather than as a flag with an expiry
    /// to check: a date either is today or it is not, and nothing has to run at
    /// midnight to undo it.
    private func muteForToday(_ key: String, now: Date = Date()) {
        defaults.set(Self.dayKey(now), forKey: key)
    }

    private func isMutedToday(_ key: String, now: Date) -> Bool {
        defaults.string(forKey: key) == Self.dayKey(now)
    }

    private func isOn(_ key: String) -> Bool {
        // Absent means on. Somebody who has never opened the settings page has
        // not asked for silence.
        defaults.object(forKey: key) as? Bool ?? true
    }

    // MARK: - Putting one on the schedule

    private func add(
        id: String,
        title: String,
        body: String,
        at date: Date,
        category: String,
        userInfo: [String: Any]
    ) async {
        guard let run = Self.schedulingGeneration, run == generation,
              let accountID, !Task.isCancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo
        content.userInfo["accountID"] = accountID

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let request = UNNotificationRequest(
            identifier: "\(id).\(run.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        try? await centre.add(request)
        if generation != run || Task.isCancelled {
            centre.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        }
    }

    private func addRepeatingDaily(
        id: String,
        title: String,
        body: String,
        hour: Int,
        category: String
    ) async {
        guard let run = Self.schedulingGeneration, run == generation,
              let accountID, !Task.isCancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo["accountID"] = accountID

        let request = UNNotificationRequest(
            identifier: "\(id).\(run.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: 0),
                repeats: true
            )
        )
        try? await centre.add(request)
        if generation != run || Task.isCancelled {
            centre.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        }
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day], from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }
}

// MARK: - Answering the buttons on a notification

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            if action == UNNotificationDefaultActionIdentifier,
               info["route"] as? String == "community", let owner = info["accountID"] as? Int {
                PushNotificationCoordinator.shared.openCommunity(accountID: owner)
                completionHandler()
                return
            }
            guard let owner = self.accountID, info["accountID"] as? Int == owner else {
                completionHandler()
                return
            }
            switch action {
            case Action.muteTask:
                if let id = info["taskID"] as? Int { self.muteTask(id) }
            case Action.muteFood:
                self.muteForToday(Key.foodMutedOn)
                self.removeToday(prefix: "rytivo.food.")
            case Action.muteWorkout:
                self.muteForToday(Key.workoutMutedOn)
                self.removeToday(prefix: "rytivo.workout.")
            default:
                break
            }
            completionHandler()
        }
    }

    /// Shown even while the app is open.
    ///
    /// A reminder that a task starts in a minute is worth seeing whether or
    /// not somebody happens to be looking at a different page of the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let owner = notification.request.content.userInfo["accountID"] as? Int
        let isCommunity = notification.request.content.userInfo["route"] as? String == "community"
        Task { @MainActor in
            let communityAllowed = !isCommunity || (UserDefaults.standard.object(forKey: "notifications.social") as? Bool ?? true)
            completionHandler(owner != nil && owner == self.accountID && communityAllowed ? [.banner, .sound] : [])
        }
    }

    private func removeToday(prefix: String) {
        let owner = accountID
        centre.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            Task { @MainActor in
                guard self.accountID == owner else { return }
                self.centre.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }
}
