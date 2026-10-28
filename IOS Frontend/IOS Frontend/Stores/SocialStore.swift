//
//  SocialStore.swift
//  IOS Frontend
//
//  The feed, and posting to it. Holds what the server last said and nothing
//  else.
//

import Foundation
import Observation

@MainActor
@Observable
final class SocialStore {
    private var repository: SocialAPIRepository?
    private var connectionGeneration = UUID()
    private let likes = SocialLikeCoordinator()
    private var publications = SocialPublicationCoordinator<FeedPost>()
    private var followingReadID = UUID()
    private var forYouReadID = UUID()
    private(set) var publicationReceipt: SocialPublicationReceipt?
    private var isRefreshingPublicationStatuses = false
    /// Where the next page starts. Nil once the feed has been read to the end.
    private var nextCursor: String?
    /// Whether the following feed has no more pages, so the Following tab can
    /// say the reader is caught up.
    private(set) var hasReachedEnd = false

    private(set) var feed: [FeedPost] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isPosting = false
    private(set) var errorMessage: String?
    /// Whether the failure behind `errorMessage` is worth offering a retry
    /// for. An outage is; a refusal under community standards is not, and a
    /// retry button in front of one invites pressing it until it works.
    private(set) var errorIsRetryable = false
    /// Set when a post goes out, so a screen can say so and move on.
    private(set) var lastPosted: FeedPost?
    private(set) var followersByUser: [Int: [PostAuthor]] = [:]
    private(set) var followingByUser: [Int: [PostAuthor]] = [:]
    private(set) var changingFollowFor: Set<Int> = []
    /// What has happened to the signed-in user, newest first.
    private(set) var notifications: [SocialNotification] = []
    /// How many of those have not been seen. Kept apart from the list because
    /// the badge is wanted in places that have no reason to load the page.
    private(set) var unreadNotifications = 0
    /// People asking to follow the signed-in user, newest first.
    private(set) var followRequests: [FollowRequestSummary] = []
    /// Requests being answered, so a row cannot be approved twice while the
    /// first answer is still in the air.
    private(set) var answeringRequests: Set<Int> = []
    /// People this viewer has asked to follow and not been answered by.
    ///
    /// Held here as well as on the profile payload because the payload is a
    /// snapshot: after the tap that made the request, the button has to change
    /// without the profile being fetched again.
    private(set) var requestedUserIDs: Set<Int> = []

    var isConnected: Bool { repository != nil }

    init() {}

    // MARK: - Failures

    /// The one place a failure becomes something a screen can show.
    ///
    /// Two things travel together: what to say, and whether offering a retry
    /// would be honest. Set apart, `errorIsRetryable` ends up describing the
    /// failure before last — which is how a refusal acquires a retry button.
    private func showFailure(_ error: Error) {
        errorMessage = error.userFacingMessage
        errorIsRetryable = error.isRetryableFailure
    }

    /// For the few failures the store states itself rather than catching.
    /// None of them are worth retrying by the same route.
    private func showFailure(message: String) {
        errorMessage = message
        errorIsRetryable = false
    }

    // MARK: - The server

    func connect(configuration: APIConfiguration, token: String) async {
        // A reconnect is also an account boundary; never retain another
        // account's pending submissions, receipt, or in-flight read state.
        disconnect()
        let generation = UUID()
        connectionGeneration = generation
        isLoading = true
        clearError()
        defer { if connectionGeneration == generation { isLoading = false } }

        do {
            let repository = try SocialAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository

            let readRevision = publications.revision
            let page = try await repository.feed()
            guard connectionGeneration == generation else { return }
            feed = reconcilePublicPage(page.posts, readRevision: readRevision, prependOwn: true)
            nextCursor = page.nextCursor
            hasReachedEnd = page.nextCursor == nil
        } catch {
            guard connectionGeneration == generation else { return }
            repository = nil
            showFailure(error)
        }
    }

    func disconnect() {
        likes.reset()
        publications.reset()
        publicationReceipt = nil
        isRefreshingPublicationStatuses = false
        followingReadID = UUID()
        forYouReadID = UUID()
        connectionGeneration = UUID()
        repository = nil
        feed = []
        nextCursor = nil
        hasReachedEnd = false
        isLoading = false
        isLoadingMore = false
        isPosting = false
        clearError()
        lastPosted = nil
        // Results name real people and are answered per reader — a block is
        // applied against whoever asked — so they belong to the account that
        // searched and must not outlive it.
        clearSearch()
        followersByUser = [:]
        followingByUser = [:]
        changingFollowFor = []
        // Who is waiting on this account, and who this account is waiting on.
        // Both belong to whoever was signed in, and neither may outlive them.
        followRequests = []
        answeringRequests = []
        requestedUserIDs = []
        notifications = []
        unreadNotifications = 0
        // One account's count must never sit on the icon for the next. Signing
        // out is not reading them, so this clears the number without touching
        // what the server still holds as unread.
        Task { await NotificationScheduler.shared.setBadge(0) }
        // One account's threads must never be shown to the next.
        comments = [:]
        locallyBlockedAuthorIDs = []
        openedPosts = [:]
        authorPosts = [:]
        loadingCommentsFor = []
        loadingPostsFor = []
        isSendingComment = false
        lastSavedWorkout = nil
        lastSavedMeal = nil
        lastModerationMessage = nil
        blockedPeople = []
        savingMealFor = []
        savingWorkoutFor = []
        // What For You knows is about whoever was signed in: their page,
        // what they dismissed, what they have looked at, who is suggested to
        // them. None of it may reach the next account, the unsent viewings
        // least of all.
        forYou = []
        forYouCursor = nil
        hasReachedEndOfForYou = false
        hasLoadedForYou = false
        isLoadingForYou = false
        isLoadingMoreForYou = false
        dismissals = [:]
        wantedPostIDs = []
        impressionFlush?.cancel()
        impressionFlush = nil
        impressions.reset()
        forYouPreferences = nil
        forYouPreferencesError = nil
        isSavingForYouPreferences = false
        forYouNeedsReranking = false
        suggestedPeople = []
        dismissedSuggestionIDs = []
        hasLoadedSuggestions = false
    }

    // MARK: - Reading

    func refresh() async {
        guard let repository else { return }
        let generation = connectionGeneration
        let readID = UUID()
        followingReadID = readID
        clearError()
        let readRevision = publications.revision
        do {
            let page = try await repository.feed()
            guard connectionGeneration == generation, followingReadID == readID else { return }
            feed = reconcilePublicPage(page.posts, readRevision: readRevision, prependOwn: true)
            nextCursor = page.nextCursor
            hasReachedEnd = page.nextCursor == nil
            await refreshPendingPublications(using: repository, generation: generation)
        } catch {
            guard connectionGeneration == generation, followingReadID == readID else { return }
            showFailure(error)
        }
    }

    /// Reads the next page when the last card comes into view.
    ///
    /// Guarded against being asked twice at once: scrolling fires this on
    /// several rows in quick succession, and two pages read from the same
    /// cursor would put the same posts in the list twice.
    func loadMore() async {
        guard let repository,
              let cursor = nextCursor,
              !hasReachedEnd,
              !isLoadingMore
        else { return }

        let generation = connectionGeneration
        let readID = followingReadID
        let readRevision = publications.revision
        isLoadingMore = true
        defer { if connectionGeneration == generation { isLoadingMore = false } }

        do {
            let page = try await repository.feed(after: cursor)
            guard connectionGeneration == generation, followingReadID == readID, nextCursor == cursor else { return }
            // Filtered against what is already held rather than appended
            // blindly: a post written between two page reads shifts the
            // boundary, and the cursor is a position, not a promise.
            let next = reconcilePublicPage(page.posts, readRevision: readRevision, prependOwn: false)
            feed = publications.publicPage(feed + next, prependOwn: true)
            nextCursor = page.nextCursor
            hasReachedEnd = page.nextCursor == nil
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    func loadRelationships(for userID: Int) async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            async let followers = repository.followers(of: userID)
            async let following = repository.following(of: userID)
            let values = try await (followers, following)
            guard connectionGeneration == generation else { return }
            followersByUser[userID] = values.0
            followingByUser[userID] = values.1
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    func setFollowing(_ follows: Bool, user: PostAuthor, viewerID: Int?) async {
        guard let repository, !changingFollowFor.contains(user.id) else { return }
        changingFollowFor.insert(user.id)
        defer { changingFollowFor.remove(user.id) }
        do {
            if follows {
                // A closed profile cannot be followed outright; the same tap
                // leaves a request instead, and the button has to say so
                // rather than claiming a follow that did not happen.
                let outcome = try await repository.follow(user.id)
                switch outcome {
                case .requested:
                    requestedUserIDs.insert(user.id)
                    return
                case .following:
                    requestedUserIDs.remove(user.id)
                }
            } else {
                try await repository.unfollow(user.id)
                // Unfollowing and withdrawing a request are the same call and
                // the same button, so both states clear together.
                requestedUserIDs.remove(user.id)
            }
            applyToAuthor(user.id) { $0.viewerFollowsAuthor = follows }
            if let viewerID { await loadRelationships(for: viewerID) }
        } catch {
            showFailure(error)
        }
    }

    // MARK: - What has happened to you

    func loadNotifications() async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            let loaded = try await repository.notifications()
            guard connectionGeneration == generation else { return }
            notifications = loaded
            // An approval is the answer to a request this device is still
            // drawing as pending. The button reads a profile snapshot that
            // only changes on a refetch, so it went on saying "Requested"
            // after they had been let in.
            //
            // It did tend to right itself, because the way somebody learns
            // they were approved is this page, and the way they act on it is
            // to open the profile — which refetches. That is luck in the
            // shape of a fix, and it fails for anyone who reads the row and
            // goes somewhere else.
            for row in loaded where row.kind == .followApproved {
                requestedUserIDs.remove(row.actorID)
            }
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    func refreshUnreadNotificationCount() async {
        guard let repository else { return }
        let generation = connectionGeneration
        // Quietly: this runs to draw a dot, and a failed count is not worth a
        // message across a page somebody is reading for another reason.
        if let count = try? await repository.unreadNotificationCount(),
           connectionGeneration == generation {
            unreadNotifications = count
            await NotificationScheduler.shared.setBadge(count)
        }
    }

    /// Marks everything seen, which is what opening the page means.
    func markNotificationsRead() async {
        guard let repository, unreadNotifications > 0 else { return }
        let generation = connectionGeneration
        do {
            try await repository.markNotificationsRead()
            guard connectionGeneration == generation else { return }
            unreadNotifications = 0
            // The rows on screen as well as the count. The server has them
            // marked and the badge is cleared, but each row still carried the
            // `isRead` it was fetched with, so the dots stayed lit down a page
            // that had just read every one of them — and stayed lit until
            // something refetched, which on this page is nothing.
            notifications = notifications.map { row in
                var seen = row
                seen.isRead = true
                return seen
            }
            await NotificationScheduler.shared.setBadge(0)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - Requests waiting on you

    func loadFollowRequests() async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            let loaded = try await repository.followRequests()
            guard connectionGeneration == generation else { return }
            followRequests = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// Lets somebody in, or turns them away.
    ///
    /// The row goes either way, which is what both answers have in common: a
    /// declined request leaves nothing on file, because a record of having
    /// been refused is a note about somebody they cannot see.
    func answerFollowRequest(
        _ request: FollowRequestSummary,
        approve: Bool
    ) async {
        guard let repository, !answeringRequests.contains(request.id) else { return }
        answeringRequests.insert(request.id)
        defer { answeringRequests.remove(request.id) }
        let generation = connectionGeneration
        do {
            if approve {
                try await repository.approveFollowRequest(request.id)
            } else {
                try await repository.declineFollowRequest(request.id)
            }
            guard connectionGeneration == generation else { return }
            followRequests.removeAll { $0.id == request.id }
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - Posting

    /// Shares a workout, meal or planner entry the signed-in user owns.
    ///
    /// Returns whether it went out, so the sheet that called it knows whether
    /// to close. The new post is put at the top of the feed rather than the
    /// feed being read again: it is the newest thing there by definition.
    @discardableResult
    func post(
        kind: PostKind,
        sourceID: Int,
        caption: String,
        visibility: PostVisibility,
        showsWeights: Bool = true,
        photo: PostPhoto? = nil,
        cookingInstructions: String = "",
        video: PostVideoDraft? = nil
    ) async -> Bool {
        guard !isPosting else { return false }
        guard let repository else {
            showFailure(message: String(localized: "Connect to Rytivo before posting.", bundle: .app, locale: .app))
            return false
        }

        let generation = connectionGeneration
        isPosting = true
        lastPosted = nil
        clearError()
        defer { if connectionGeneration == generation { isPosting = false } }

        do {
            if let video { try await video.validate() }
            let posted = try await repository.post(
                kind: kind,
                sourceID: sourceID,
                caption: caption,
                visibility: visibility,
                showsWeights: showsWeights,
                photo: photo,
                cookingInstructions: cookingInstructions
            )
            guard connectionGeneration == generation else { return false }
            publications.trackSubmission(id: posted.id, awaitingAttachment: video != nil)
            lastPosted = posted
            openedPosts[posted.id] = posted
            replace(posted)
            if let video {
                let updated = try await repository.uploadVideo(postID: posted.id, draft: video)
                guard connectionGeneration == generation else { return false }
                publications.attachmentFinished(id: posted.id)
                replace(updated)
                lastPosted = updated
            }
            lastModerationMessage = lastPosted?.publicationMessage
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            showFailure(error)
            return false
        }
    }

    func delete(_ post: FeedPost) {
        guard let repository else { return }
        let generation = connectionGeneration
        Task {
            do {
                try await repository.delete(post.id)
                guard connectionGeneration == generation else { return }
                removePost(id: post.id)
            } catch {
                guard connectionGeneration == generation else { return }
                showFailure(error)
            }
        }
    }

    func retryVideo(postID: Int, draft: PostVideoDraft) async -> Bool {
        guard let repository, !isPosting else { return false }
        let generation = connectionGeneration
        isPosting = true
        publications.trackSubmission(id: postID, awaitingAttachment: true)
        feed = publications.publicPage(feed, prependOwn: true)
        forYou = ownRecommendation(publications.publicPage(forYou, prependOwn: true))
        clearError()
        defer { if generation == connectionGeneration { isPosting = false } }
        do {
            let updated = try await repository.retryVideo(postID: postID, draft: draft)
            guard generation == connectionGeneration else { return false }
            publications.attachmentFinished(id: postID)
            replace(updated)
            lastPosted = updated
            lastModerationMessage = updated.publicationMessage
            return true
        } catch {
            guard generation == connectionGeneration else { return false }
            showFailure(error)
            return false
        }
    }

    func refreshVideo(postID: Int) async throws -> PostVideoMedia? {
        guard let repository else { throw CancellationError() }
        let generation = connectionGeneration
        let readRevision = publications.revision
        let updated = try await repository.post(withID: postID)
        guard generation == connectionGeneration else { throw CancellationError() }
        guard replace(updated, readRevision: readRevision) else { return post(withID: postID)?.video }
        return updated.video
    }

    func recordVideoPlayback(postID: Int, failed: Bool) async {
        guard let repository else { return }
        await repository.recordVideoPlayback(postID: postID, failed: failed)
    }

    // MARK: - Liking and reposting

    /// All copies of an original post share one pending like operation.
    func isLikePending(_ post: FeedPost) -> Bool {
        likes.isPending(post.repostOf?.id ?? post.id)
    }

    func toggleLike(_ post: FeedPost) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let originalID = post.repostOf?.id ?? post.id
        let current = self.post(withID: originalID) ?? self.post(withID: post.id) ?? post
        let wanted = !current.viewerHasLiked
        do {
            guard let saved = try await likes.submit(postID: originalID, operation: {
                let result = try await repository.setLiked(wanted, postID: originalID)
                return .init(liked: result.viewerHasLiked, count: result.likeCount)
            }), connectionGeneration == generation else { return }
            // Patch only like fields: a like response must not overwrite a
            // caption, comment count or repost changed while it was in flight.
            applyLike(saved, originalID: originalID)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    private func applyLike(_ saved: SocialLikeCoordinator.Confirmation, originalID: Int) {
        func update(_ post: inout FeedPost) {
            guard post.id == originalID || post.repostOf?.id == originalID else { return }
            post.viewerHasLiked = saved.liked
            post.likeCount = max(0, saved.count)
        }
        for index in feed.indices { update(&feed[index]) }
        for index in forYou.indices { update(&forYou[index]) }
        for index in discoverPosts.indices { update(&discoverPosts[index]) }
        for index in searchedPosts.indices { update(&searchedPosts[index]) }
        for id in Array(openedPosts.keys) {
            if var post = openedPosts[id] { update(&post); openedPosts[id] = post }
        }
        for author in Array(authorPosts.keys) {
            guard var posts = authorPosts[author] else { continue }
            for index in posts.indices { update(&posts[index]) }
            authorPosts[author] = posts
        }
        publications.mutate(where: { $0.id == originalID || $0.repostOf?.id == originalID }, update)
    }

    /// Passes a post on, or takes it back.
    ///
    /// Not optimistic, unlike a like. A repost puts something on other
    /// people's feeds, and showing it as done before the server agrees is a
    /// claim about what they can see.
    func toggleRepost(_ post: FeedPost) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let wanted = !post.viewerHasReposted

        do {
            let saved = try await repository.setReposted(wanted, postID: post.id)
            guard connectionGeneration == generation else { return }
            // The answer is the original, which on a repost card is a
            // different post than the one tapped.
            replace(saved)
            if post.repostOf != nil {
                if wanted {
                    apply(to: post.id) { $0.viewerHasReposted = true }
                } else {
                    // Undone from the reader's own repost card, so that card
                    // is the copy being withdrawn and goes now. Undone from
                    // the original's card instead, a repost card elsewhere in
                    // the feed is left for the next refresh: finding it would
                    // mean knowing which of these posts the reader wrote, and
                    // the feed does not carry that.
                    if post.viewerIsAuthor { removePost(id: post.id) }
                    else { apply(to: post.id) { $0.viewerHasReposted = false } }
                }
            }
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - For You

    /// Posts the server picked for the reader, best first, each carrying why.
    ///
    /// Its own list rather than a view over `feed`: the server ranks it, the
    /// following feed is the people chosen in the order they posted, and the
    /// two answer different questions.
    private(set) var forYou: [FeedPost] = []
    private(set) var isLoadingForYou = false
    private(set) var isLoadingMoreForYou = false
    private(set) var hasReachedEndOfForYou = false
    /// Whether a first page has been asked for on this connection, so opening
    /// the tab ranks once rather than on every appearance.
    private(set) var hasLoadedForYou = false
    private var forYouCursor: String?
    /// Posts the reader said "not interested" or "fewer like this" to here.
    /// Kept in the list and drawn as a line with an undo: a mis-tap should
    /// cost one more tap, not the post.
    private(set) var dismissals: [Int: ForYouDismissal] = [:]
    /// Posts the reader asked for more like here. The card stays; its menu
    /// shows the choice, and is the way to take it back.
    private(set) var wantedPostIDs: Set<Int> = []

    /// Ranks afresh and replaces the page. What is on screen is sent first,
    /// so the ranking about to be made already knows it was seen.
    func loadForYou() async {
        guard let repository, !isLoadingForYou else { return }
        let generation = connectionGeneration
        let readID = UUID()
        forYouReadID = readID
        isLoadingForYou = true
        defer { if connectionGeneration == generation { isLoadingForYou = false } }
        await finishImpressions()
        guard connectionGeneration == generation, forYouReadID == readID else { return }
        let readRevision = publications.revision
        do {
            let page = try await repository.forYou()
            guard connectionGeneration == generation, forYouReadID == readID else { return }
            publications.acknowledgeFirstPage(readRevision: readRevision)
            forYou = ownRecommendation(reconcilePublicPage(page.posts, readRevision: readRevision, prependOwn: true))
            if let receipt = publicationReceipt, !forYou.contains(where: { $0.id == receipt.postID }) {
                publicationReceipt = nil
            }
            forYouCursor = page.nextCursor
            hasReachedEndOfForYou = page.nextCursor == nil
            hasLoadedForYou = true
            dismissals = [:]
            wantedPostIDs = []
            forYouNeedsReranking = false
            await refreshPendingPublications(using: repository, generation: generation)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// The next stretch, as the last card comes into view. Guarded against
    /// being asked twice at once, like `loadMore`.
    func loadMoreForYou() async {
        guard let repository,
              let cursor = forYouCursor,
              !hasReachedEndOfForYou,
              !isLoadingMoreForYou
        else { return }

        let generation = connectionGeneration
        let readID = forYouReadID
        let readRevision = publications.revision
        isLoadingMoreForYou = true
        defer { if connectionGeneration == generation { isLoadingMoreForYou = false } }

        // Sent first for the same reason as a refresh: the server re-ranks the
        // rest of the session for what the reader has done, and what they
        // scrolled past is part of that.
        await flushImpressions()
        do {
            let page = try await repository.forYou(after: cursor)
            guard connectionGeneration == generation, forYouReadID == readID, forYouCursor == cursor else { return }
            // The server never repeats a post within a session; a session that
            // expired starts again from the top, and that can. A duplicate id
            // in a ForEach is a crash, so it is filtered here.
            let next = reconcilePublicPage(page.posts, readRevision: readRevision, prependOwn: false)
            forYou = ownRecommendation(publications.publicPage(forYou + next, prependOwn: true))
            forYouCursor = page.nextCursor
            hasReachedEndOfForYou = page.nextCursor == nil
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// "Not interested", and taking it back.
    ///
    /// Optimistic, unlike a repost: it changes nothing anybody else sees, and
    /// the line that replaces the card is also the way to undo it.
    func setNotInterested(_ notInterested: Bool, post: FeedPost) async {
        await setDismissal(.notInterested, notInterested, post: post)
    }

    /// "Fewer like this", and taking it back. Optimistic, like "not
    /// interested", and drawn the same way.
    func setFewerLikeThis(_ fewer: Bool, post: FeedPost) async {
        await setDismissal(.fewerLikeThis, fewer, post: post)
    }

    /// "More like this", and taking it back. The card stays where it is:
    /// asking for more of something is no reason to lose it.
    func setMoreLikeThis(_ more: Bool, post: FeedPost) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let wasWanted = wantedPostIDs.contains(post.id)
        if more {
            wantedPostIDs.insert(post.id)
        } else {
            wantedPostIDs.remove(post.id)
        }
        do {
            try await repository.setMoreLikeThis(more, postID: post.id)
        } catch {
            guard connectionGeneration == generation else { return }
            if wasWanted {
                wantedPostIDs.insert(post.id)
            } else {
                wantedPostIDs.remove(post.id)
            }
            showFailure(error)
        }
    }

    /// A post holds one choice on the server, so saying one here replaces
    /// "more like this" on it too.
    private func setDismissal(_ how: ForYouDismissal, _ on: Bool, post: FeedPost) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let before = dismissals[post.id]
        let wasWanted = wantedPostIDs.contains(post.id)
        if on {
            dismissals[post.id] = how
            wantedPostIDs.remove(post.id)
        } else {
            dismissals[post.id] = nil
        }
        do {
            switch how {
            case .notInterested:
                try await repository.setNotInterested(on, postID: post.id)
            case .fewerLikeThis:
                try await repository.setFewerLikeThis(on, postID: post.id)
            }
        } catch {
            guard connectionGeneration == generation else { return }
            dismissals[post.id] = before
            if wasWanted { wantedPostIDs.insert(post.id) }
            showFailure(error)
        }
    }

    // MARK: - What was on screen

    /// Viewings waiting to be sent, and the open ones.
    private var impressions = ImpressionTracker()
    /// The pending send, so a burst of cards leaving the screen becomes one
    /// request rather than one each.
    private var impressionFlush: Task<Void, Never>?

    /// A For You card is mostly on screen.
    func impressionShown(_ postID: Int) {
        impressions.shown(postID)
    }

    /// It is not any more: one viewing, queued.
    func impressionHidden(_ postID: Int) {
        impressions.hidden(postID)
        if impressions.pending.count >= ImpressionTracker.maxBatch {
            Task { await flushImpressions() }
        } else if impressions.hasPending {
            scheduleImpressionFlush()
        }
    }

    /// How far into a post's clip playback got, and whether it finished.
    func noteWatched(postID: Int, milliseconds: Int, completed: Bool) {
        impressions.watched(postID, milliseconds: milliseconds, completed: completed)
    }

    /// Closes every open viewing and sends everything: the feed is leaving
    /// the screen, or the app is going to the background.
    func finishImpressions() async {
        impressions.closeAll()
        await flushImpressions()
    }

    /// Sends what is queued, now.
    func flushImpressions() async {
        impressionFlush?.cancel()
        impressionFlush = nil
        await sendImpressions()
    }

    private func scheduleImpressionFlush() {
        guard impressionFlush == nil else { return }
        impressionFlush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            self.impressionFlush = nil
            await self.sendImpressions()
        }
    }

    private func sendImpressions() async {
        guard let repository else {
            impressions.reset()
            return
        }
        while true {
            let batch = impressions.nextBatch()
            guard !batch.isEmpty else { return }
            // Dropped on failure rather than retried: these are signals for
            // ranking, and an old batch sent later would only describe a
            // session that is over.
            try? await repository.recordImpressions(batch)
        }
    }

    // MARK: - Tuning For You

    /// What For You has picked up and what the reader chose. Nil until the
    /// tuning sheet first asks.
    private(set) var forYouPreferences: ForYouPreferences?
    private(set) var isSavingForYouPreferences = false
    /// Said inside the sheet rather than on the feed, which the sheet covers.
    private(set) var forYouPreferencesError: String?
    /// Set when a choice was saved, so the feed ranks again once the sheet
    /// has closed rather than leaving the old page under it.
    private(set) var forYouNeedsReranking = false

    func loadForYouPreferences() async {
        guard let repository else { return }
        let generation = connectionGeneration
        forYouPreferencesError = nil
        do {
            let loaded = try await repository.forYouPreferences()
            guard connectionGeneration == generation else { return }
            forYouPreferences = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            forYouPreferencesError = error.userFacingMessage
        }
    }

    func setPersonalized(_ personalized: Bool) async {
        await saveForYouPreferences { repository in
            try await repository.updateForYouPreferences(personalized: personalized)
        }
    }

    /// Hides a topic or shows it again. The whole list is sent, as the
    /// server wants it. Hiding an added interest takes it off the added
    /// list in the same change: a topic is one or the other, never both.
    func setTopic(_ topic: String, hidden: Bool) async {
        guard let current = forYouPreferences else { return }
        var topics = current.hiddenTopics.filter { $0 != topic }
        if hidden { topics.append(topic) }
        let added: [String]? = hidden && current.isAdded(topic)
            ? current.addedTopics.filter { $0 != topic }
            : nil
        await saveForYouPreferences { repository in
            try await repository.updateForYouPreferences(hiddenTopics: topics, addedTopics: added)
        }
    }

    /// Adds an interest of the reader's own, or takes it off. Adding a
    /// hidden topic shows it again in the same change.
    func setInterest(_ topic: String, added: Bool) async {
        guard let current = forYouPreferences else { return }
        var topics = current.addedTopics.filter { $0 != topic }
        if added { topics.append(topic) }
        let hidden: [String]? = added && current.isHidden(topic)
            ? current.hiddenTopics.filter { $0 != topic }
            : nil
        await saveForYouPreferences { repository in
            try await repository.updateForYouPreferences(hiddenTopics: hidden, addedTopics: topics)
        }
    }

    /// Starts For You fresh. Returns whether it worked, for the sheet to say.
    @discardableResult
    func startForYouFresh() async -> Bool {
        await saveForYouPreferences { repository in
            try await repository.startForYouFresh()
        }
    }

    @discardableResult
    private func saveForYouPreferences(
        _ change: (SocialAPIRepository) async throws -> ForYouPreferences
    ) async -> Bool {
        guard let repository, !isSavingForYouPreferences else { return false }
        let generation = connectionGeneration
        isSavingForYouPreferences = true
        forYouPreferencesError = nil
        defer { if connectionGeneration == generation { isSavingForYouPreferences = false } }
        do {
            let saved = try await change(repository)
            guard connectionGeneration == generation else { return false }
            forYouPreferences = saved
            forYouNeedsReranking = true
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            forYouPreferencesError = error.userFacingMessage
            return false
        }
    }

    // MARK: - People to follow

    /// Who the server suggests, each with why. Shown on Discover.
    private(set) var suggestedPeople: [SuggestedPerson] = []
    private(set) var hasLoadedSuggestions = false
    /// People dismissed here, drawn as a line with an undo.
    private(set) var dismissedSuggestionIDs: Set<Int> = []

    func loadSuggestedPeople() async {
        guard let repository else { return }
        let generation = connectionGeneration
        // Quietly. Suggestions are a bonus on top of Discover, and a failure
        // to fetch them is not worth a message across the posts below.
        guard let loaded = try? await repository.suggestedPeople(limit: 8),
              connectionGeneration == generation
        else { return }
        suggestedPeople = loaded
        dismissedSuggestionIDs = []
        hasLoadedSuggestions = true
    }

    func setSuggestionDismissed(_ dismissed: Bool, person: SuggestedPerson) async {
        guard let repository else { return }
        let generation = connectionGeneration
        if dismissed {
            dismissedSuggestionIDs.insert(person.id)
        } else {
            dismissedSuggestionIDs.remove(person.id)
        }
        do {
            try await repository.setSuggestionDismissed(dismissed, userID: person.id)
        } catch {
            guard connectionGeneration == generation else { return }
            if dismissed {
                dismissedSuggestionIDs.remove(person.id)
            } else {
                dismissedSuggestionIDs.insert(person.id)
            }
            showFailure(error)
        }
    }

    // MARK: - Discover

    /// Posts by people the reader does **not** follow. Kept apart from `feed`
    /// because they answer different questions and a reader switching tabs
    /// should not have to wait for the other one to reload.
    ///
    /// Narrowed by the server rather than here — see
    /// `allPosts(matching:fromFollowing:limitPages:)` for why a capped list
    /// cannot be filtered after the fact.
    private(set) var discoverPosts: [FeedPost] = []
    private(set) var isLoadingDiscover = false

    func loadDiscover() async {
        guard let repository, !isLoadingDiscover else { return }
        let generation = connectionGeneration
        let readRevision = publications.revision
        isLoadingDiscover = true
        defer { if connectionGeneration == generation { isLoadingDiscover = false } }

        do {
            let loaded = try await repository.allPosts(fromFollowing: false)
            guard connectionGeneration == generation else { return }
            discoverPosts = reconcilePublicPage(loaded, readRevision: readRevision, prependOwn: false)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - Search

    /// What the server was last asked for. Empty means the tab is showing
    /// Discover itself rather than results.
    private(set) var searchQuery = ""
    private(set) var searchedPeople: [PostAuthor] = []
    private(set) var searchedPosts: [FeedPost] = []
    private(set) var isSearching = false
    private(set) var searchErrorMessage: String?
    private var searchRequestID = UUID()

    var isShowingSearchResults: Bool { !searchQuery.isEmpty }

    /// Whether a finished search found nothing, as opposed to not having run.
    ///
    /// Separate from "both lists are empty", which is also true before the
    /// first keystroke and while the first one is in flight. Drawing "no
    /// results" in either of those says the search failed when it has not yet
    /// been asked.
    var searchFoundNothing: Bool {
        isShowingSearchResults
            && !isSearching
            && searchErrorMessage == nil
            && searchedPeople.isEmpty
            && searchedPosts.isEmpty
    }

    /// Ask the server who and what matches.
    ///
    /// Both halves are awaited together rather than separately: they are one
    /// answer to one question, and letting them land independently draws a
    /// list of people over an empty set of posts for however long the slower
    /// request takes.
    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repository, !trimmed.isEmpty else {
            clearSearch()
            return
        }

        let generation = connectionGeneration
        let requestID = UUID()
        searchRequestID = requestID
        let readRevision = publications.revision
        searchQuery = trimmed
        isSearching = true
        searchErrorMessage = nil
        searchedPeople = []
        searchedPosts = []
        // Query text alone is not a fence: A → B → A can finish out of order.
        defer {
            if connectionGeneration == generation, searchRequestID == requestID {
                isSearching = false
            }
        }

        do {
            async let people = repository.people(matching: trimmed)
            // Fewer pages than Discover pulls. Somebody searching is looking
            // for one thing, and reading five pages to show the first few
            // matches spends the request budget on results nobody scrolls to.
            async let posts = repository.allPosts(matching: trimmed, limitPages: 2)
            let found = try await (people, posts)
            guard connectionGeneration == generation, searchRequestID == requestID, !Task.isCancelled else { return }
            searchedPeople = found.0.filter { !locallyBlockedAuthorIDs.contains($0.id) }
            searchedPosts = reconcileAuthorVisiblePage(found.1, readRevision: readRevision)
        } catch {
            guard connectionGeneration == generation, searchRequestID == requestID,
                  !Task.isCancelled, !error.isCancellation else { return }
            searchErrorMessage = error.userFacingMessage
        }
    }

    func clearSearch() {
        searchRequestID = UUID()
        searchQuery = ""
        searchErrorMessage = nil
        searchedPeople = []
        searchedPosts = []
        isSearching = false
    }

    // MARK: - One person's posts

    /// Posts by author, for a profile page. Held here rather than in the
    /// profile store so a like made on a profile is the same like the feed
    /// shows, and the counts cannot drift apart.
    private(set) var authorPosts: [Int: [FeedPost]] = [:]
    private(set) var loadingPostsFor: Set<Int> = []

    func posts(byAuthor authorID: Int) -> [FeedPost] {
        authorPosts[authorID] ?? []
    }

    func isLoadingPosts(byAuthor authorID: Int) -> Bool {
        loadingPostsFor.contains(authorID)
    }

    func loadPosts(byAuthor authorID: Int) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let readRevision = publications.revision
        loadingPostsFor.insert(authorID)
        defer {
            if connectionGeneration == generation {
                loadingPostsFor.remove(authorID)
            }
        }

        do {
            let loaded = try await repository.posts(byAuthor: authorID)
            guard connectionGeneration == generation else { return }
            for post in loaded { observePublication(post, readRevision: readRevision) }
            synchronizePublications()
            authorPosts[authorID] = publications.authorPage(loaded, matches: { $0.author.id == authorID })
                .filter(canAppearInAuthorVisibleSurface)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - Taking a workout for yourself

    /// What the last save produced, for a message the reader can dismiss.
    var lastSavedWorkout: SavedWorkoutOutcome?
    var lastSavedMeal: SavedMealOutcome?

    /// Called after a post's workout or meal has been copied into the
    /// reader's own.
    ///
    /// The copy lands in a list this store does not hold: workouts belong to
    /// the workout store, saved meals to the food store. Neither was told,
    /// so a workout saved from a post was on the server and absent from
    /// Saved workouts until the app was next launched -- which reads as the
    /// save having silently failed.
    ///
    /// Says what changed and lets whoever owns the list go and read it,
    /// rather than reaching across into another store. Same shape as
    /// CycleStore.onCalendarChanged.
    var onSavedWorkoutsChanged: (@MainActor () async -> Void)?
    var onSavedMealsChanged: (@MainActor () async -> Void)?
    /// What to say after reporting or blocking. Cleared on a tap, like the
    /// save notices beside it.
    var lastModerationMessage: String?
    /// Everyone this reader has blocked, for the screen that lifts them.
    private(set) var blockedPeople: [BlockedPerson] = []
    private(set) var isLoadingBlocks = false
    private var savingMealFor: Set<Int> = []
    private(set) var savingWorkoutFor: Set<Int> = []

    func isSavingWorkout(from postID: Int) -> Bool {
        savingWorkoutFor.contains(postID)
    }

    func isSavingMeal(from postID: Int) -> Bool {
        savingMealFor.contains(postID)
    }

    /// Copies a posted meal into the reader's own saved meals.
    ///
    /// Not optimistic and not silent, for the same reason as the workout: the
    /// name it lands under is not always the one on the post, and only the
    /// server knows which.
    func saveMeal(from post: FeedPost) async {
        guard let repository, !savingMealFor.contains(post.id) else { return }
        let generation = connectionGeneration
        savingMealFor.insert(post.id)
        defer {
            if connectionGeneration == generation {
                savingMealFor.remove(post.id)
            }
        }

        do {
            let outcome = try await repository.saveMeal(fromPost: post.id)
            guard connectionGeneration == generation else { return }
            lastSavedWorkout = nil
            lastSavedMeal = outcome
            apply(to: post.id) { $0.viewerHasSaved = true }
            await onSavedMealsChanged?()
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// Reports a post.
    ///
    /// Says nearly the same thing whether or not it had already been reported:
    /// someone who pressed it twice wants to know it worked, not to be told
    /// they were early.
    func report(
        _ post: FeedPost,
        reason: PostReportReason,
        detail: String
    ) async -> Bool {
        guard let repository else { return false }
        let generation = connectionGeneration
        do {
            let already = try await repository.report(
                postID: post.id,
                reason: reason,
                detail: detail
            )
            guard connectionGeneration == generation else { return false }
            lastModerationMessage = already
                ? String(localized: "A report for this reason has already been submitted.", bundle: .app, locale: .app)
                : String(localized: "Report received. Thank you for helping keep Rytivo safe.", bundle: .app, locale: .app)
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            showFailure(error)
            return false
        }
    }

    /// Blocks somebody, and takes their posts off the screen on the spot.
    ///
    /// The server drops the follows. Dropping what is already loaded is what
    /// stops the person just blocked sitting there until the next refresh.
    func block(_ author: PostAuthor) async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            try await repository.block(userID: author.id)
            guard connectionGeneration == generation else { return }
            locallyBlockedAuthorIDs.insert(author.id)
            feed.removeAll { $0.displayed.author.id == author.id }
            forYou.removeAll { $0.displayed.author.id == author.id }
            discoverPosts.removeAll { $0.displayed.author.id == author.id }
            suggestedPeople.removeAll { $0.id == author.id }
            // Search results too, and for the same reason. Blocking somebody
            // found by searching for them leaves their row directly under the
            // box that found it, and the server will not return them again —
            // so without this the only thing still showing them is the screen
            // the block was made from.
            searchedPeople.removeAll { $0.id == author.id }
            searchedPosts.removeAll { $0.displayed.author.id == author.id }
            lastModerationMessage =
                String(localized: "Blocked \(author.displayName). You will not see each other's posts.", bundle: .app, locale: .app)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    func reportComment(_ comment: PostComment, reason: PostReportReason, detail: String) async -> Bool {
        guard let repository else { return false }
        let generation = connectionGeneration
        do {
            try await repository.reportComment(commentID: comment.id, reason: reason, detail: detail)
            guard connectionGeneration == generation else { return false }
            lastModerationMessage = String(localized: "Thanks. Your comment report was sent to our moderators.", bundle: .app, locale: .app)
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            showFailure(error)
            return false
        }
    }

    func loadBlocks() async {
        guard let repository else { return }
        let generation = connectionGeneration
        isLoadingBlocks = true
        defer { if connectionGeneration == generation { isLoadingBlocks = false } }
        do {
            let loaded = try await repository.blocks()
            guard connectionGeneration == generation else { return }
            blockedPeople = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// Lifts a block. The feed is not refilled here: what they posted while
    /// blocked is not news, and it arrives on the next refresh anyway.
    func unblock(_ blocked: BlockedPerson) async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            try await repository.unblock(blockID: blocked.id)
            guard connectionGeneration == generation else { return }
            locallyBlockedAuthorIDs.remove(blocked.person.id)
            blockedPeople.removeAll { $0.id == blocked.id }
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// Copies a posted workout into the reader's own workouts.
    ///
    /// Not optimistic and not silent: the name it lands under is not always
    /// the one on the post, so there is something to say afterwards that only
    /// the server knows.
    func saveWorkout(from post: FeedPost) async {
        guard let repository, !savingWorkoutFor.contains(post.id) else { return }
        let generation = connectionGeneration
        savingWorkoutFor.insert(post.id)
        defer {
            if connectionGeneration == generation {
                savingWorkoutFor.remove(post.id)
            }
        }

        do {
            let outcome = try await repository.saveWorkout(fromPost: post.id)
            guard connectionGeneration == generation else { return }
            lastSavedMeal = nil
            lastSavedWorkout = outcome
            // The card says Saved without waiting for the feed to be read
            // again. The server already knows; this is the same answer,
            // applied where it is being looked at.
            apply(to: post.id) { $0.viewerHasSaved = true }
            await onSavedWorkoutsChanged?()
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - Comments

    /// Threads by post, kept so returning to a post shows what was there while
    /// the fresh copy loads.
    private(set) var comments: [Int: [PostComment]] = [:]
    private var locallyBlockedAuthorIDs: Set<Int> = []
    private(set) var loadingCommentsFor: Set<Int> = []
    private(set) var isSendingComment = false

    func comments(for postID: Int) -> [PostComment] {
        (comments[postID] ?? []).filter { !locallyBlockedAuthorIDs.contains($0.author.id) }.map { comment in
            var filtered = comment
            filtered.replies.removeAll { locallyBlockedAuthorIDs.contains($0.author.id) }
            return filtered
        }
    }

    func isLoadingComments(for postID: Int) -> Bool {
        loadingCommentsFor.contains(postID)
    }

    func loadComments(for postID: Int) async {
        guard let repository else { return }
        let generation = connectionGeneration
        loadingCommentsFor.insert(postID)
        defer {
            if connectionGeneration == generation {
                loadingCommentsFor.remove(postID)
            }
        }

        do {
            let loaded = try await repository.comments(forPost: postID)
            guard connectionGeneration == generation else { return }
            comments[postID] = loaded
            // The badge on the card and the list on the page must agree.
            apply(to: postID) { $0.commentCount = loaded.reduce(0) { $0 + $1.totalCount } }
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// Adds a comment and reads the thread back.
    ///
    /// Read back rather than spliced in: where a reply belongs depends on what
    /// else has been said, and the count on the card has to match.
    func addComment(_ draft: CommentDraft, toPost postID: Int) async {
        guard let repository, !isSendingComment, draft.isSendable else { return }
        let generation = connectionGeneration
        isSendingComment = true
        defer { if connectionGeneration == generation { isSendingComment = false } }

        do {
            try await repository.addComment(
                draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
                toPost: postID,
                replyingTo: draft.replyingTo?.id
            )
            guard connectionGeneration == generation else { return }
            await loadComments(for: postID)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    func deleteComment(_ comment: PostComment) async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            try await repository.deleteComment(comment.id)
            guard connectionGeneration == generation else { return }
            await loadComments(for: comment.postID)
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    // MARK: - Keeping the feed in step

    func consumePublicationReceipt(id: UUID) {
        guard publicationReceipt?.id == id else { return }
        publicationReceipt = nil
    }

    private func isSharedPublication(_ post: FeedPost) -> Bool {
        SocialPublicationEligibility.shared(approved: post.isPublished, publishedAt: post.publishedAt,
                                            isPrivate: post.visibility == .privateToMe, videoStatus: post.video?.status)
    }

    private func canAppearInSharedFeed(_ post: FeedPost) -> Bool {
        isSharedPublication(post)
            && !locallyBlockedAuthorIDs.contains(post.author.id)
            && !locallyBlockedAuthorIDs.contains(post.displayed.author.id)
            && !publications.isUnavailable(post.id)
            && !(post.repostOf.map { publications.isUnavailable($0.id) } ?? false)
    }

    private func canAppearInAuthorVisibleSurface(_ post: FeedPost) -> Bool {
        !locallyBlockedAuthorIDs.contains(post.author.id)
            && !locallyBlockedAuthorIDs.contains(post.displayed.author.id)
            && !publications.isDeleted(post.id)
            && !(post.repostOf.map { publications.isUnavailable($0.id) } ?? false)
            && (post.viewerIsAuthor || canAppearInSharedFeed(post))
    }

    private func ownRecommendation(_ posts: [FeedPost]) -> [FeedPost] {
        let reasons = Dictionary(forYou.compactMap { post in
            post.recommendation.map { (post.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        return posts.map { post in
            var post = post
            if post.recommendation == nil { post.recommendation = reasons[post.id] }
            if post.viewerIsAuthor, post.recommendation == nil {
                post.recommendation = .init(reason: "own", label: String(localized: "Your post", bundle: .app, locale: .app))
            }
            return post
        }
    }

    private func reconcilePublicPage(_ posts: [FeedPost], readRevision: UInt64, prependOwn: Bool) -> [FeedPost] {
        for post in posts { observePublication(post, readRevision: readRevision) }
        synchronizePublications()
        return publications.publicPage(posts, prependOwn: prependOwn).filter(canAppearInSharedFeed)
    }

    private func reconcileAuthorVisiblePage(_ posts: [FeedPost], readRevision: UInt64) -> [FeedPost] {
        for post in posts { observePublication(post, readRevision: readRevision) }
        synchronizePublications()
        return publications.resolvedPage(posts).filter(canAppearInAuthorVisibleSurface)
    }

    @discardableResult
    private func observePublication(_ post: FeedPost, readRevision: UInt64? = nil) -> Bool {
        var snapshot = post
        snapshot.recommendation = nil // Ranking metadata belongs to its destination feed.
        let observation = publications.observe(
            snapshot, isOwn: post.viewerIsAuthor, eligible: isSharedPublication(post),
            expiresAt: (post.publishedAt ?? post.createdAt).addingTimeInterval(24 * 60 * 60),
            readRevision: readRevision
        )
        guard observation.accepted else { return false }
        if lastPosted?.id == post.id {
            lastPosted = post
            lastModerationMessage = post.publicationMessage
        }
        if !canAppearInSharedFeed(post), publicationReceipt?.postID == post.id { publicationReceipt = nil }
        if observation.announcePublication, canAppearInSharedFeed(post) {
            publicationReceipt = .init(postID: post.id)
        }
        return true
    }

    private func synchronizePublications() {
        feed = publications.publicPage(feed, prependOwn: true).filter(canAppearInSharedFeed)
        forYou = ownRecommendation(publications.publicPage(forYou, prependOwn: true).filter(canAppearInSharedFeed))
        discoverPosts = publications.publicPage(discoverPosts, prependOwn: false).filter(canAppearInSharedFeed)
        searchedPosts = publications.resolvedPage(searchedPosts).filter(canAppearInAuthorVisibleSurface)
        let opened = publications.resolvedPage(Array(openedPosts.values)).filter(canAppearInAuthorVisibleSurface)
        openedPosts = Dictionary(uniqueKeysWithValues: opened.map { ($0.id, $0) })
        for authorID in Array(authorPosts.keys) {
            authorPosts[authorID] = publications.resolvedPage(authorPosts[authorID] ?? [])
                .filter(canAppearInAuthorVisibleSurface)
        }
    }

    /// Status reads are bounded and occur only during user/foreground refresh,
    /// not on a timer. Approval can arrive while no detail/video view is open.
    private func refreshPendingPublications(using repository: SocialAPIRepository, generation: UUID) async {
        guard !isRefreshingPublicationStatuses else { return }
        isRefreshingPublicationStatuses = true
        defer { if connectionGeneration == generation { isRefreshingPublicationStatuses = false } }
        let pending = publications.pendingSubmissions
            .filter {
                $0.viewerIsAuthor && SocialPublicationEligibility.shouldRefresh(
                    moderationStatus: $0.moderationStatus, publishedAt: $0.publishedAt,
                    isPrivate: $0.visibility == .privateToMe, videoStatus: $0.video?.status,
                    videoProcessingState: $0.video?.processingState)
            }.prefix(5)
        for post in pending {
            guard connectionGeneration == generation, !Task.isCancelled else { return }
            publications.markStatusChecked(id: post.id)
            let readRevision = publications.revision
            do {
                let updated = try await repository.post(withID: post.id)
                guard connectionGeneration == generation, !Task.isCancelled else { return }
                replace(updated, readRevision: readRevision)
            } catch {
                // Keep the last confirmed private status and let the feed
                // refresh proceed. A later refresh can retry the status read.
                guard connectionGeneration == generation, !Task.isCancelled else { return }
            }
        }
    }

    /// Called when Social returns to the foreground or the composer closes.
    /// It rechecks only known pending submissions and does not start a timer.
    func refreshPublicationStatuses() async {
        guard let repository else { return }
        await refreshPendingPublications(using: repository, generation: connectionGeneration)
    }

    private func removePost(id: Int) {
        publications.remove(id: id)
        let removes: (FeedPost) -> Bool = { $0.id == id || $0.repostOf?.id == id }
        feed.removeAll(where: removes)
        forYou.removeAll(where: removes)
        discoverPosts.removeAll(where: removes)
        searchedPosts.removeAll(where: removes)
        openedPosts = openedPosts.filter { !removes($0.value) }
        for authorID in Array(authorPosts.keys) { authorPosts[authorID]?.removeAll(where: removes) }
        comments[id] = nil
        dismissals[id] = nil
        wantedPostIDs.remove(id)
        if lastPosted?.id == id { lastPosted = nil; lastModerationMessage = nil }
        if publicationReceipt?.postID == id { publicationReceipt = nil }
    }

    private func apply(to postID: Int, _ change: (inout FeedPost) -> Void) {
        if let index = feed.firstIndex(where: { $0.id == postID }) {
            change(&feed[index])
        }
        // For You holds its own copy too, for the same reason Discover does.
        if let index = forYou.firstIndex(where: { $0.id == postID }) {
            change(&forYou[index])
        }
        // Discover holds its own list, so a card looked at there is a
        // different copy from the one in the feed. Missing it meant liking,
        // reposting or saving from that tab changed nothing on screen: the
        // server was told and the card carried on saying Save.
        if let index = discoverPosts.firstIndex(where: { $0.id == postID }) {
            change(&discoverPosts[index])
        }
        if let index = searchedPosts.firstIndex(where: { $0.id == postID }) {
            change(&searchedPosts[index])
        }
        // A post opened from outside the feed is held here instead, and a like
        // made on its page has to show there too.
        if var opened = openedPosts[postID] {
            change(&opened)
            openedPosts[postID] = opened
        }
        // And on a profile, which is a third place the same post is drawn.
        for author in authorPosts.keys {
            guard let index = authorPosts[author]?.firstIndex(where: { $0.id == postID })
            else { continue }
            change(&authorPosts[author]![index])
        }
        publications.mutate(where: { $0.id == postID }, change)
    }

    private func applyToAuthor(_ authorID: Int, _ change: (inout FeedPost) -> Void) {
        for index in feed.indices where feed[index].author.id == authorID {
            change(&feed[index])
        }
        for index in forYou.indices where forYou[index].author.id == authorID {
            change(&forYou[index])
        }
        for index in discoverPosts.indices
        where discoverPosts[index].author.id == authorID {
            change(&discoverPosts[index])
        }
        for index in searchedPosts.indices where searchedPosts[index].author.id == authorID {
            change(&searchedPosts[index])
        }
        for id in openedPosts.keys where openedPosts[id]?.author.id == authorID {
            guard var post = openedPosts[id] else { continue }
            change(&post)
            openedPosts[id] = post
        }
        for author in authorPosts.keys {
            guard var posts = authorPosts[author] else { continue }
            for index in posts.indices where posts[index].author.id == authorID {
                change(&posts[index])
            }
            authorPosts[author] = posts
        }
        publications.mutate(where: { $0.author.id == authorID }, change)
    }

    /// Puts a server copy over every card showing that post — the post itself,
    /// and any repost of it, which carries the same figures underneath.
    @discardableResult
    private func replace(_ post: FeedPost, readRevision: UInt64? = nil) -> Bool {
        guard observePublication(post, readRevision: readRevision) else { return false }
        if !canAppearInSharedFeed(post) {
            feed.removeAll { $0.id == post.id || $0.repostOf?.id == post.id }
            forYou.removeAll { $0.id == post.id || $0.repostOf?.id == post.id }
            discoverPosts.removeAll { $0.id == post.id || $0.repostOf?.id == post.id }
            searchedPosts.removeAll { $0.id == post.id || $0.repostOf?.id == post.id }
            if publicationReceipt?.postID == post.id { publicationReceipt = nil }
            if !post.viewerIsAuthor {
                openedPosts[post.id] = nil
                for author in Array(authorPosts.keys) { authorPosts[author]?.removeAll { $0.id == post.id } }
            }
        }
        for index in feed.indices where feed[index].id == post.id {
            feed[index] = post
        }
        // Keeping the reason it was recommended for: the copy the server sent
        // back answers a like or a save, and knows nothing about For You.
        for index in forYou.indices where forYou[index].id == post.id {
            let recommendation = forYou[index].recommendation
            forYou[index] = post
            forYou[index].recommendation = recommendation
        }
        for index in discoverPosts.indices where discoverPosts[index].id == post.id {
            discoverPosts[index] = post
        }
        for index in searchedPosts.indices where searchedPosts[index].id == post.id {
            searchedPosts[index] = post
        }
        if openedPosts[post.id] != nil {
            openedPosts[post.id] = post
        }
        for author in authorPosts.keys {
            guard let index = authorPosts[author]?.firstIndex(where: { $0.id == post.id })
            else { continue }
            authorPosts[author]![index] = post
        }
        for index in feed.indices where feed[index].repostOf?.id == post.id {
            feed[index].repostOf?.video = post.video
            feed[index].likeCount = post.likeCount
            feed[index].commentCount = post.commentCount
            feed[index].repostCount = post.repostCount
        }
        for index in discoverPosts.indices
        where discoverPosts[index].repostOf?.id == post.id {
            discoverPosts[index].repostOf?.video = post.video
            discoverPosts[index].likeCount = post.likeCount
            discoverPosts[index].commentCount = post.commentCount
            discoverPosts[index].repostCount = post.repostCount
        }
        for index in forYou.indices where forYou[index].repostOf?.id == post.id {
            forYou[index].repostOf?.video = post.video
            forYou[index].likeCount = post.likeCount
            forYou[index].commentCount = post.commentCount
            forYou[index].repostCount = post.repostCount
        }
        for index in searchedPosts.indices where searchedPosts[index].repostOf?.id == post.id {
            searchedPosts[index].repostOf?.video = post.video
            searchedPosts[index].likeCount = post.likeCount
            searchedPosts[index].commentCount = post.commentCount
            searchedPosts[index].repostCount = post.repostCount
        }
        publications.mutate(where: { $0.repostOf?.id == post.id }) {
            $0.repostOf?.video = post.video
            $0.likeCount = post.likeCount
            $0.commentCount = post.commentCount
            $0.repostCount = post.repostCount
        }
        synchronizePublications()
        if post.viewerIsAuthor {
            authorPosts[post.author.id] = publications.authorPage(authorPosts[post.author.id] ?? [],
                                                                matches: { $0.author.id == post.author.id })
        }
        return true
    }

    /// Posts opened from somewhere the feed does not hold — a profile, a
    /// notification, a card that has since paged out.
    private(set) var openedPosts: [Int: FeedPost] = [:]

    /// The post as it currently stands, so a page opened from a card follows
    /// it as counts change rather than freezing a copy.
    func post(withID id: Int) -> FeedPost? {
        feed.first { $0.id == id }
            ?? forYou.first { $0.id == id }
            ?? discoverPosts.first { $0.id == id }
            ?? openedPosts[id]
    }

    /// Fetches a post the feed does not have. Does nothing when it does.
    func loadPost(id: Int) async {
        guard let repository, post(withID: id) == nil else { return }
        let generation = connectionGeneration
        let readRevision = publications.revision
        do {
            let loaded = try await repository.post(withID: id)
            guard connectionGeneration == generation else { return }
            guard replace(loaded, readRevision: readRevision), loaded.isPublished || loaded.viewerIsAuthor,
                  !locallyBlockedAuthorIDs.contains(loaded.displayed.author.id) else { return }
            openedPosts[id] = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            showFailure(error)
        }
    }

    /// Dismisses whatever the last failure was.
    ///
    /// Clears the retry flag with it: leaving that set would put a "Try again"
    /// button in front of the *next* failure, whatever it turned out to be.
    func clearError() {
        errorMessage = nil
        errorIsRetryable = false
    }
}

#if DEBUG
extension SocialStore {
    /// A feed with something to like, something already liked, a repost, and a
    /// thread under one of them. The simulator has no second account, so this
    /// is the only way to see the states a real feed would show.
    static var preview: SocialStore {
        let store = SocialStore()
        let aaron = PostAuthor(
            id: 1, username: "aaron.pio", firstName: "Aaron",
            lastName: "Pio", photoURL: nil
        )
        let mara = PostAuthor(
            id: 2, username: "mara.k", firstName: "Mara",
            lastName: "Kelly", photoURL: nil
        )
        let push = PostWorkoutSnapshot(
            title: "Push Day",
            workoutType: "lifting",
            performedAt: Date().addingTimeInterval(-60 * 60 * 30),
            durationSeconds: 3_420,
            exerciseCount: 5,
            totalSetCount: 18,
            totalVolumeKg: 4_820,
            routeDistanceKm: nil,
            exercises: [
                PostExerciseLine(id: 1, name: "Bench Press", setCount: 4, topSetWeightKg: 100, topSetReps: 5),
                PostExerciseLine(id: 2, name: "Overhead Press", setCount: 4, topSetWeightKg: 60, topSetReps: 8),
                PostExerciseLine(id: 3, name: "Incline Dumbbell", setCount: 3, topSetWeightKg: 34, topSetReps: 10),
            ]
        )
        /// The same shape of session posted with the load held back: sets and
        /// reps survive, the weights and the volume do not.
        let quiet = PostWorkoutSnapshot(
            title: "Quiet Day",
            workoutType: "lifting",
            performedAt: Date().addingTimeInterval(-60 * 60 * 50),
            durationSeconds: 3_000,
            exerciseCount: 2,
            totalSetCount: 8,
            totalVolumeKg: nil,
            routeDistanceKm: nil,
            exercises: [
                PostExerciseLine(id: 4, name: "Bench Press", setCount: 4, topSetWeightKg: nil, topSetReps: 5),
                PostExerciseLine(id: 5, name: "Overhead Press", setCount: 4, topSetWeightKg: nil, topSetReps: 8),
            ]
        )
        let run = PostWorkoutSnapshot(
            title: "Morning Run",
            workoutType: "running",
            performedAt: Date().addingTimeInterval(-60 * 60 * 5),
            durationSeconds: 2_640,
            exerciseCount: 0,
            totalSetCount: 0,
            totalVolumeKg: nil,
            routeDistanceKm: 8.2,
            exercises: []
        )

        let original = FeedPost(
            id: 1, author: aaron, kind: .workout,
            caption: "Everything moved well today.",
            imageURL: nil, visibility: .publicToAll,
            createdAt: Date().addingTimeInterval(-60 * 60 * 30),
            viewerFollowsAuthor: true, sourceID: nil,
            workout: push, meal: nil, planner: nil,
            likeCount: 12, commentCount: 3, repostCount: 2,
            viewerHasLiked: true, viewerHasReposted: false,
            // Somebody else's, so it offers its workout.
            showsWeights: true, viewerIsAuthor: false, repostOf: nil
        )
        // A meal, so the meal card has any preview cover at all: it is a real
        // post kind, and until now it could only be looked at with a signed-in
        // account and a day's food behind it. Two items, because one would not
        // show what a list of them reads like in the title or underneath it.
        let lunch = PostMealSnapshot(
            name: "Meal 1",
            date: "2026-08-24",
            totalCalories: 800,
            totalProteinGrams: 50,
            totalCarbohydrateGrams: 120,
            totalFatGrams: 30,
            entries: [
                PostFoodLine(id: 1, name: "Chicken Bowl", servings: 1, totalCalories: 620),
                PostFoodLine(id: 2, name: "Greek Yoghurt", servings: 1, totalCalories: 180),
            ]
        )

        store.feed = [
            original,
            FeedPost(
                id: 5, author: aaron, kind: .meal,
                caption: "this my food",
                imageURL: nil, visibility: .publicToAll,
                createdAt: Date().addingTimeInterval(-60 * 60 * 26),
                viewerFollowsAuthor: true, sourceID: nil,
                workout: nil, meal: lunch, planner: nil,
                likeCount: 4, commentCount: 0, repostCount: 0,
                viewerHasLiked: false, viewerHasReposted: false, repostOf: nil
            ),
            // Weights held back. The rows read "4 × 5" with no load, there is
            // no "kg lifted" figure, and the workout is still worth saving.
            FeedPost(
                id: 4, author: mara, kind: .workout,
                caption: "Kept the numbers to myself today.",
                imageURL: nil, visibility: .publicToAll,
                createdAt: Date().addingTimeInterval(-60 * 60 * 50),
                viewerFollowsAuthor: true, sourceID: nil,
                workout: quiet, meal: nil, planner: nil,
                likeCount: 3, commentCount: 0, repostCount: 0,
                viewerHasLiked: false, viewerHasReposted: false,
                showsWeights: false, viewerIsAuthor: false, repostOf: nil
            ),
            FeedPost(
                id: 2, author: mara, kind: .workout, caption: "",
                imageURL: nil, visibility: .publicToAll,
                createdAt: Date().addingTimeInterval(-60 * 60 * 5),
                viewerFollowsAuthor: true, sourceID: nil,
                workout: run, meal: nil, planner: nil,
                likeCount: 0, commentCount: 0, repostCount: 0,
                viewerHasLiked: false, viewerHasReposted: false, repostOf: nil
            ),
            // A repost: Mara passing on Aaron's post. The card must credit
            // Aaron for the training and Mara for passing it on.
            FeedPost(
                id: 3, author: mara, kind: .repost, caption: "",
                imageURL: nil, visibility: .publicToAll,
                createdAt: Date().addingTimeInterval(-60 * 60 * 2),
                viewerFollowsAuthor: true, sourceID: nil,
                workout: nil, meal: nil, planner: nil,
                likeCount: 12, commentCount: 3, repostCount: 2,
                viewerHasLiked: true, viewerHasReposted: true,
                repostOf: RepostedPost(
                    id: 1, author: aaron, kind: .workout,
                    caption: "Everything moved well today.",
                    imageURL: nil,
                    createdAt: Date().addingTimeInterval(-60 * 60 * 30),
                    workout: push, meal: nil, planner: nil
                )
            ),
        ]
        store.comments = [
            1: [
                PostComment(
                    id: 10, postID: 1, author: mara, parentID: nil,
                    body: "That volume is up a long way on last week.",
                    replies: [
                        PostComment(
                            id: 11, postID: 1, author: aaron, parentID: 10,
                            body: "Third week of the block — it should be.",
                            replies: [], viewerIsAuthor: true,
                            createdAt: Date().addingTimeInterval(-60 * 40)
                        )
                    ],
                    viewerIsAuthor: false,
                    createdAt: Date().addingTimeInterval(-60 * 90)
                ),
                PostComment(
                    id: 12, postID: 1, author: mara, parentID: nil,
                    body: "What are you finishing on?",
                    replies: [], viewerIsAuthor: false,
                    createdAt: Date().addingTimeInterval(-60 * 20)
                ),
            ]
        ]
        return store
    }
}
#endif
