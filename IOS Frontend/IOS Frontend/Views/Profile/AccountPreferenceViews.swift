import SwiftUI
import UserNotifications
import UIKit

struct AppleHealthConnectionView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.openURL) private var openURL

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RepbaseScreenHeader(
                    eyebrow: "Apple Health",
                    title: "Movement, connected.",
                    detail: "Rytivo imports steps and completed workouts, then stores the synced totals with your account."
                )

                VStack(spacing: 0) {
                    statusRow("Health available", value: activity.isHealthSupported ? "Yes" : "Unavailable")
                    Divider()
                    statusRow("Access requested", value: activity.hasAskedHealth ? "Yes" : "Not yet")
                    Divider()
                    statusRow("Today's steps", value: activity.stepsToday?.formatted() ?? "Not reported")
                    Divider()
                    statusRow("7-day average", value: activity.weekAverage.map { "\($0.formatted()) steps" } ?? "Not reported")
                    Divider()
                    statusRow("8K goal days", value: "\(activity.goalDaysThisWeek) this week")
                    if let synced = activity.lastSyncedAt {
                        Divider()
                        statusRow("Last synced", value: synced.formatted(.relative(presentation: .named)))
                    }
                }

                if let summary = activity.lastImport {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LATEST IMPORT").font(.community(.caption2, weight: .bold)).tracking(1)
                            .foregroundStyle(timeOfDay.accent)
                        Text("\(summary.imported) workouts added")
                            .font(.community(.title3, weight: .bold))
                        Text("\(summary.alreadyImported) already synced · \(summary.skippedOverlapping) overlapping")
                            .font(.community(.caption)).foregroundStyle(.secondary)
                    }
                }

                Button {
                    if activity.hasAskedHealth {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } else {
                        Task { await activity.connectHealth() }
                    }
                } label: {
                    HStack {
                        Text(activity.hasAskedHealth ? "Open iOS Settings" : "Connect Apple Health")
                        Spacer()
                        if activity.isRequestingHealthAccess { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.up.right") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RepbasePrimaryButtonStyle())
                .disabled(!activity.isHealthSupported || activity.isRequestingHealthAccess)

                if activity.hasAskedHealth {
                    Button {
                        Task { await activity.refresh() }
                    } label: {
                        Label(activity.isSyncing ? "Syncing activity" : "Sync activity now", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(activity.isSyncing)
                }
            }
            .padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(timeOfDay)
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.community(.body))
            Spacer()
            Text(value).font(.community(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }
}

struct NotificationPreferencesView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("notifications.training") private var training = true
    @AppStorage("notifications.nutrition") private var nutrition = true
    @AppStorage("notifications.social") private var social = true
    @AppStorage("notifications.planner") private var planner = true
    /// The plan the reminders are built from. Named with a trailing underscore
    /// only because `planner` above is already the switch.
    @Environment(PlannerStore.self) private var planner_
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationError: String?
    /// Changed to redraw the muted summary after clearing it. The mutes live
    /// in UserDefaults rather than in any observable object, so nothing else
    /// would tell this view they had gone.
    @State private var mutedSummaryToken = UUID()

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RepbaseScreenHeader(
                    eyebrow: "Notifications",
                    title: "Only what helps.",
                    detail: "Choose the moments worth bringing you back. These preferences never change what appears inside the app."
                )

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SYSTEM ACCESS").font(.community(.caption2, weight: .bold)).tracking(1)
                            .foregroundStyle(timeOfDay.accent)
                        Text(permissionLabel).font(.community(.headline))
                        Text(permissionDetail).font(.community(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if authorizationStatus == .notDetermined {
                        Button("Allow") { Task { await requestPermission() } }
                            .buttonStyle(.borderedProminent)
                    } else if authorizationStatus == .denied {
                        Button("Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }

                VStack(spacing: 0) {
                    preference(
                        "Workouts",
                        detail: "One in the morning on days holding training with no set time. Training you have given a time is reminded about as a task.",
                        value: $training
                    )
                    Divider()
                    preference(
                        "Food",
                        detail: "Morning, afternoon and evening, to log what you ate.",
                        value: $nutrition
                    )
                    Divider()
                    preference(
                        "Tasks & events",
                        detail: "An hour before, then thirty, fifteen, five and one minute before it starts.",
                        value: $planner
                    )
                    Divider()
                    preference(
                        "Community",
                        detail: "Follows, likes, reposts and replies. Shown on the notifications page in Social rather than sent to your phone.",
                        value: $social
                    )
                }

                if !mutedTaskCount.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MUTED RIGHT NOW")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(timeOfDay.accent)
                        Text(mutedTaskCount)
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Un-mute everything") {
                            NotificationScheduler.shared.unmuteEveryTask()
                            NotificationScheduler.shared.clearTodaysMutes()
                            mutedSummaryToken = UUID()
                            Task { await synchronizeSchedules() }
                        }
                        .font(.community(.subheadline, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                    }
                    .padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("MUTING IS NOT TURNING OFF")
                        .font(.community(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(timeOfDay.accent)
                    Text("Muting from a notification is temporary — one task, or food for the rest of that day. It comes back tomorrow. The switches above are what stop a kind of reminder altogether, and iOS Settings stops all of them.")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Said plainly rather than left to be discovered: nothing
                // another person does can reach a closed phone in these
                // builds, because there is no push entitlement to send it
                // with. Everything above that does arrive is scheduled by the
                // phone itself from a time already known.
                Text("Reminders for workouts, food, tasks and events are scheduled on this device. Community activity is read when you open the notifications page.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("System-level permission is controlled in iOS Settings. Rytivo will honor both your system permission and these choices.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.secondaryText)

                if let notificationError {
                    Text(notificationError).font(.community(.caption)).foregroundStyle(.orange)
                }
            }
            .padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(timeOfDay)
        .task { await refreshPermissionAndSchedules() }
        .onChange(of: training) { _, _ in Task { await synchronizeSchedules() } }
        .onChange(of: nutrition) { _, _ in Task { await synchronizeSchedules() } }
        .onChange(of: planner) { _, _ in Task { await synchronizeSchedules() } }
    }

    /// What is currently silenced, in words, or empty when nothing is.
    private var mutedTaskCount: String {
        _ = mutedSummaryToken
        let scheduler = NotificationScheduler.shared
        var parts: [String] = []
        let tasks = scheduler.mutedTaskIDs.count
        if tasks > 0 {
            parts.append(tasks == 1 ? "1 task" : "\(tasks) tasks")
        }
        if scheduler.isFoodMutedToday { parts.append("food for today") }
        if scheduler.isWorkoutMutedToday { parts.append("workouts for today") }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: ", ") + " muted from a notification."
    }

    private func preference(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.community(.headline))
                Text(detail).font(.community(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 15)
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Notifications are on"
        case .denied: "Notifications are off"
        case .notDetermined: "Allow notifications"
        @unknown default: "Notification status unavailable"
        }
    }

    private var permissionDetail: String {
        authorizationStatus == .denied
            ? "Open iOS Settings to restore permission."
            : "Rytivo schedules only the reminders enabled below."
    }

    private func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await refreshPermissionAndSchedules()
        } catch {
            notificationError = error.localizedDescription
        }
    }

    private func refreshPermissionAndSchedules() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            await synchronizeSchedules()
        }
    }

    /// Rebuilds the reminders to match the switches.
    ///
    /// The three fixed daily nudges this page used to add itself are gone.
    /// They knew nothing about what was actually planned, and they fought the
    /// real scheduler, which clears everything pending before laying down what
    /// the plan says. One place decides now, and this asks it to think again.
    private func synchronizeSchedules() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.localReminderIDs
        )
        // Only with the plan actually in hand.
        //
        // Signed out this store is empty, and rebuilding from it does not mean
        // "nothing is planned" -- it means nothing has been loaded. The
        // rebuild clears the schedule first, so from an empty store it tore
        // down every task and workout reminder and put back only the three
        // food rules, which are the ones needing no data to write.
        //
        // Which is exactly what happened: this is the page somebody opens to
        // grant permission, and opening it before signing in silently emptied
        // the schedule while leaving food behind to make it look fine.
        guard planner_.isConnected else { return }
        let entries = planner_.entriesByDate.values.flatMap { $0 }
        await NotificationScheduler.shared.reschedule(
            entries: entries,
            untimedWorkouts: entries.filter {
                $0.workoutID != nil && $0.time == nil
            }
        )
        notificationError = nil
    }

    private func schedule(
        _ identifier: String,
        hour: Int,
        title: String,
        body: String
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour),
            repeats: true
        )
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }

    private static let localReminderIDs = [
        "repbase.training.daily",
        "repbase.nutrition.daily",
        "repbase.planner.daily"
    ]
}
