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
                    detail: "Repbase imports steps and completed workouts, then stores the synced totals with your account."
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
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationError: String?

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
                    preference("Training", detail: "Planned sessions, active workouts, and recovery", value: $training)
                    Divider()
                    preference("Nutrition", detail: "Meal reminders and daily targets", value: $nutrition)
                    Divider()
                    preference("Calendar", detail: "Tasks, events, and due items", value: $planner)
                    Divider()
                    preference("Community", detail: "Saved now; remote social alerts require server push support", value: $social)
                }

                Text("System-level permission is controlled in iOS Settings. Repbase will honor both your system permission and these choices.")
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
            : "Repbase schedules only the reminders enabled below."
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

    private func synchronizeSchedules() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.localReminderIDs)
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        do {
            if training {
                try await schedule("repbase.training.daily", hour: 8, title: "Your training plan is ready", body: "Take a look at today's session before the day gets busy.")
            }
            if nutrition {
                try await schedule("repbase.nutrition.daily", hour: 12, title: "Keep your plate in view", body: "Log lunch while the portions are still easy to remember.")
            }
            if planner {
                try await schedule("repbase.planner.daily", hour: 18, title: "Tomorrow starts tonight", body: "Review your tasks, events, and planned training.")
            }
            notificationError = nil
        } catch {
            notificationError = error.localizedDescription
        }
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
