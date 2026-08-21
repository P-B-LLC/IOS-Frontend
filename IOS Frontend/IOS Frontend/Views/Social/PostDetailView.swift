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
    @Environment(\.homeTimeOfDay) private var timeOfDay

    @State private var draft = CommentDraft()
    @State private var confirmingDelete: PostComment?
    /// True until the first fetch has been attempted, so a post being loaded
    /// does not flash "this post is gone" on the way in.
    @State private var isFetching = true
    @FocusState private var isWriting: Bool

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
        .task {
            // Fetched first when the feed does not hold it — opened from a
            // profile, or from a card that has since paged out.
            await store.loadPost(id: postID)
            isFetching = false
            await store.loadComments(for: postID)
        }
    }

    private func loaded(_ post: FeedPost) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    PostCard(post: post, timeOfDay: timeOfDay)

                    threadsHeader(post)

                    if store.isLoadingComments(for: postID) && threads.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else if threads.isEmpty {
                        emptyThreads
                    } else {
                        ForEach(threads) { thread in
                            CommentThread(
                                comment: thread,
                                timeOfDay: timeOfDay,
                                onReply: { begin(replyingTo: $0) },
                                onDelete: { confirmingDelete = $0 }
                            )
                        }
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            composer
        }
        .confirmationDialog(
            "Delete this comment?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { comment in
            Button("Delete", role: .destructive) {
                Task { await store.deleteComment(comment) }
            }
            Button("Keep", role: .cancel) {}
        } message: { comment in
            Text(
                comment.replies.isEmpty
                    ? "It will be removed for everyone."
                    : "Its \(comment.replies.count == 1 ? "reply goes" : "replies go") with it."
            )
        }
    }

    private var threads: [PostComment] { store.comments(for: postID) }

    private func threadsHeader(_ post: FeedPost) -> some View {
        HStack {
            Text(post.commentCount == 1 ? "1 comment" : "\(post.commentCount) comments")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timeOfDay.primaryText)
            Spacer()
            if store.isLoadingComments(for: postID) && !threads.isEmpty {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.top, 4)
    }

    private var emptyThreads: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left")
                .font(.title3)
                .foregroundStyle(timeOfDay.accent)
            Text("No comments yet.")
                .font(.footnote)
                .foregroundStyle(timeOfDay.secondaryText)
            Text("Be the first to say something.")
                .font(.caption)
                .foregroundStyle(timeOfDay.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Writing

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()

            if let replyingTo = draft.replyingTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2)
                    Text("Replying to \(replyingTo.author.displayName)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Cancel") { draft.replyingTo = nil }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
                .foregroundStyle(timeOfDay.secondaryText)
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(draft.placeholder, text: $draft.body, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isWriting)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        timeOfDay.primaryText.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(
                            draft.isSendable ? timeOfDay.accent : timeOfDay.secondaryText.opacity(0.4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!draft.isSendable || store.isSendingComment)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }

    private func begin(replyingTo comment: PostComment) {
        // Always the thread's own comment, never a reply to a reply — which
        // the server refuses, so offering it would be offering an error.
        draft.replyingTo = comment.isReply ? nil : comment
        isWriting = true
    }

    private func send() {
        let sending = draft
        // Cleared before the round trip so the field is ready for the next
        // thought; a failure puts the words back rather than losing them.
        draft.clear()
        Task {
            await store.addComment(sending, toPost: postID)
            if store.errorMessage != nil, draft.body.isEmpty {
                draft = sending
            }
        }
    }
}

/// A comment and the replies under it.
private struct CommentThread: View {
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

private struct CommentRow: View {
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
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .lineLimit(1)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button("Reply", action: onReply)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                    if comment.viewerIsAuthor {
                        Button("Delete", action: onDelete)
                            .font(.caption.weight(.semibold))
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
        }
    }
}
