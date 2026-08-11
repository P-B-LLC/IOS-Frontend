//
//  IOS_FrontendApp.swift
//  IOS Frontend
//
//  Created by user299988 on 8/9/26.
//

import SwiftUI

@main
struct IOS_FrontendApp: App {
    /// App-wide single source of truth. Swap this adapter when the database is ready.
    @State private var store = WorkoutStore(
        persistence: EphemeralWorkoutPersistence()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
