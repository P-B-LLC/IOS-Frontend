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
    @State private var workoutStore = WorkoutStore()
    @State private var plannerStore = PlannerStore()
    @State private var foodTrackingStore: FoodTrackingStore

    init() {
        let configuration = APIConfiguration.current
        _authentication = State(
            initialValue: AuthenticationStore(configuration: configuration)
        )
#if DEBUG
        let isPreviewingFood = ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] != nil
        _foodTrackingStore = State(
            initialValue: isPreviewingFood ? .preview : FoodTrackingStore()
        )
        let isPreviewingPlanner = ProcessInfo.processInfo.environment["REPBASE_PLANNER_PREVIEW"] != nil
        _plannerStore = State(
            initialValue: isPreviewingPlanner ? .preview : PlannerStore()
        )
#else
        _foodTrackingStore = State(initialValue: FoodTrackingStore())
        _plannerStore = State(initialValue: PlannerStore())
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(authentication)
                .environment(workoutStore)
                .environment(plannerStore)
                .environment(foodTrackingStore)
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
    }
#endif

    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(PlannerStore.self) private var plannerStore
    @Environment(FoodTrackingStore.self) private var foodTrackingStore

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == "home" {
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
                foodTrackingStore.reset()
                return
            }
            await workoutStore.connect(
                configuration: authentication.configuration,
                token: token
            )
            await plannerStore.connect(
                configuration: authentication.configuration,
                token: token
            )
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
