import SwiftUI

/// Account-owned workout summaries, never a claim about OS read permission.
struct ConnectedAppsView: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RepbaseScreenHeader(
                    eyebrow: "Connected apps",
                    title: "Your effort. All here.",
                    detail: "Bring your watch workouts into Rytivo, without logging them twice."
                )
                NavigationLink { AppleHealthConnectionView() } label: {
                    providerCard("Apple Watch & Health", symbol: "applewatch", detail: "Steps, workouts and heart rate", status: activity.healthSyncEnabled ? "Sync enabled" : "Set up")
                }
                .buttonStyle(.plain)
                NavigationLink { GarminConnectionView() } label: {
                    providerCard("Garmin", symbol: "watch.analog", detail: "Workout summaries from your watch", status: "Via Apple Health")
                }
                .buttonStyle(.plain)
                Label("You choose what to share. Your exercise logs stay unchanged.", systemImage: "lock.shield")
                    .font(.community(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Connected apps")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(.current)
        .task { await activity.loadIntegrationStatus() }
    }

    private func providerCard(_ title: LocalizedStringKey, symbol: String, detail: LocalizedStringKey, status: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(RepbaseDesign.accent)
                    .frame(width: 50, height: 50)
                    .background(RepbaseDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                Spacer()
                Text(status).font(.community(.caption, weight: .semibold)).foregroundStyle(.secondary)
                Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
            }
            Text(title).font(.community(.title3, weight: .bold))
            Text(detail).font(.community(.subheadline)).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.12)))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

struct HealthConnectionDashboard: View {
    @Environment(ActivityStore.self) private var activity
    @State private var confirmsPause = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RepbaseScreenHeader(eyebrow: "Apple Watch & Health", title: "Movement, connected.", detail: "Steps, workouts and heart rate")
                VStack(alignment: .leading, spacing: 12) {
                    Label(activity.healthSyncEnabled ? "Sync enabled" : "Set up", systemImage: activity.healthSyncEnabled ? "checkmark.circle.fill" : "heart.text.square")
                        .font(.community(.headline))
                    Text("Enable sync to save this iPhone’s steps and completed workout summaries, including available distance, energy and heart rate, to your signed-in Rytivo account.")
                        .font(.community(.footnote)).foregroundStyle(.secondary)
                    Text("Read-only. No routes or individual heart-rate samples are uploaded.")
                        .font(.community(.caption)).foregroundStyle(.secondary)
                    if let synced = activity.lastSyncedAt {
                        LabeledContent("Last synced", value: synced.formatted(.relative(presentation: .named).locale(.app)))
                            .font(.community(.caption))
                    }
                    if activity.isLoadingIntegration {
                        ProgressView("Loading…")
                    } else if activity.isIntegrationSupported == false {
                        Text("This server needs the connected-apps update before sync can be enabled.")
                            .font(.community(.footnote))
                        Button("Retry") { Task { await activity.loadIntegrationStatus() } }
                    } else if !activity.isHealthSupported {
                        Text("Apple Health is unavailable on this device. Use an iPhone to connect your watch data.")
                            .font(.community(.footnote))
                    } else if activity.isHealthPausePending {
                        Button("Retry pause") { Task { await activity.pauseHealthSync() } }
                            .buttonStyle(.bordered)
                    } else if !activity.healthSyncEnabled {
                        Button { Task { await activity.connectHealth() } } label: {
                            Label("Enable Health sync", systemImage: "heart.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RepbasePrimaryButtonStyle())
                        .disabled(activity.isRequestingHealthAccess || activity.isSyncing || activity.isIntegrationSupported != true)
                    } else {
                        Button { Task { await activity.refresh() } } label: {
                            Label(activity.isSyncing ? "Syncing activity" : "Sync activity now", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RepbasePrimaryButtonStyle())
                        .disabled(activity.isSyncing || activity.isRequestingHealthAccess)
                        Button("Pause Health sync", role: .destructive) { confirmsPause = true }
                            .frame(minHeight: 44)
                    }
                    if activity.isRequestingHealthAccess { ProgressView("Connecting…") }
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.12)))

                if let error = activity.persistenceError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.community(.footnote)).foregroundStyle(.red)
                        .accessibilityIdentifier("health-sync-error")
                    Button("Retry") { Task { await activity.refresh() } }
                        .buttonStyle(.bordered)
                        .disabled(activity.isSyncing || activity.isLoadingIntegration)
                }
                if let summary = activity.lastImport {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LATEST IMPORT").font(.community(.caption2, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(summary.imported) workouts added").font(.community(.headline))
                        Text("\(summary.alreadyImported) already synced · \(summary.skippedOverlapping) overlapping")
                            .font(.community(.caption)).foregroundStyle(.secondary)
                        if summary.skippedOverlapping > 0 {
                            Text("Overlapping workouts were left unchanged to avoid duplicates.")
                                .font(.community(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                }
                DisclosureGroup("Help with missing data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sync your watch with your iPhone, then open Rytivo. In the Health app, open your profile → Apps → Rytivo to review access. An empty result can mean no data or limited permissions.")
                        Text("Only the last 30 days of completed workouts and 7 days of steps are checked. Missing readings are not treated as zero.")
                    }
                    .font(.community(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
                HealthWorkoutList(garminOnly: false)
            }
            .padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Apple Watch & Health")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(.current)
        .task { await activity.loadIntegrationStatus() }
        .confirmationDialog("Pause Health sync", isPresented: $confirmsPause, titleVisibility: .visible) {
            Button("Pause Health sync", role: .destructive) { Task { await activity.pauseHealthSync() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops new uploads. Previously synced workouts stay in Rytivo. Manage Health permissions separately in the Health app.")
        }
    }
}

struct GarminConnectionView: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RepbaseScreenHeader(eyebrow: "Garmin", title: "Your watch. Your workout.", detail: "Via Apple Health")
                VStack(alignment: .leading, spacing: 14) {
                    Label("Direct Garmin connection is not available yet", systemImage: "info.circle")
                        .font(.community(.headline))
                    Text("Direct sync needs Garmin approval. For now, you can import workouts Garmin Connect shares with Apple Health.")
                    Text("1. Enable Apple Health sharing in Garmin Connect.\n2. Open Garmin Connect and sync your watch.\n3. Enable Health sync here, then tap Sync activity now.")
                    NavigationLink { AppleHealthConnectionView() } label: {
                        Label("Set up Apple Health", systemImage: "arrow.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RepbasePrimaryButtonStyle())
                    Link("Garmin setup guide", destination: URL(string: "https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA")!)
                        .frame(minHeight: 44)
                    Text("One-way import only. Garmin may omit some metrics. Editing a workout in Rytivo does not change it on Garmin.")
                        .foregroundStyle(.secondary)
                }
                .font(.community(.footnote))
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.12)))
                if let error = activity.persistenceError {
                    Label(error, systemImage: "exclamationmark.circle").font(.community(.footnote)).foregroundStyle(.red)
                    Button("Retry") { Task {
                        await activity.loadIntegrationStatus()
                        await activity.loadGarminWorkouts()
                    } }
                        .buttonStyle(.bordered).disabled(activity.isLoadingIntegration)
                }
                HealthWorkoutList(garminOnly: true)
            }
            .padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(.current)
        .task { await activity.loadIntegrationStatus() }
        .task(id: activity.isIntegrationSupported) {
            if activity.isIntegrationSupported == true { await activity.loadGarminWorkouts() }
        }
    }
}

/// Shared owner-only readback. Opening a row reveals metrics, not editable logs.
private struct HealthWorkoutList: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(WorkoutStore.self) private var workoutsStore
    var garminOnly: Bool

    private var workouts: [HealthWorkoutSummary] {
        garminOnly ? activity.garminWorkouts : activity.wearableWorkouts
    }

    private var isLoading: Bool { garminOnly ? activity.isLoadingGarminWorkouts : activity.isLoadingWorkouts }
    private var hasMore: Bool { garminOnly ? activity.hasMoreGarminWorkouts : activity.hasMoreWorkouts }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Synced workouts").font(.community(.title3, weight: .bold))
            if isLoading && workouts.isEmpty { ProgressView("Loading…") }
            else if workouts.isEmpty {
                Text("No synced workouts to show yet. Check your connection and try syncing again.")
                    .font(.community(.footnote)).foregroundStyle(.secondary)
            }
            ForEach(workouts) { summary in
                DisclosureGroup {
                    HealthWorkoutMetricsView(summary: summary, unit: workoutsStore.preferences.weightUnit == .imperial ? .miles : .kilometers)
                        .padding(.top, 12)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.activity.title)
                            .font(.community(.headline))
                        Text(summary.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.app)))
                            .font(.community(.caption)).foregroundStyle(.secondary)
                        Text(summary.sourceDisplayName).font(.community(.caption, weight: .semibold))
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.12)))
            }
            if hasMore {
                Button("Load more workouts") { Task {
                    if garminOnly { await activity.loadMoreGarminWorkouts() }
                    else { await activity.loadMoreWorkouts() }
                } }
                    .buttonStyle(.bordered).disabled(isLoading)
            }
        }
    }
}
