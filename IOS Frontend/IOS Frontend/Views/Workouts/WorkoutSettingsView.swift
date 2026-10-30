//
//  WorkoutSettingsView.swift
//  IOS Frontend
//
//  How weights are shown and how rests behave.
//

import ActivityKit
import SwiftUI
import UserNotifications

struct WorkoutSettingsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationsAllowed = true
    @State private var activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled

    private var preferences: WorkoutPreferences { store.preferences }

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Default unit", selection: Binding(
                    get: { preferences.defaultWeightUnit },
                    set: { unit in Task { await preferences.makeDefault(unit, using: store) } }
                )) {
                    ForEach(WorkoutWeightUnit.allCases) { unit in
                        Text("\(unit.title) (\(unit.label))").tag(unit)
                    }
                }
                .disabled(preferences.isSavingUnit || !store.isConnected)
                if let error = preferences.unitError {
                    Text(error).font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
                }
            } header: {
                Text("Weight")
            } footer: {
                Text("Saved to your account, so every device shows it. The kg | lb switch on a workout changes the display for now without changing this. Recorded weights never change.")
            }

            Section {
                Picker("Default rest", selection: $preferences.defaultRestSeconds) {
                    ForEach(RestDurationOptions.seconds, id: \.self) { seconds in
                        Text(RestDurationOptions.label(seconds)).tag(seconds)
                    }
                }
                Toggle("Start rest after each set", isOn: $preferences.autoStartRest)
                Toggle("Alert when rest is over", isOn: $preferences.restAlerts)
                    .onChange(of: preferences.restAlerts) { _, on in
                        if on { requestNotifications() }
                        store.refreshSessionSignals()
                    }
                if preferences.restAlerts && !notificationsAllowed {
                    Label("Notifications are off for Rytivo in iOS Settings, so the alert can’t sound while Rytivo is closed.", systemImage: "bell.slash")
                        .font(.community(.caption))
                        .foregroundStyle(RepbaseDesign.warning)
                }
            } header: {
                Text("Rest timer")
            } footer: {
                Text("Used for every exercise without a rest of its own. Each exercise’s rest can be changed in a workout or its plan. Drop sets never start a rest, and a superset rests after the last exercise of each round.")
            }

            Section {
                Toggle("Show on Lock Screen", isOn: $preferences.liveActivity)
                    .onChange(of: preferences.liveActivity) { store.refreshSessionSignals() }
                if preferences.liveActivity && !activitiesAllowed {
                    Label("Live Activities are off for Rytivo in iOS Settings.", systemImage: "lock.slash")
                        .font(.community(.caption))
                        .foregroundStyle(RepbaseDesign.warning)
                }
            } header: {
                Text("Lock Screen")
            } footer: {
                Text("While you lift, the current set, your rest countdown and buttons to log the set or adjust the rest appear on the Lock Screen and in the Dynamic Island.")
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermissions() } }
        }
    }

    private func refreshPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
            || settings.authorizationStatus == .notDetermined
        activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func requestNotifications() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
            await refreshPermissions()
        }
    }
}
