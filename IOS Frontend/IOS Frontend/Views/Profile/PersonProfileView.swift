//
//  PersonProfileView.swift
//  IOS Frontend
//
//  Somebody else's profile, opened by id.
//

import SwiftUI

/// Loads a person and hands them to the profile screen.
///
/// The profile page takes a `SocialProfile`, and everywhere it is reached from
/// — a name in Discover, an author on a post — has only an id. This is the
/// step between, so the page itself does not have to know two ways of being
/// given its subject.
struct PersonProfileView: View {
    @Environment(SocialProfileStore.self) private var store

    let userID: Int

    @State private var person: SocialProfile?
    @State private var failed = false

    var body: some View {
        Group {
            if let person {
                SocialProfileView(profile: person, isCurrentUser: false)
            } else if failed {
                ContentUnavailableView {
                    Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Repbase could not load this profile.")
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Cached in the store, so coming back to a profile draws at once
            // rather than blanking while it asks again.
            person = await store.person(userID)
            failed = person == nil
        }
    }
}
