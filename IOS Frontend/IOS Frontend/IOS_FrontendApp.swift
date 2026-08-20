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
    @State private var socialStore: SocialStore
    @State private var activityStore: ActivityStore
#if DEBUG
    @State private var gearStore = ProcessInfo.processInfo
        .environment["REPBASE_GEAR_PREVIEW"] != nil ? GearStore.preview : GearStore()
#else
    @State private var gearStore = GearStore()
#endif

    init() {
        let configuration = APIConfiguration.current
        _authentication = State(
            initialValue: AuthenticationStore(configuration: configuration)
        )
#if DEBUG
        _activityStore = State(
            initialValue: ProcessInfo.processInfo.environment["REPBASE_HEALTH_PREVIEW"] != nil
                ? .preview
                : ActivityStore()
        )
        let isPreviewingFood = ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] != nil
        let isPreviewingProfile = ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] != nil
        _socialProfileStore = State(
            initialValue: isPreviewingProfile ? .preview : SocialProfileStore()
        )
        _socialStore = State(initialValue: SocialStore())
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
        _activityStore = State(initialValue: ActivityStore())
        _socialProfileStore = State(initialValue: SocialProfileStore())
        _socialStore = State(initialValue: SocialStore())
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
                .environment(socialStore)
                .environment(activityStore)
                .environment(gearStore)
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
            || environment["REPBASE_KEYCHAIN_CHECK"] != nil
            || environment["REPBASE_HEALTH_CHECK"] != nil
            || environment["REPBASE_HEALTH_PREVIEW"] != nil
            || environment["REPBASE_ROUTE_PREVIEW"] != nil
            || environment["REPBASE_GEAR_PREVIEW"] != nil
    }
#endif

    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(PlannerStore.self) private var plannerStore
    @Environment(FoodTrackingStore.self) private var foodTrackingStore
    @Environment(SocialProfileStore.self) private var socialProfileStore
    @Environment(SocialStore.self) private var socialStore
    @Environment(ActivityStore.self) private var activityStore
    @Environment(GearStore.self) private var gearStore

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.environment["REPBASE_HEALTH_CHECK"] != nil {
                // Whether the simulator honours a HealthKit entitlement that
                // device signing strips is a runtime question, not a build one.
                HealthKitProbeView()
            } else if ProcessInfo.processInfo.environment["REPBASE_GEAR_PREVIEW"] == "row" {
                // The picker row in both states. It lives on a workout page
                // reachable only by tapping, so this is the only way to see
                // whether it reads well.
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("With shoes added")
                                .font(.caption.weight(.bold))
                            GearPickerRow(
                                workoutType: .running,
                                destination: .pending(.constant(nil)),
                                primaryText: WorkoutVisualPhase.prepare.primaryText,
                                secondaryText: WorkoutVisualPhase.prepare.secondaryText,
                                accent: WorkoutVisualPhase.prepare.accent
                            )
                            Text("With none")
                                .font(.caption.weight(.bold))
                            GearPickerRow(
                                workoutType: .swimming,
                                destination: .pending(.constant(nil)),
                                primaryText: WorkoutVisualPhase.prepare.primaryText,
                                secondaryText: WorkoutVisualPhase.prepare.secondaryText,
                                accent: WorkoutVisualPhase.prepare.accent
                            )
                        }
                        .padding(RepbaseDesign.pageInset)
                    }
                    .repbaseScreen(.prepare)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_GEAR_PREVIEW"] != nil {
                NavigationStack { GearView() }
            } else if ProcessInfo.processInfo.environment["REPBASE_ROUTE_PREVIEW"] != nil {
                // The simulator has no GPS movement, so a real session there
                // records no track and the map is correctly absent. This is
                // the only way to see that it draws at all.
                ScrollView {
                    SessionRouteMap(
                        // "empty" is the state a simulator session actually
                        // produces, and the one worth checking looks right.
                        points: ProcessInfo.processInfo
                            .environment["REPBASE_ROUTE_PREVIEW"] == "empty"
                            ? []
                            : SessionRouteMap.previewPoints,
                        accent: RepbasePalette.caramel
                    )
                    .padding(RepbaseDesign.pageInset)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_HEALTH_PREVIEW"] == "widget" {
                // The card on its own. On Home it sits below the fold, and a
                // script cannot scroll the simulator to reach the rest of it.
                ScrollView {
                    StepsWidget()
                        .padding(RepbaseDesign.pageInset)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_HEALTH_PREVIEW"] != nil {
                // The widget with days behind it. The simulator has no Watch,
                // so this is the only way to see the populated state.
                RepbaseRootView()
            } else if ProcessInfo.processInfo.environment["REPBASE_KEYCHAIN_CHECK"] != nil {
                // Whether a signed-in session survives relaunching depends on
                // whether this build can reach the Keychain, which no amount
                // of reading the code settles.
                Text(KeychainTokenStore.diagnose())
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else if ProcessInfo.processInfo.environment["REPBASE_AUTH_PREVIEW"] != nil {
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
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "entry",
                      let meal = foodTrackingStore.meals(on: Date()).first {
                NavigationStack {
                    FoodEntryEditorView(date: Date(), mealID: meal.id)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "picker",
                      let meal = foodTrackingStore.meals(on: Date()).first {
                NavigationStack {
                    FoodPickerView(date: Date(), mealID: meal.id)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "goals" {
                NavigationStack {
                    NutritionGoalsView()
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
                // The shell, not the page: the bottom bar lives on the shell,
                // so previewing the page alone would show it without one.
                RepbaseRootView()
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] == "shell-planner" {
                RepbaseRootView(initialTab: .planner)
            } else if ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] == "shell-workouts" {
                RepbaseRootView(initialTab: .training)
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
                socialStore.disconnect()
                activityStore.disconnect()
                gearStore.disconnect()
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
            await foodTrackingStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await socialStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await activityStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await gearStore.connect(
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
                RepbaseRootView()
            }
        }
    }
}
