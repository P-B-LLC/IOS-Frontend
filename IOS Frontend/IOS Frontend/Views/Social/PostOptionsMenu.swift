//
//  PostOptionsMenu.swift
//  IOS Frontend
//
//  What can be done about a post: delete your own, or tune, report and block.
//

import SwiftUI

/// The menu behind a post's "more" button, whatever the card around it looks
/// like. One copy, so the feed's two card designs cannot come to offer
/// different things -- least of all a card that forgot Report or Block.
struct PostOptionsMenu<Label: View>: View {
    let post: FeedPost
    /// Report asks a question, so the card raises a sheet for it.
    let report: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(SocialStore.self) private var store

    var body: some View {
        Menu {
            if post.viewerIsAuthor {
                Button(role: .destructive) {
                    store.delete(post)
                } label: {
                    SwiftUI.Label("Delete post", systemImage: "trash")
                }
            } else {
                // Only on For You, the one list the server picks.
                // Elsewhere a post is there because of who wrote it,
                // and the answer to that is unfollowing.
                if post.recommendation != nil {
                    // A toggle, so the menu shows the choice and
                    // is the way to take it back; the card stays.
                    Toggle(isOn: Binding(
                        get: { store.wantedPostIDs.contains(post.id) },
                        set: { more in
                            Task { await store.setMoreLikeThis(more, post: post) }
                        }
                    )) {
                        SwiftUI.Label("More like this", systemImage: "hand.thumbsup")
                    }
                    Button {
                        Task { await store.setFewerLikeThis(true, post: post) }
                    } label: {
                        SwiftUI.Label("Fewer like this", systemImage: "hand.thumbsdown")
                    }
                    Button {
                        Task { await store.setNotInterested(true, post: post) }
                    } label: {
                        SwiftUI.Label("Not interested", systemImage: "eye.slash")
                    }
                }
                // Report asks a question, so it opens a sheet.
                // Block does not: it acts on the tap, the way
                // every destructive control in this app does.
                Button {
                    report()
                } label: {
                    SwiftUI.Label("Report post", systemImage: "flag")
                }
                Button(role: .destructive) {
                    Task { await store.block(post.displayed.author) }
                } label: {
                    SwiftUI.Label(
                        "Block \(post.displayed.author.displayName)",
                        systemImage: "hand.raised"
                    )
                }
            }
        } label: {
            label()
        }
    }
}
