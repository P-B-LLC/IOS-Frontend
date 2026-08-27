//
//  PostDetailView.swift
//  IOS Frontend
//
//  One post, and everything said under it.
//
//  The post is read from the store by id rather than held as a copy, so a like
//  made here is the same like the feed card shows when this page is popped —
//  two numbers for one thing, drifting apart, is the bug this avoids.
//

import SwiftUI

struct PostDetailView: View {
    let postID: Int

    @Environment(SocialStore.self) private var store

    /// Worked out here rather than read from the environment. A pushed screen
    /// does not inherit what the feed set inside its own body, so this page
    /// came up in the day palette at eleven at night with the tab bar under
    /// it still dark.
    @State private var timeOfDay = HomeTimeOfDay(date: Date())
    /// True until the first fetch has been attempted, so a post being loaded
    /// does not flash "this post is gone" on the way in.
    @State private var isFetching = true
    /// Whether the threads are raised over the post.
    ///
    /// Closed on arrival. The threads used to be the page, with the post
    /// squeezed into a strip above them — so opening a post showed the
    /// comment box and an empty-state before the reader had asked for
    /// either, and the post's own action row sat half-hidden behind it.
    @State private var showingComments = false
    /// The author's profile, when it has been opened from the card.
    @State private var visitingAuthor: Int?

    private var post: FeedPost? { store.post(withID: postID) }

    var body: some View {
        Group {
            if let post {
                loaded(post)
            } else if isFetching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The card that opened this has left the feed — deleted, or
                // paged out from under it.
                ContentUnavailableView(
                    "This post is gone",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text("It may have been deleted since you opened it.")
                )
            }
        }
        .homeTimeScreen(timeOfDay)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $visitingAuthor) { userID in
            PersonProfileView(userID: userID)
        }
        .task {
            // Fetched first when the feed does not hold it — opened from a
            // profile, or from a card that has since paged out.
            await store.loadPost(id: postID)
            isFetching = false
#if DEBUG
            // Arrives with the threads already raised. They open on a tap now,
            // and simctl cannot tap.
            if ProcessInfo.processInfo.environment["REPBASE_SOCIAL_FOCUS"] != nil {
                showingComments = true
            }
#endif
        }
    }

    private func loaded(_ post: FeedPost) -> some View {
        // The post gets the page. It is what was tapped, so it is what should
        // be on screen — whole, and scrolling as far as it needs rather than
        // capped into a strip with the conversation pushing up underneath it.
        ScrollView {
            PostCard(
                post: post,
                timeOfDay: timeOfDay,
                // The same sheet the feed raises, from the same button. Being
                // on the post's own page is not a reason to have already
                // opened its comments.
                openComments: { showingComments = true },
                openAuthor: { visitingAuthor = $0 }
            )
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            // Clear of the floating tab bar, which is drawn over a pushed
            // screen rather than inset out of it.
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingComments) {
            PostCommentsSheet(postID: postID, timeOfDay: timeOfDay)
        }
    }
}

/// A comment and the replies under it.
struct CommentThread: View {
    let comment: PostComment
    let timeOfDay: HomeTimeOfDay
    let onReply: (PostComment) -> Void
    let onDelete: (PostComment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(
                comment: comment,
                timeOfDay: timeOfDay,
                onReply: { onReply(comment) },
                onDelete: { onDelete(comment) }
            )

            ForEach(comment.replies) { reply in
                CommentRow(
                    comment: reply,
                    timeOfDay: timeOfDay,
                    // A reply answers the thread, not the reply, because that
                    // is the only shape the server keeps.
                    onReply: { onReply(comment) },
                    onDelete: { onDelete(reply) }
                )
                // Indented once and no further. The rail says which thread it
                // belongs to without another level of margin.
                .padding(.leading, 30)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(timeOfDay.secondaryText.opacity(0.18))
                        .frame(width: 1)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct CommentRow: View {
    let comment: PostComment
    let timeOfDay: HomeTimeOfDay
    let onReply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName)
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .lineLimit(1)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.community(.caption2))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(comment.body)
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button("Reply", action: onReply)
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                    if comment.viewerIsAuthor {
                        Button("Delete", action: onDelete)
                            .font(.community(.caption, weight: .semibold))
                            .foregroundStyle(RepbaseDesign.danger)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            }
        }
    }

    private var avatar: some View {
        Group {
            if let photo = comment.author.photoURL, let url = URL(string: photo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(timeOfDay.accent.opacity(0.18))
            Text(comment.author.initials)
                .font(.community(size: 11, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
        }
    }
}
