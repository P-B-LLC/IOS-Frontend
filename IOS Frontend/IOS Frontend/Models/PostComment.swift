//
//  PostComment.swift
//  IOS Frontend
//
//  What people said under a post.
//
//  One level of nesting, enforced by the server: a thread is a comment and the
//  replies under it. Deeper than that indents off the side of a phone and stops
//  being readable, so a reply to a reply is refused rather than re-parented.
//

import Foundation

nonisolated struct PostComment: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let postID: Int
    var author: PostAuthor
    /// Nil for a top-level comment.
    var parentID: Int?
    var body: String
    /// Always empty on a reply, because a reply cannot have any.
    var replies: [PostComment]
    /// Whether the person reading wrote it, and so may delete it.
    var viewerIsAuthor: Bool
    var createdAt: Date

    var isReply: Bool { parentID != nil }

    /// This comment and its replies, counted the way the post's badge counts
    /// them — the server includes replies in `commentCount`.
    var totalCount: Int { 1 + replies.count }
}

/// A comment being written, and where it is going.
nonisolated struct CommentDraft: Equatable, Hashable, Sendable {
    var body: String = ""
    /// The comment being answered, or nil to start a new thread.
    var replyingTo: PostComment?

    var isSendable: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the composer says it is about to do.
    var placeholder: String {
        guard let replyingTo else { return "Add a comment" }
        return "Reply to \(replyingTo.author.displayName)"
    }

    mutating func clear() {
        body = ""
        replyingTo = nil
    }
}
