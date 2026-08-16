//
//  IOS_FrontendApp.swift
//  IOS Frontend
//
//  Created by user299988 on 8/9/26.
//

import RepbaseAPI
import SwiftUI

@main
struct IOS_FrontendApp: App {
    @State private var authentication: AuthenticationStore
    @State private var workoutStore: WorkoutStore
    @State private var plannerStore: PlannerStore
    @State private var foodTrackingStore: FoodTrackingStore
    @State private var socialProfileStore: SocialProfileStore

    init() {
        let configuration = APIConfiguration.current
        _authentication = State(
            initialValue: AuthenticationStore(configuration: configuration)
        )
#if DEBUG
        let isPreviewingFood = ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] != nil
        let isPreviewingProfile = ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] != nil
        _socialProfileStore = State(
            initialValue: isPreviewingProfile ? .preview : SocialProfileStore()
        )
        _foodTrackingStore = State(
            initialValue: isPreviewingFood ? .preview : FoodTrackingStore()
        )
        let plannerPreview = ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"]
        _plannerStore = State(
            initialValue: plannerPreview != nil ? .preview : PlannerStore()
        )
        // The home page draws workouts too, so previewing it needs both.
        _workoutStore = State(
            initialValue: plannerPreview == "home" ? .preview : WorkoutStore()
        )
#else
        _socialProfileStore = State(initialValue: SocialProfileStore())
        _foodTrackingStore = State(initialValue: FoodTrackingStore())
        _plannerStore = State(initialValue: PlannerStore())
        _workoutStore = State(initialValue: WorkoutStore())
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(authentication)
                .environment(workoutStore)
                .environment(plannerStore)
                .environment(foodTrackingStore)
                .environment(socialProfileStore)
        }
    }
}

private struct AppRootView: View {
#if DEBUG
    /// Whether the app was launched to look at one page with sample data,
    /// rather than as the real signed-in app.
    static var isPreviewing: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["REPBASE_FOOD_PREVIEW"] != nil
            || environment["REPBASE_PLANNER_PREVIEW"] != nil
            || environment["REPBASE_PROFILE_PREVIEW"] != nil
            || environment["REPBASE_AUTH_PREVIEW"] != nil
    }
#endif

    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(PlannerStore.self) private var plannerStore
    @Environment(FoodTrackingStore.self) private var foodTrackingStore
    @Environment(SocialProfileStore.self) private var socialProfileStore

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.environment["REPBASE_AUTH_PREVIEW"] != nil {
                AuthenticationView()
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "home" {
                NavigationStack {
                    ScrollView {
                        FoodSummaryWidget()
                            .padding()
                    }
                    .repbaseScreen(.prepare)
                    .navigationTitle("Home")
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] != nil {
                NavigationStack {
                    FoodTrackingView()
                }
            } else if let profilePreview = ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"],
                      profilePreview != "profile" && profilePreview != "public" {
                NavigationStack {
                    ProfileOnboardingView(
                        seed: SocialProfile(
                            provider: .apple,
                            firstName: "",
                            lastName: "",
                            username: "",
                            bio: "",
                            heightFeet: 5,
                            heightInches: 8,
                            weightPounds: 160,
                            targetWeightPounds: 155,
                            showsHeight: false,
                            showsWeight: false,
                            showsTargetWeight: false,
                            disciplines: [],
                            gym: nil,
                            profileImageData: nil
                        ),
                        initialStep: ["connect": 0, "name": 1, "goals": 2, "identity": 3][profilePreview] ?? 0
                    )
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] == "public",
                      let profile = socialProfileStore.profile {
                NavigationStack {
                    SocialProfileView(profile: profile, isCurrentUser: false)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] != nil {
                NavigationStack {
                    ProfileDestinationView()
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] == "home" {
                ContentView()
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] == "task-editor" {
                PlannerEntryEditorView(mode: .create(.task, Date()))
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] == "event-editor" {
                // The editor is only reachable by tapping, and the simulator
                // cannot be tapped from a script. This is the only way to see
                // it before it ships.
                PlannerEntryEditorView(mode: .create(.event, Date()))
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] == "edit-editor" {
                PlannerEntryEditorView(
                    mode: .edit(
                        PlannerEntry(
                            serverID: 1,
                            kind: .event,
                            title: "Sophie's birthday",
                            category: .birthday,
                            date: PlannerStore.dateString(Date())
                        )
                    )
                )
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] != nil {
                NavigationStack {
                    PlannerView()
                }
            } else {
                authenticatedContent
            }
#else
            authenticatedContent
#endif
        }
        .task {
#if DEBUG
            // A preview run must not touch the network or the stores; without
            // this, signing out would clear the sample data it exists to show.
            guard Self.isPreviewing == false else { return }
#endif
            await authentication.restoreSession()
        }
        .task(id: authentication.token) {
#if DEBUG
            // A preview run must not touch the network or the stores; without
            // this, signing out would clear the sample data it exists to show.
            guard Self.isPreviewing == false else { return }
#endif
            guard let token = authentication.token else {
                workoutStore.disconnect()
                plannerStore.disconnect()
                socialProfileStore.disconnect()
                foodTrackingStore.reset()
                return
            }
            await socialProfileStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await workoutStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await plannerStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await plannerStore.syncScheduledWorkouts(workoutStore.currentWeekWorkouts)
        }
        .task(id: workoutStore.currentWeekWorkouts) {
#if DEBUG
            guard Self.isPreviewing == false else { return }
#endif
            guard authentication.token != nil else { return }
            await plannerStore.syncScheduledWorkouts(workoutStore.currentWeekWorkouts)
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        Group {
            switch authentication.phase {
            case .checking:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Connecting to Repbase...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .repbaseScreen(.prepare)
            case .signedOut:
                AuthenticationView()
            case .signedIn:
                ContentView()
            }
        }
    }
}
