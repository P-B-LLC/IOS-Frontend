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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WeeklyScheduleWidget()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Home")
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutStore())
}
