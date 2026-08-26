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
    @State private var cycleStore = ProcessInfo.processInfo
        .environment["REPBASE_CYCLE_PREVIEW"] == "empty"
        ? CycleStore.previewEmpty
        : (ProcessInfo.processInfo.environment["REPBASE_CYCLE_PREVIEW"] != nil
            ? CycleStore.preview
            : CycleStore())
#else
    @State private var gearStore = GearStore()
    @State private var cycleStore = CycleStore()
#endif

    init() {
        let configuration = APIConfiguration.current
        _authentication = State(
            initialValue: AuthenticationStore(configuration: configuration)
        )
#if DEBUG
        _activityStore = State(
            initialValue: ProcessInfo.processInfo.environment["REPBASE_HEALTH_PREVIEW"] != nil
                || ProcessInfo.processInfo.environment["REPBASE_STEPS_PREVIEW"] != nil
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
                .environment(cycleStore)
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
            || environment["REPBASE_STEPS_PREVIEW"] != nil
            || environment["REPBASE_CYCLE_PREVIEW"] != nil
            || environment["REPBASE_SOCIAL_PREVIEW"] != nil
            || environment["REPBASE_PROMPT_PREVIEW"] != nil
            || environment["REPBASE_LIFTS_PREVIEW"] != nil
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
    @Environment(CycleStore.self) private var cycleStore

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.environment["REPBASE_HEALTH_CHECK"] != nil {
                // Whether the simulator honours a HealthKit entitlement that
                // device signing strips is a runtime question, not a build one.
                HealthKitProbeView()
            } else if ProcessInfo.processInfo.environment["REPBASE_STEPS_PREVIEW"] != nil {
                // The steps card in both states. It sits low on the workout
                // page, which a script cannot scroll to.
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("With steps")
                                .font(.caption.weight(.bold))
                            StepsWidget(explainsWhenEmpty: true)
                            Text("Health not connected")
                                .font(.caption.weight(.bold))
                            StepsWidget(explainsWhenEmpty: true)
                                .environment(ActivityStore(health: .previewNeverAsked()))
                            Text("Asked already, still nothing")
                                .font(.caption.weight(.bold))
                            StepsWidget(explainsWhenEmpty: true)
                                .environment(ActivityStore(health: .previewAlreadyAsked()))
                        }
                        .padding(RepbaseDesign.pageInset)
                    }
                    .repbaseScreen(.prepare)
                }
            } else if let promptPreview = ProcessInfo.processInfo.environment["REPBASE_PROMPT_PREVIEW"] {
                // These sit behind Profile -> About -> a button, and then
                // behind another tap or two, which no script can press.
                NavigationStack {
                    switch promptPreview {
                    case "library":
                        PromptLibraryView(taken: ["why_i_train"], replacing: nil) { _ in }
                    case "answer":
                        PromptAnswerView(question: .proudest)
                    default:
                        PromptPickerView()
                    }
                }
                .environment(SocialProfileStore.preview)
            } else if ProcessInfo.processInfo.environment["REPBASE_LIFTS_PREVIEW"] != nil {
                NavigationStack { ProfileExpressionEditorView() }
                    .environment(SocialProfileStore.preview)
            } else if ProcessInfo.processInfo.environment["REPBASE_SOCIAL_PREVIEW"] != nil {
                // A feed needs other people in it, and the simulator has one
                // account. Sample posts are the only way to see a like already
                // on, a repost, and a thread with a reply in it.
                NavigationStack {
                    switch ProcessInfo.processInfo.environment["REPBASE_SOCIAL_PREVIEW"] {
                    case "detail":
                        PostDetailView(postID: 1)
                    case "push":
                        // Arrives with the thread already pushed, which is the
                        // only way to check that a card leads anywhere.
                        SocialFeedView(initiallyOpened: 1)
                    default:
                        SocialFeedView()
                    }
                }
                .environment(SocialStore.preview)
            } else if ProcessInfo.processInfo.environment["REPBASE_CYCLE_PREVIEW"] != nil {
                // A rotation is several taps deep and needs a saved library
                // behind it, neither of which a script can arrange.
                let mode = ProcessInfo.processInfo.environment["REPBASE_CYCLE_PREVIEW"]
                NavigationStack {
                    switch mode {
                    case "editor":
                        CycleEditorView(mode: .create)
                    case "build":
                        // The builder as the editor pushes it. Whether a view
                        // that carries its own NavigationStack draws a second
                        // bar when pushed is not answerable by reading it.
                        CycleEditorPreviewPush()
                    case "dashboard":
                        TrainingDashboardContent()
                    default:
                        // "empty" arrives here too, with an empty store behind
                        // it, which is the no-rotation state.
                        CycleView()
                    }
                }
                .environment(WorkoutStore.previewWithLibrary)
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
                            // An empty store, not a sport without gear:
                            // swimming takes neither shoes nor a bike, so the
                            // row correctly drew nothing and told me nothing.
                            GearPickerRow(
                                workoutType: .running,
                                destination: .pending(.constant(nil)),
                                primaryText: WorkoutVisualPhase.prepare.primaryText,
                                secondaryText: WorkoutVisualPhase.prepare.secondaryText,
                                accent: WorkoutVisualPhase.prepare.accent
                            )
                            .environment(GearStore())
                        }
                        .padding(RepbaseDesign.pageInset)
                    }
                    .repbaseScreen(.prepare)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_GEAR_PREVIEW"] != nil {
                NavigationStack {
                    GearView(
                        selection: ProcessInfo.processInfo
                            .environment["REPBASE_GEAR_PREVIEW"] == "select"
                            ? GearView.Selection(kind: .shoe, currentID: 2, choose: { _ in })
                            : nil
                    )
                }
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
                cycleStore.disconnect()
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
            await cycleStore.connect(
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
                if authentication.needsOnboarding {
                    RepbaseOnboardingView {
                        authentication.completeOnboarding()
                    }
                } else {
                    RepbaseRootView()
                }
            }
        }
    }
}

#if DEBUG
/// The rotation editor with the workout builder already pushed onto it.
///
/// `simctl` cannot tap, so the only way to see what the pushed builder looks
/// like — and whether it draws a second navigation bar over its own header —
/// is to arrive with it already on the stack.
private struct CycleEditorPreviewPush: View {
    @Environment(WorkoutStore.self) private var workoutStore
    @State private var isPushed = true

    var body: some View {
        CycleEditorView(mode: .create)
            .navigationDestination(isPresented: $isPushed) {
                WorkoutEditorView(
                    mode: .create,
                    suggestions: workoutStore.knownWorkouts
                )
            }
    }
}
#endif
