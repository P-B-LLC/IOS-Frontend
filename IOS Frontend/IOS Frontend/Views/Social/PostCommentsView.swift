//
//  PostCommentsView.swift
//  IOS Frontend
//
//  The threads on a post and the box to add to them.
//
//  Shared by the post's own page and the sheet the feed raises, so the two
//  cannot drift into behaving differently. What changes between them is only
//  where the bottom of the screen is: pushed under the app's floating tab bar
//  the composer has to clear it, and in a sheet there is no bar to clear.
//

import SwiftUI

struct PostCommentsView: View {
    let postID: Int
    let timeOfDay: HomeTimeOfDay
    /// True when this is pushed under the app's tab bar, which is drawn over
    /// the screen rather than inset out of it.
    var clearsBottomBar: Bool = false
    /// Raised by the parent to put the cursor in the box — what the comment
    /// button does once the thread is already on screen.
    @Binding var focusRequest: Int

    @Environment(SocialStore.self) private var store

    @State private var draft = CommentDraft()
    @State private var confirmingDelete: PostComment?
    @FocusState private var isWriting: Bool

    private var threads: [PostComment] { store.comments(for: postID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header

                    if store.isLoadingComments(for: postID) && threads.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else if threads.isEmpty {
                        empty
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
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            composer
        }
        // Both, deliberately. `onChange` alone never fired for the sheet,
        // which arrives with the request already set and so never changes it:
        // the box was there and the keyboard was not.
        .task { if focusRequest > 0 { isWriting = true } }
        .onChange(of: focusRequest) { isWriting = true }
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

    private var header: some View {
        HStack {
            Text(countText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timeOfDay.primaryText)
            Spacer()
            if store.isLoadingComments(for: postID) && !threads.isEmpty {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private var countText: String {
        let total = store.post(withID: postID)?.commentCount
            ?? threads.reduce(0) { $0 + $1.totalCount }
        return total == 1 ? "1 comment" : "\(total) comments"
    }

    private var empty: some View {
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
                    // No `.submitLabel(.send)`. The field grows vertically, so
                    // return inserts a newline and never submits — a send
                    // arrow on that key would promise something it does not
                    // do. The button beside the field is the way to send.
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
                            draft.isSendable
                                ? timeOfDay.accent
                                : timeOfDay.secondaryText.opacity(0.4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!draft.isSendable || store.isSendingComment)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.vertical, 10)
            // Clear of the floating tab bar, which is drawn over a pushed
            // screen rather than inset out of it. Dropped once the keyboard
            // is up, since the keyboard covers the bar anyway, and never
            // applied in a sheet, where there is no bar.
            .padding(
                .bottom,
                clearsBottomBar && !isWriting
                    ? RepbaseDesign.bottomBarClearance - 10
                    : 0
            )
        }
        .background(.thinMaterial)
        .animation(.easeOut(duration: 0.2), value: isWriting)
    }

    private func begin(replyingTo comment: PostComment) {
        // Always the thread's own comment, never a reply to a reply — which
        // the server refuses, so offering it would be offering an error.
        draft.replyingTo = comment.isReply ? nil : comment
        isWriting = true
    }

    private func send() {
        let sending = draft
        // Cleared before the round trip so the box is ready for the next
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

/// The threads raised over the feed, so a comment can be left without leaving
/// the list.
struct PostCommentsSheet: View {
    let postID: Int
    let timeOfDay: HomeTimeOfDay

    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Opens with the cursor already in the box: this sheet is raised by the
    /// comment button, so writing one is what it was opened to do.
    @State private var focusRequest = 1

    var body: some View {
        NavigationStack {
            PostCommentsView(
                postID: postID,
                timeOfDay: timeOfDay,
                focusRequest: $focusRequest
            )
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await store.loadComments(for: postID) }
    }
}
