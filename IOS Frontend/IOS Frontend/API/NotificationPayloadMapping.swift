import Foundation
import RepbaseAPI

/// The optional additions deliberately decode on both the current beta and
/// the richer testing backend. Old responses cannot opt into scoped writes.
nonisolated enum NotificationPayloadMapping {
    static func notification(from row: Components.Schemas.Notification) -> SocialNotification {
        SocialNotification(
            id: row.id,
            kind: SocialNotification.Kind(rawValue: row.kind.rawValue) ?? .unknown,
            actorID: row.actorId,
            actorUsername: row.actorUsername,
            actorFirstName: row.actorFirstName,
            actorLastName: row.actorLastName,
            actorPhotoURL: row.actorPhotoUrl,
            postID: row.post,
            commentBody: row.commentBody,
            isRead: row.isRead,
            createdAt: row.createdAt,
            postPreview: row.postPreview.map { payload in
                let preview = payload.value1
                return SocialNotificationPostPreview(
                    id: preview.id,
                    kind: preview.kind,
                    title: preview.title,
                    thumbnailURL: preview.thumbnailUrl,
                    mediaKind: preview.mediaKind
                )
            },
            supportsScopedRead: row.supportsScopedRead ?? false
        )
    }
}
