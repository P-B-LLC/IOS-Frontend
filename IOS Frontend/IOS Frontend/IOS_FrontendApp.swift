//
//  IOS_FrontendApp.swift
//  IOS Frontend
//
//  Created by user299988 on 8/9/26.
//

import SwiftUI

@main
struct IOS_FrontendApp: App {
    /// App-wide single source of truth for workout scheduling.
    @State private var store = WorkoutStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
