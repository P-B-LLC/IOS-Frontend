import Foundation

nonisolated struct SocialPublicationReceipt: Identifiable, Equatable, Sendable {
    let id = UUID()
    let postID: Int
}

nonisolated enum SocialPublicationEligibility {
    static func shared(approved: Bool, publishedAt: Date?, isPrivate: Bool, videoStatus: String?) -> Bool {
        approved && publishedAt != nil && !isPrivate && (videoStatus == nil || videoStatus == "approved")
    }

    static func shouldRefresh(moderationStatus: String, publishedAt: Date?, isPrivate: Bool,
                              videoStatus: String?, videoProcessingState: String?) -> Bool {
        guard !isPrivate, moderationStatus != "rejected", videoStatus != "rejected",
              videoStatus != "failed", videoProcessingState != "failed" else { return false }
        return !shared(approved: moderationStatus == "approved", publishedAt: publishedAt,
                       isPrivate: isPrivate, videoStatus: videoStatus)
    }
}

/// Reconciles confirmed publication with reads that may have started before it.
/// This holds no credentials and is reset whenever the account connection changes.
nonisolated struct SocialPublicationCoordinator<Post: Identifiable & Sendable> where Post.ID == Int {
    struct Observation {
        let accepted: Bool
        let announcePublication: Bool
    }

    private struct Snapshot {
        var post: Post
        let isOwn: Bool
        let eligible: Bool
        let expiresAt: Date
    }

    private(set) var revision: UInt64 = 0
    private var versions: [Int: UInt64] = [:]
    private var snapshots: [Int: Snapshot] = [:]
    private var submitted: [Int] = []
    private var heldForAttachment: Set<Int> = []
    private var recentPublished: [Int] = []
    private var announced: Set<Int> = []
    private var deleted: Set<Int> = []
    private var unavailable: Set<Int> = []
    private var publicationVersions: [Int: UInt64] = [:]
    private var lastStatusCheck: [Int: UInt64] = [:]
    private var checkSequence: UInt64 = 0

    mutating func reset() { self = Self() }

    mutating func trackSubmission(id: Int, awaitingAttachment: Bool) {
        if !submitted.contains(id) { submitted.insert(id, at: 0) }
        if awaitingAttachment { heldForAttachment.insert(id) }
        changed(id)
    }

    mutating func attachmentFinished(id: Int) {
        heldForAttachment.remove(id)
        changed(id)
    }

    @discardableResult
    mutating func observe(
        _ post: Post, isOwn: Bool, eligible: Bool, expiresAt: Date,
        readRevision: UInt64? = nil
    ) -> Observation {
        // A safety downgrade wins even when an engagement mutation or another
        // read completed first. Only stale attempts to expose a post are denied.
        guard !deleted.contains(post.id),
              !eligible || (readRevision.map({ (versions[post.id] ?? 0) <= $0 }) ?? true) else {
            return .init(accepted: false, announcePublication: false)
        }
        let prior = snapshots[post.id]
        let recent = submitted.contains(post.id) || recentPublished.contains(post.id)
            || (isOwn && prior?.isOwn == true && prior?.eligible == false)
        let visible = eligible && !heldForAttachment.contains(post.id)
        let wasUnavailable = unavailable.contains(post.id)
        if visible { unavailable.remove(post.id) }
        else { unavailable.insert(post.id) }
        // Ordinary feed/search rows remain in their destination collections.
        // Only local/known-pending own submissions need a content overlay.
        if isOwn, submitted.contains(post.id) || prior != nil || !visible {
            snapshots[post.id] = .init(post: post, isOwn: isOwn, eligible: visible, expiresAt: expiresAt)
            changed(post.id)
        } else if !visible || wasUnavailable {
            changed(post.id)
        }
        if !visible { recentPublished.removeAll { $0 == post.id } }
        if isOwn, visible, recent, !recentPublished.contains(post.id) {
            recentPublished.insert(post.id, at: 0)
            for id in recentPublished.dropFirst(20) {
                snapshots[id] = nil
                submitted.removeAll { $0 == id }
                publicationVersions[id] = nil
            }
            recentPublished = Array(recentPublished.prefix(20))
            publicationVersions[post.id] = revision
        }
        let shouldAnnounce = isOwn && visible && recent && announced.insert(post.id).inserted
        return .init(accepted: true, announcePublication: shouldAnnounce)
    }

    /// A fresh first page owns ranking/eligibility. Keep only publications that
    /// happened after that request began, so an older response cannot erase them.
    mutating func acknowledgeFirstPage(readRevision: UInt64) {
        let confirmed = recentPublished.filter { (publicationVersions[$0] ?? 0) <= readRevision }
        for id in confirmed {
            recentPublished.removeAll { $0 == id }
            submitted.removeAll { $0 == id }
            snapshots[id] = nil
        }
    }

    var pendingSubmissions: [Post] {
        snapshots.values.filter { $0.isOwn && !$0.eligible && !heldForAttachment.contains($0.post.id) }
            .map(\.post)
            .sorted {
                let lhs = lastStatusCheck[$0.id] ?? 0, rhs = lastStatusCheck[$1.id] ?? 0
                return lhs == rhs ? $0.id > $1.id : lhs < rhs
            }
    }

    mutating func markStatusChecked(id: Int) {
        checkSequence &+= 1
        lastStatusCheck[id] = checkSequence
    }

    mutating func remove(id: Int) {
        deleted.insert(id)
        snapshots[id] = nil
        submitted.removeAll { $0 == id }
        recentPublished.removeAll { $0 == id }
        heldForAttachment.remove(id)
        unavailable.insert(id)
        publicationVersions[id] = nil
        lastStatusCheck[id] = nil
        changed(id)
    }

    /// Non-approved/private posts are suppressed even if an older page carries
    /// an approved copy. Recent own publications bridge stale first-page reads.
    func publicPage(_ posts: [Post], prependOwn: Bool, now: Date = Date()) -> [Post] {
        let recent = prependOwn ? recentPublished.compactMap { id -> Post? in
            guard let snapshot = snapshots[id], snapshot.expiresAt > now else { return nil }
            return snapshot.post
        } : []
        return unique(recent + posts).compactMap { post in
            guard !isUnavailable(post.id) else { return nil }
            guard let snapshot = snapshots[post.id] else { return post }
            return snapshot.eligible ? snapshot.post : nil
        }
    }

    /// A pending submission belongs only on its author's status/profile surface.
    func authorPage(_ posts: [Post], matches: (Post) -> Bool) -> [Post] {
        let local = submitted.compactMap { snapshots[$0]?.post }.filter(matches)
        return resolvedPage(local + posts)
    }

    func resolvedPage(_ posts: [Post]) -> [Post] {
        unique(posts).compactMap { post in
            guard !deleted.contains(post.id) else { return nil }
            return snapshots[post.id]?.post ?? post
        }
    }

    func isDeleted(_ id: Int) -> Bool { deleted.contains(id) }

    func isUnavailable(_ id: Int) -> Bool {
        deleted.contains(id) || heldForAttachment.contains(id) || unavailable.contains(id)
    }

    mutating func mutate(where matches: (Post) -> Bool, _ change: (inout Post) -> Void) {
        for id in Array(snapshots.keys) {
            guard var snapshot = snapshots[id], matches(snapshot.post) else { continue }
            change(&snapshot.post)
            snapshots[id] = snapshot
            changed(id)
        }
    }

    private mutating func changed(_ id: Int) {
        revision &+= 1
        versions[id] = revision
    }

    private func unique(_ posts: [Post]) -> [Post] {
        var seen: Set<Int> = []
        return posts.filter { seen.insert($0.id).inserted }
    }
}
