import Foundation

/// A post occurs once, even when its activity crosses dates or API pages.
/// People are deduplicated independently from action counts: a person can
/// like, comment and repost the same post without becoming three people.
nonisolated struct SocialNotificationGroup: Identifiable, Equatable, Sendable {
    let id: String
    let notifications: [SocialNotification]

    var latest: SocialNotification { notifications[0] }
    var createdAt: Date? { latest.createdAt }
    var isPostActivity: Bool { latest.kind.isPostInteraction && latest.postID != nil }
    var postID: Int? { isPostActivity ? latest.postID : nil }
    // The newest response is authoritative, including a missing preview.
    // Never revive an older URL after a newer response has revoked access.
    var preview: SocialNotificationPostPreview? { latest.postPreview }
    var isRead: Bool { notifications.allSatisfy(\.isRead) }
    var unreadIDs: [Int] { notifications.filter { !$0.isRead }.map(\.id) }
    var likes: Int { count(.like) }
    var comments: Int { count(.comment) }
    var reposts: Int { count(.repost) }
    var actors: [SocialNotification] {
        var seen = Set<Int>()
        return notifications.filter { seen.insert($0.actorID).inserted }
    }

    private func count(_ kind: SocialNotification.Kind) -> Int {
        notifications.lazy.filter { $0.kind == kind }.count
    }
}

nonisolated enum SocialNotificationGrouping {
    static func groups(from notifications: [SocialNotification]) -> [SocialNotificationGroup] {
        var rowsByID: [Int: SocialNotification] = [:]
        for row in notifications {
            // Numbered pages can overlap when new events arrive. Prefer the
            // last response, preserving any confirmed read status.
            var current = row
            current.isRead = row.isRead || (rowsByID[row.id]?.isRead ?? false)
            rowsByID[row.id] = current
        }
        let sorted = rowsByID.values.sorted(by: newestFirst)
        var keys: [String] = []
        var byKey: [String: [SocialNotification]] = [:]
        for row in sorted {
            let key: String
            if row.kind.isPostInteraction, let postID = row.postID {
                key = "post:\(postID)"
            } else {
                key = "notification:\(row.id)"
            }
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(row)
        }
        return keys.map { SocialNotificationGroup(id: $0, notifications: byKey[$0]!) }
    }

    static func newestFirst(_ lhs: SocialNotification, _ rhs: SocialNotification) -> Bool {
        let left = lhs.createdAt ?? .distantPast
        let right = rhs.createdAt ?? .distantPast
        return left == right ? lhs.id > rhs.id : left > right
    }
}

/// Pending/confirmed read state belongs to the current account only. Keeping
/// it independent from SwiftUI makes race and legacy-server rules testable.
nonisolated struct SocialNotificationReadState {
    private(set) var pending: Set<Int> = []
    private(set) var confirmed: Set<Int> = []

    mutating func enqueue(_ ids: [Int], in rows: [SocialNotification]) {
        let requested = Set(ids)
        let eligible = rows.filter {
            requested.contains($0.id) && !$0.isRead && $0.supportsScopedRead
                && !confirmed.contains($0.id)
        }.map(\.id)
        pending.formUnion(eligible)
    }

    mutating func takeBatch() -> [Int] {
        let batch = Array(pending.sorted().prefix(500))
        pending.subtract(batch)
        return batch
    }

    mutating func complete(_ ids: [Int]) {
        confirmed.formUnion(ids)
        pending.subtract(ids)
    }

    mutating func retry(_ ids: [Int]) {
        pending.formUnion(ids.filter { !confirmed.contains($0) })
    }

    func applyingConfirmedReads(to rows: [SocialNotification]) -> [SocialNotification] {
        rows.map { row in
            var current = row
            if confirmed.contains(row.id) { current.isRead = true }
            return current
        }
    }

    mutating func retain(_ ids: Set<Int>) {
        confirmed.formIntersection(ids)
        pending.formIntersection(ids)
    }
}
