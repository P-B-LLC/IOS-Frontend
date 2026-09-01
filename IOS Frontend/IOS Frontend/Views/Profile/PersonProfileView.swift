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
                // A closed profile is answered, not refused: the server sends
                // the username and the fact that it is closed, and nothing
                // else. Drawing the ordinary page over that would be drawing
                // a profile with every field blank.
                if person.isProfilePublic {
                    SocialProfileView(profile: person, isCurrentUser: false)
                } else {
                    PrivateProfileView(person: person)
                }
            } else if failed {
                ContentUnavailableView {
                    Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Routiq could not load this profile.")
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

/// What a profile says when its owner has closed it.
///
/// Deliberately plain. There is no follow button, because following someone
/// privately is a request-and-approval flow that does not exist yet, and a
/// button that quietly did nothing would be worse than no button. There is no
/// photo or name either: the server withholds both, and this page says only
/// what it was actually told.
private struct PrivateProfileView: View {
    let person: SocialProfile

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .font(.community(size: 30, weight: .semibold))
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(width: 92, height: 92)
                .background(timeOfDay.surfaceRaised, in: Circle())

            VStack(spacing: 7) {
                Text("@\(person.username)")
                    .font(.community(.headline))
                    .foregroundStyle(timeOfDay.primaryText)

                Text("This profile is private")
                    .font(.community(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.primaryText)
                    .multilineTextAlignment(.center)

                // Says what is true of this page and no more. Their posts are
                // not hidden by this switch, and claiming otherwise here would
                // be promising something the app does not do.
                Text("They have chosen not to share their profile.")
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .homeTimeScreen(timeOfDay)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
