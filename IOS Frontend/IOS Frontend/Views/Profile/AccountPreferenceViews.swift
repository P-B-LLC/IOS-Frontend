import SwiftUI

struct AppleHealthConnectionView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)
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
                    }

                    if let summary = activity.lastImport {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LATEST IMPORT").font(.caption2.weight(.bold)).tracking(1)
                                .foregroundStyle(timeOfDay.accent)
                            Text("\(summary.imported) workouts added")
                                .font(.title3.weight(.bold))
                            Text("\(summary.alreadyImported) already synced · \(summary.skippedOverlapping) overlapping")
                                .font(.caption).foregroundStyle(.secondary)
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
                }
                .padding(RepbaseDesign.pageInset)
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }
}

struct NotificationPreferencesView: View {
    @AppStorage("notifications.training") private var training = true
    @AppStorage("notifications.nutrition") private var nutrition = true
    @AppStorage("notifications.social") private var social = true
    @AppStorage("notifications.planner") private var planner = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    RepbaseScreenHeader(
                        eyebrow: "Notifications",
                        title: "Only what helps.",
                        detail: "Choose the moments worth bringing you back. These preferences never change what appears inside the app."
                    )

                    VStack(spacing: 0) {
                        preference("Training", detail: "Planned sessions, active workouts, and recovery", value: $training)
                        Divider()
                        preference("Nutrition", detail: "Meal reminders and daily targets", value: $nutrition)
                        Divider()
                        preference("Calendar", detail: "Tasks, events, and due items", value: $planner)
                        Divider()
                        preference("Community", detail: "Comments, follows, and shared progress", value: $social)
                    }

                    Text("System-level permission is controlled in iOS Settings. Repbase will honor both your system permission and these choices.")
                        .font(.caption)
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .padding(RepbaseDesign.pageInset)
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
        }
    }

    private func preference(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 15)
    }
}
