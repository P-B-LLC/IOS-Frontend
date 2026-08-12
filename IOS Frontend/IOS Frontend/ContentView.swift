//
//  ContentView.swift
//  IOS Frontend
//
//  Created by user299988 on 8/9/26.
//

import SwiftUI

/// The app's main / home screen. Hosts the home widgets — currently the weekly
/// workout schedule. Wrapped in a `NavigationStack` so widgets can push their
/// detail pages (the weekly widget → Workouts).
struct ContentView: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let error = workoutStore.persistenceError {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.orange)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(error)
                                    .font(.footnote)
                                Button("Retry") {
                                    workoutStore.retryPersistence()
                                }
                                .font(.footnote.weight(.semibold))
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            Color.orange.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                    }

                    WeeklyScheduleWidget()
                    FoodSummaryWidget()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Home")
            .overlay {
                if workoutStore.isLoading {
                    ZStack {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                        ProgressView("Loading workouts...")
                            .padding(18)
                            .background(
                                .regularMaterial,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if case .signedIn(let user) = authentication.phase {
                            Text(user.displayName)
                            Text("@\(user.username)")
                        }
                        Divider()
                        Button("Refresh Workouts", systemImage: "arrow.clockwise") {
                            workoutStore.retryPersistence()
                        }
                        Button(
                            "Sign Out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            role: .destructive
                        ) {
                            Task {
                                await authentication.signOut()
                            }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .disabled(authentication.isWorking)
                    .accessibilityLabel("Account")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutStore.preview)
        .environment(FoodTrackingStore.preview)
        .environment(
            AuthenticationStore(configuration: .current)
        )
}
