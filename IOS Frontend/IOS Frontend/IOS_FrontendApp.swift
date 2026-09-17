//
//  IOS_FrontendApp.swift
//  IOS Frontend
//
//  Created by the Rytivo project on 8/9/26.
//

import RepbaseAPI
import SwiftUI
import UIKit

@main
struct IOS_FrontendApp: App {
    @AppStorage(RepbaseAppearancePreference.storageKey)
    private var appearanceRawValue = RepbaseAppearancePreference.light.rawValue

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
            // The planner draws the rotation it is on, so previewing the
            // planner needs one -- the same reason the home preview seeds the
            // workout store.
            || ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] != nil
            ? CycleStore.preview
            : CycleStore())
#else
    @State private var gearStore = GearStore()
    @State private var cycleStore = CycleStore()
#endif

    init() {
        Self.enlargeTheResponseCache()
        RepbaseTypography.configureUIKitAppearance()
        // Registers the categories the reminders carry their mute buttons on,
        // and takes delivery of taps. Before any of them is scheduled: a
        // notification naming a category nobody registered arrives with no
        // buttons on it at all.
        MainActor.assumeIsolated { NotificationScheduler.shared.start() }
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

    /// Give URLSession somewhere to keep photographs between launches.
    ///
    /// `RemoteImageCache` holds decoded images in an `NSCache`, which lives
    /// and dies with the process: every launch re-downloaded every photo the
    /// user had already seen. Underneath it `URLSession.shared` was using the
    /// system default response cache, a few megabytes, which a feed of
    /// photographs evicts itself out of almost immediately.
    ///
    /// The server side of this already exists and was going unused. Photo
    /// URLs are signed with an expiry rounded to a whole day, specifically so
    /// the same photo keeps the same URL long enough to be worth caching, and
    /// the responses carry `Cache-Control: private, max-age=..., immutable`.
    /// Without somewhere to put them that outlives the process, none of that
    /// bought anything.
    ///
    /// Sized for a photo feed rather than for an API: the JSON is small and
    /// mostly uncacheable anyway. The disk figure is deliberately generous
    /// because iOS empties the Caches directory itself when storage runs
    /// short, so the cost of asking for too much is bounded and the cost of
    /// asking for too little is paid on cellular.
    ///
    /// Signing out still calls `URLCache.shared.removeAllCachedResponses()`,
    /// which matters more now that there is something in it to remove.
    private static func enlargeTheResponseCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
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
                .environment(\.font, .community(.body))
                .preferredColorScheme(appearance.colorScheme)
                // preferredColorScheme reaches the nearest enclosing
                // presentation and stops. Settings is a fullScreenCover, which
                // is a presentation of its own, so flipping the picker
                // recoloured the page underneath while the screen actually
                // being looked at kept the old scheme until it was dismissed.
                // Overriding the window covers the root and every presentation
                // over it at once, which is the only place that is true of.
                .onChange(of: appearanceRawValue) { applyToWindows() }
                .task { applyToWindows() }
        }
    }

    /// Push the appearance down to the window itself.
    ///
    /// Every presented screen inherits its traits from the window, so this is
    /// what makes the switch land on a sheet or a cover at the same instant it
    /// lands on the page behind. Left alongside preferredColorScheme rather
    /// than replacing it: that one is right from the first frame, before any
    /// window exists to override.
    @MainActor
    private func applyToWindows() {
        let style: UIUserInterfaceStyle =
            appearance == .dark ? .dark : .light

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    private var appearance: RepbaseAppearancePreference {
#if DEBUG
        // Dark mode is two taps into Settings and simctl cannot tap. This is
        // how the dark palette gets looked at.
        if let forced = ProcessInfo.processInfo.environment["REPBASE_APPEARANCE"],
           let named = RepbaseAppearancePreference(rawValue: forced) {
            return named
        }
#endif
        return RepbaseAppearancePreference(rawValue: appearanceRawValue) ?? .light
    }
}

private struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
#if DEBUG
    /// Whether the app was launched to look at one page with sample data,
    /// rather than as the real signed-in app.
    static var isPreviewing: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["REPBASE_FOOD_PREVIEW"] != nil
            || environment["REPBASE_PLANNER_PREVIEW"] != nil
            || environment["REPBASE_PROFILE_PREVIEW"] != nil
            || environment["REPBASE_AUTH_PREVIEW"] != nil
            || environment["REPBASE_RESET_PREVIEW"] != nil
            || environment["REPBASE_LEGAL_PREVIEW"] != nil
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
            if ProcessInfo.processInfo.environment["REPBASE_ROUTE_CHECK"] != nil {
                // The GPS path has never run end to end, because recording a
                // run starts with a tap and nothing here can tap. simctl can
                // drive the location and grant the authorisation, so this
                // runs the rest of it.
                RouteProbeView()
            } else if ProcessInfo.processInfo.environment["REPBASE_HEALTH_CHECK"] != nil {
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
                                .font(.community(.caption, weight: .bold))
                            StepsWidget(explainsWhenEmpty: true)
                            Text("Health not connected")
                                .font(.community(.caption, weight: .bold))
                            StepsWidget(explainsWhenEmpty: true)
                                .environment(ActivityStore(health: .previewNeverAsked()))
                            Text("Asked already, still nothing")
                                .font(.community(.caption, weight: .bold))
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
                    case "report":
                        // Behind the ... menu on somebody else's post, which
                        // a script cannot open.
                        PostReportSheet(
                            post: SocialStore.preview.feed[0],
                            timeOfDay: HomeTimeOfDay.current
                        )
                    case "blocked":
                        BlockedAccountsView()
                    case "push":
                        // Arrives with the thread already pushed, which is the
                        // only way to check that a card leads anywhere.
                        SocialFeedView(initiallyOpened: 1)
                    case "cropper", "cropper-avatar":
                        // The cropper is behind the photo picker, which is a
                        // system sheet a script cannot drive. This opens it on
                        // a generated picture instead, which is enough to see
                        // the window, the shape chips and the dimmed surround.
                        // `-avatar` shows the profile configuration of the
                        // same view: square, circular, no choice of shape.
                        PhotoCropperPreview()
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
                    case "saved":
                        // The saved library, which is a tap inside the
                        // training tab and so out of a script's reach.
                        SavedWorkoutsView()
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
                                .font(.community(.caption, weight: .bold))
                            GearPickerRow(
                                workoutType: .running,
                                destination: .pending(.constant(nil)),
                                primaryText: WorkoutVisualPhase.prepare.primaryText,
                                secondaryText: WorkoutVisualPhase.prepare.secondaryText,
                                accent: WorkoutVisualPhase.prepare.accent
                            )
                            Text("With none")
                                .font(.community(.caption, weight: .bold))
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
                    .font(.community(.footnote).monospaced())
                    .multilineTextAlignment(.center)
                    .padding(24)
            } else if let name = ProcessInfo.processInfo.environment["REPBASE_LEGAL_PREVIEW"],
                      let document = LegalDocuments.all.first(where: { $0.id == name }) {
                NavigationStack {
                    LegalDocumentView(document: document)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_AUTH_PREVIEW"] != nil
                        || ProcessInfo.processInfo.environment["REPBASE_RESET_PREVIEW"] != nil {
                // The reset flow is reached from this screen, and opens itself
                // when the flag is set.
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
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "saved"
                        || ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "recipe" {
                NavigationStack {
                    // Two taps inside the food page, which a script cannot
                    // make, and the one list whose delete needed looking at.
                    SavedMealsView(referenceDate: Date())
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "goals" {
                NavigationStack {
                    NutritionGoalsView()
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] != nil {
                NavigationStack {
                    // "pushed" draws it the way Home links to it: onto another
                    // tab's stack, where it needs a back button of its own
                    // because the tab bar still points at where you came from.
                    FoodTrackingView(
                        showsBackButton: ProcessInfo.processInfo
                            .environment["REPBASE_FOOD_PREVIEW"] == "pushed"
                    )
                }
            } else if let profilePreview = ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"],
                      profilePreview != "profile",
                      profilePreview != "public",
                      profilePreview != "private",
                      profilePreview != "edit",
                      profilePreview != "links" {
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
            } else if ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] == "edit",
                      let profile = socialProfileStore.profile {
                NavigationStack {
                    // The whole-profile editor, which sits behind a sign-in
                    // and several taps, so a script cannot reach it.
                    ProfileOnboardingView(seed: profile, isEditing: true)
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] == "private" {
                NavigationStack {
                    // Seeded the way the server actually answers for a closed
                    // profile: the username, the fact of it, and every other
                    // field emptied. A sample with a name and a face in it
                    // would be previewing something that cannot happen.
                    PrivateProfileView(
                        person: SocialProfile(
                            provider: .apple,
                            firstName: "",
                            lastName: "",
                            username: "ada.lifts",
                            bio: "",
                            heightFeet: 0,
                            heightInches: 0,
                            weightPounds: 0,
                            targetWeightPounds: 0,
                            showsHeight: false,
                            showsWeight: false,
                            showsTargetWeight: false,
                            isProfilePublic: false,
                            isReadable: false,
                            disciplines: [],
                            gym: nil,
                            profileImageData: nil
                        )
                    )
                }
            } else if let profilePreview = ProcessInfo.processInfo.environment["REPBASE_PROFILE_PREVIEW"] {
                NavigationStack {
                    // Settings -> Profile -> Social links is three taps deep,
                    // and a script can press none of them.
                    if profilePreview == "links" {
                        SocialLinksEditorView()
                    } else {
                        ProfileDestinationView()
                    }
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
                            // High, so this route also shows what a raised
                            // priority looks like once it is set — and that an
                            // event can carry one, not only a task.
                            priority: .high,
                            date: PlannerStore.dateString(Date()),
                            // With a start and a length, so this route also
                            // shows the Length row carrying a value and the
                            // end time it works out from it.
                            time: "18:00:00",
                            durationMinutes: 120
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
        .font(.community(.body))
        .repbaseCelebrationOverlay()
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { workoutStore.checkpointActiveSession() }
            if phase == .active {
                Task { await workoutStore.retryPendingWorkoutSaves() }
            }
        }
        .task {
#if DEBUG
            // A preview run must not touch the network or the stores; without
            // this, signing out would clear the sample data it exists to show.
            guard Self.isPreviewing == false else { return }
#endif
            authentication.onSessionEnded = { clearAccountState() }
            authentication.onAccountDeleted = { ownerID in
                workoutStore.deleteAccountRecovery(ownerID: ownerID, origin: authentication.configuration.serverURL.absoluteString)
                try? EditorDraftRecovery.shared.removeAccount(scope: .init(ownerID: ownerID, origin: authentication.configuration.serverURL.absoluteString))
            }
            await authentication.restoreSession()
        }
        .task(id: authentication.token) {
#if DEBUG
            // A preview run must not touch the network or the stores; without
            // this, signing out would clear the sample data it exists to show.
            guard Self.isPreviewing == false else { return }
#endif
            guard let token = authentication.token else {
                // A temporary restore failure must not erase existing local
                // reminders. Explicit logout/rejection runs synchronous cleanup.
                if authentication.phase == .signedOut { clearAccountState() }
                return
            }
            guard case .signedIn(let user) = authentication.phase else { return }
            EditorDraftRecovery.shared.scope = .init(ownerID: user.id, origin: authentication.configuration.serverURL.absoluteString)
            NotificationScheduler.shared.setAccount(user.id)
            await socialProfileStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            await workoutStore.connect(
                configuration: authentication.configuration,
                token: token,
                accountID: user.id
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            await plannerStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            await foodTrackingStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            // Saving somebody else's workout or meal writes a row into a list
            // this store does not hold. Without these the copy sat on the
            // server and stayed missing from Saved workouts until the next
            // launch, which reads as the save having quietly failed.
            socialStore.onSavedWorkoutsChanged = { [workoutStore] in
                await workoutStore.reloadSchedule()
            }
            socialStore.onSavedMealsChanged = { [foodTrackingStore] in
                await foodTrackingStore.reloadSavedMeals()
            }
            await socialStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            await activityStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            await gearStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            // Starting or switching a rotation plans days on the server. The
            // week on screen belongs to the workout store, so it has to be
            // told to read them, or the rotation looks like it did nothing.
            cycleStore.onCalendarChanged = { [workoutStore] in
                await workoutStore.reloadSchedule()
            }
            await cycleStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            guard authentication.token == token, !Task.isCancelled else { return }
            await plannerStore.syncScheduledWorkouts(workoutStore.currentWeekWorkouts)
            guard authentication.token == token, !Task.isCancelled else { return }
            await rescheduleReminders()
            // So the icon is right from launch rather than only after the
            // Social tab has been opened once.
            guard authentication.token == token, !Task.isCancelled else { return }
            await socialStore.refreshUnreadNotificationCount()
            guard authentication.token == token, !Task.isCancelled else { return }
            await workoutStore.retryPendingWorkoutSaves()
        }
        .task(id: workoutStore.currentWeekWorkouts) {
#if DEBUG
            guard Self.isPreviewing == false else { return }
#endif
            guard authentication.token != nil else { return }
            await plannerStore.syncScheduledWorkouts(workoutStore.currentWeekWorkouts)
            await rescheduleReminders()
        }
        // A task added, moved, finished or deleted changes what should be
        // waiting on the phone. Without this the reminders only caught up on
        // the next sign-in, so a task written for this evening was never
        // reminded about at all.
        //
        // Keyed on the reminder list rather than the month on screen. Keyed on
        // the month, simply paging the calendar rebuilt the whole schedule out
        // of whatever month was being looked at, which silently dropped
        // tomorrow's reminders on the way past.
        .task(id: plannerStore.reminderEntries) {
#if DEBUG
            guard Self.isPreviewing == false else { return }
#endif
            guard authentication.token != nil else { return }
            await rescheduleReminders()
        }
    }

    /// Rebuilds every reminder the device raises on its own.
    ///
    /// Driven off the planner alone, which is enough for both halves of it. A
    /// scheduled workout is already synced into the planner as a task, so a
    /// workout somebody gave an hour is an entry with a time and gets the
    /// countdown; one they did not is an entry without a time, and gets the
    /// single morning nudge instead. Deriving both from one list is what stops
    /// a timed workout being reminded about twice.
    private func rescheduleReminders() async {
        guard authentication.token != nil, !Task.isCancelled else { return }
        let entries = plannerStore.reminderEntries
        await NotificationScheduler.shared.reschedule(
            entries: entries,
            untimedWorkouts: entries.filter {
                $0.workoutID != nil && $0.time == nil
            }
        )
    }

    private func clearAccountState() {
        EditorDraftRecovery.shared.scope = nil
        NotificationScheduler.shared.setAccount(nil)
        workoutStore.disconnect()
        plannerStore.disconnect()
        socialProfileStore.disconnect()
        socialStore.disconnect()
        activityStore.disconnect()
        gearStore.disconnect()
        cycleStore.disconnect()
        foodTrackingStore.reset()
        RemoteImageCache.shared.clear()
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        Group {
            switch authentication.phase {
            case .checking:
                VStack(spacing: 14) {
                    Image("RytivoLogoMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    ProgressView()
                    Text("Connecting to Rytivo...")
                        .font(.community(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .repbaseScreen(.prepare)
            case .recoveryRequired:
                VStack(spacing: 20) {
                    Text("Let's reconnect.")
                        .font(.community(.title2, weight: .semibold))
                    Text(authentication.errorMessage ?? "Your saved login is safe.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await authentication.restoreSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authentication.isWorking)
                    Button("Sign out") {
                        Task { await authentication.signOut() }
                    }
                }
                .padding(28)
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
