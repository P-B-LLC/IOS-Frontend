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
#else
        _foodTrackingStore = State(initialValue: FoodTrackingStore())
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(authentication)
                .environment(workoutStore)
                .environment(foodTrackingStore)
        }
    }
}

private struct AppRootView: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
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
                    .background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle("Home")
                }
            } else if ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] != nil {
                NavigationStack {
                    FoodTrackingView()
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
            guard ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == nil else {
                return
            }
#endif
            await authentication.restoreSession()
        }
        .task(id: authentication.token) {
#if DEBUG
            guard ProcessInfo.processInfo.environment["REPBASE_FOOD_PREVIEW"] == nil else {
                return
            }
#endif
            guard let token = authentication.token else {
                workoutStore.disconnect()
                foodTrackingStore.reset()
                return
            }
            await workoutStore.connect(
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
            case .signedOut:
                AuthenticationView()
            case .signedIn:
                ContentView()
            }
        }
    }
}
