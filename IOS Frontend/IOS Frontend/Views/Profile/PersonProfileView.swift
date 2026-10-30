//
//  PersonProfileView.swift
//  IOS Frontend
//
//  Somebody else's profile, opened by id.
//

import Foundation
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
                // Readable, not public: a closed profile is still handed
                // in full to the people following it, and only they and its
                // owner get anything to draw. The server answers a closed
                // door with the username and nothing else, so the ordinary
                // page over that would be a profile of blank fields.
                if person.isReadable {
                    SocialProfileView(profile: person, isCurrentUser: false)
                } else {
                    PrivateProfileView(person: person)
                }
            } else if failed {
                ContentUnavailableView {
                    Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? String(localized: "Rytivo could not load this profile.", bundle: .app, locale: .app))
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
/// Deliberately plain, and it says only what it was actually told: the server
/// withholds the name and the photo along with everything else, so neither
/// appears here.
///
/// The one thing it offers is the way in. Asking to follow does not open
/// anything by itself -- it waits on the person on the other side, which is
/// what separates this from a public profile where the same tap is the whole
/// transaction.
struct PrivateProfileView: View {
    @Environment(SocialStore.self) private var social
    @Environment(SocialProfileStore.self) private var profileStore

    let person: SocialProfile

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        VStack(spacing: 18) {
            Spacer(minLength: 0)

            // Bordered as well as filled. The raised surface is near enough
            // to the page behind it on the light theme that the circle
            // vanished and the lock floated on nothing.
            Image(systemName: "lock.fill")
                .font(.community(size: 30, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 92, height: 92)
                .background(timeOfDay.accent.opacity(0.10), in: Circle())
                .overlay { Circle().strokeBorder(timeOfDay.accent.opacity(0.22), lineWidth: 1) }

            VStack(spacing: 7) {
                Text("@\(person.username)")
                    .font(.community(.headline))
                    .foregroundStyle(timeOfDay.primaryText)

                Text("This profile is private")
                    .font(.community(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.primaryText)
                    .multilineTextAlignment(.center)

                Text("Only their followers can see this profile.")
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The way in, and the only one. Asking does not open anything by
            // itself: it waits until the person on the other side answers,
            // which is what makes this different from a public profile where
            // the same tap is the whole transaction.
            if let id = person.id {
                let relationship = social.relationship(
                    with: id,
                    viewerID: profileStore.viewerID,
                    isPrivate: true,
                    viewerFollowsHint: person.viewerFollows,
                    requestedHint: person.viewerHasRequested,
                    followsViewerHint: person.followsViewer
                )
                VStack(spacing: 10) {
                    RelationshipBadge(relationship: relationship)
                    FollowButton(
                        person: PostAuthor(
                            id: id,
                            username: person.username,
                            firstName: person.firstName,
                            lastName: person.lastName,
                            photoURL: person.profilePhotoURL
                        ),
                        relationship: relationship,
                        viewerID: profileStore.viewerID,
                        size: .large
                    )
                    .frame(maxWidth: 260)
                    if relationship.action == .requested {
                        Text("They will see your request.")
                            .font(.community(.caption))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }
                .padding(.top, 4)
                .animation(.snappy(duration: 0.2), value: relationship)
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
