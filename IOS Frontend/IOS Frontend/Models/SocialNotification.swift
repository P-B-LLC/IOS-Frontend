import Foundation

/// Only the recipient-authorized, bounded preview returned by the backend.
/// Never infer a private media URL from a post ID or fetch a full post per row.
nonisolated struct SocialNotificationPostPreview: Equatable, Hashable, Sendable {
    let id: Int
    let kind: String
    let title: String
    let thumbnailURL: String?
    let mediaKind: String
}

/// One server event; the notification screen groups these without changing
/// the identity of the individual events used for read acknowledgements.
nonisolated struct SocialNotification: Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case follow
        case followRequest = "follow_request"
        case followApproved = "follow_approved"
        case like
        case repost
        case comment
        case moderationRejected = "moderation_rejected"
        case unknown

        var isPostInteraction: Bool {
            self == .like || self == .comment || self == .repost
        }
    }

    let id: Int
    let kind: Kind
    let actorID: Int
    let actorUsername: String
    let actorFirstName: String
    let actorLastName: String
    let actorPhotoURL: String?
    let postID: Int?
    let commentBody: String?
    var isRead: Bool
    var createdAt: Date? = nil
    var postPreview: SocialNotificationPostPreview? = nil
    /// Old servers ignore read request bodies and mark everything read.
    /// Absence of this capability must never invoke that legacy operation.
    var supportsScopedRead = false

    var actorName: String {
        if kind == .moderationRejected { return "Rytivo" }
        let full = "\(actorFirstName) \(actorLastName)"
            .trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? actorUsername : full
    }

    var summary: String {
        switch kind {
        case .follow: return String(localized: "\(actorName) started following you", bundle: .app, locale: .app)
        case .followRequest: return String(localized: "\(actorName) asked to follow you", bundle: .app, locale: .app)
        case .followApproved: return String(localized: "\(actorName) accepted your follow request", bundle: .app, locale: .app)
        case .like: return String(localized: "\(actorName) liked your post", bundle: .app, locale: .app)
        case .repost: return String(localized: "\(actorName) reposted your post", bundle: .app, locale: .app)
        case .comment: return String(localized: "\(actorName) commented on your post", bundle: .app, locale: .app)
        case .moderationRejected:
            return String(
                localized: "\(actorName) did not publish your post after review. You can check it on your profile or contact support.",
                bundle: .app,
                locale: .app,
                comment: "The placeholder is the app's name, Rytivo"
            )
        case .unknown: return String(localized: "\(actorName) did something", bundle: .app, locale: .app)
        }
    }

    var symbol: String {
        switch kind {
        case .follow, .followRequest: return "person.badge.plus"
        case .followApproved: return "person.crop.circle.badge.checkmark"
        case .like: return "heart.fill"
        case .repost: return "arrow.2.squarepath"
        case .comment: return "bubble.left"
        case .moderationRejected: return "exclamationmark.shield"
        case .unknown: return "bell"
        }
    }
}
