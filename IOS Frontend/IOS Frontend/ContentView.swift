//
//  ContentView.swift
//  IOS Frontend
//
//  The name the root reaches Home by. The page itself is GuidedHomeView.
//
//  This file used to hold Home: eleven private sections building a command
//  centre out of the stores. Home was rebuilt as GuidedHomeView and this was
//  reduced to a one-line pass-through, but the eleven were left behind, and
//  being private they compiled quietly with nothing able to reach them.
//
//  They were not inert. HomeUpNextSection still contained the "up next" bug
//  that was fixed in the live Home, so anyone reading this file to understand
//  Home would have found working-looking code, believed the bug was shipping,
//  and gone looking for it in the wrong place.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        GuidedHomeView()
    }
}

#Preview {
    NavigationStack { ContentView() }
        .environment(WorkoutStore.preview)
        .environment(PlannerStore.preview)
        .environment(FoodTrackingStore.preview)
        .environment(ActivityStore())
        .environment(SocialProfileStore.preview)
        .environment(AuthenticationStore(configuration: .current))
}
