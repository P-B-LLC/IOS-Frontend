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
    /// Where the next page starts. Nil once the feed has been read to the end.
    private var nextCursor: String?
    private var hasReachedEnd = false

    private(set) var feed: [FeedPost] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isPosting = false
    private(set) var errorMessage: String?
    /// Set when a post goes out, so a screen can say so and move on.
    private(set) var lastPosted: FeedPost?

    var isConnected: Bool { repository != nil }

    init() {}

    // MARK: - The server

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        isLoading = true
        errorMessage = nil
        defer { if connectionGeneration == generation { isLoading = false } }

        do {
            let repository = try SocialAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository

            let page = try await repository.feed()
            guard connectionGeneration == generation else { return }
            feed = page.posts
            nextCursor = page.nextCursor
            hasReachedEnd = page.nextCursor == nil
        } catch {
            guard connectionGeneration == generation else { return }
            repository = nil
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        feed = []
        nextCursor = nil
        hasReachedEnd = false
        isLoading = false
        isLoadingMore = false
        isPosting = false
        errorMessage = nil
        lastPosted = nil
        // One account's threads must never be shown to the next.
        comments = [:]
        openedPosts = [:]
        loadingCommentsFor = []
        isSendingComment = false
    }

    // MARK: - Reading

    func refresh() async {
        guard let repository else { return }
        let generation = connectionGeneration
        errorMessage = nil
        do {
            let page = try await repository.feed()
            guard connectionGeneration == generation else { return }
            feed = page.posts
            nextCursor = page.nextCursor
            hasReachedEnd = page.nextCursor == nil
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
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
        isLoadingMore = true
        defer { if connectionGeneration == generation { isLoadingMore = false } }

        do {
            let page = try await repository.feed(after: cursor)
            guard connectionGeneration == generation else { return }
            // Filtered against what is already held rather than appended
            // blindly: a post written between two page reads shifts the
            // boundary, and the cursor is a position, not a promise.
            let known = Set(feed.map(\.id))
            feed.append(contentsOf: page.posts.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
            hasReachedEnd = page.nextCursor == nil
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
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
        photo: PostPhoto? = nil
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Connect to Repbase before posting."
            return false
        }

        let generation = connectionGeneration
        isPosting = true
        errorMessage = nil
        defer { if connectionGeneration == generation { isPosting = false } }

        do {
            let posted = try await repository.post(
                kind: kind,
                sourceID: sourceID,
                caption: caption,
                visibility: visibility,
                photo: photo
            )
            guard connectionGeneration == generation else { return false }
            // A private post is deliberately kept out of the stream, exactly as
            // the server keeps it out of everyone else's.
            if visibility != .privateToMe {
                feed.insert(posted, at: 0)
            }
            lastPosted = posted
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            errorMessage = error.localizedDescription
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
                feed.removeAll { $0.id == post.id }
            } catch {
                guard connectionGeneration == generation else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Liking and reposting

    /// Turns the like on or off, showing the new state at once and putting it
    /// back if the server refuses.
    ///
    /// Optimistic because a like is the one action where the delay is the
    /// whole experience: a heart that fills a third of a second after the tap
    /// reads as a broken button, and people tap it again.
    func toggleLike(_ post: FeedPost) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let wanted = !post.viewerHasLiked

        apply(to: post.id) {
            $0.viewerHasLiked = wanted
            // Guarded so a stale card cannot take the count below zero.
            $0.likeCount = max(0, $0.likeCount + (wanted ? 1 : -1))
        }

        do {
            let saved = try await repository.setLiked(wanted, postID: post.id)
            guard connectionGeneration == generation else { return }
            // The server's figures replace the guess: other people have been
            // liking it too, and its count is the true one.
            replace(saved)
        } catch {
            guard connectionGeneration == generation else { return }
            apply(to: post.id) {
                $0.viewerHasLiked = !wanted
                $0.likeCount = max(0, $0.likeCount + (wanted ? -1 : 1))
            }
            errorMessage = error.localizedDescription
        }
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
                    feed.removeAll { $0.id == post.id }
                }
            }
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Comments

    /// Threads by post, kept so returning to a post shows what was there while
    /// the fresh copy loads.
    private(set) var comments: [Int: [PostComment]] = [:]
    private(set) var loadingCommentsFor: Set<Int> = []
    private(set) var isSendingComment = false

    func comments(for postID: Int) -> [PostComment] {
        comments[postID] ?? []
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Keeping the feed in step

    private func apply(to postID: Int, _ change: (inout FeedPost) -> Void) {
        if let index = feed.firstIndex(where: { $0.id == postID }) {
            change(&feed[index])
        }
        // A post opened from outside the feed is held here instead, and a like
        // made on its page has to show there too.
        if var opened = openedPosts[postID] {
            change(&opened)
            openedPosts[postID] = opened
        }
    }

    /// Puts a server copy over every card showing that post — the post itself,
    /// and any repost of it, which carries the same figures underneath.
    private func replace(_ post: FeedPost) {
        for index in feed.indices where feed[index].id == post.id {
            feed[index] = post
        }
        if openedPosts[post.id] != nil {
            openedPosts[post.id] = post
        }
        for index in feed.indices where feed[index].repostOf?.id == post.id {
            feed[index].likeCount = post.likeCount
            feed[index].commentCount = post.commentCount
            feed[index].repostCount = post.repostCount
        }
    }

    /// Posts opened from somewhere the feed does not hold — a profile, a
    /// notification, a card that has since paged out.
    private(set) var openedPosts: [Int: FeedPost] = [:]

    /// The post as it currently stands, so a page opened from a card follows
    /// it as counts change rather than freezing a copy.
    func post(withID id: Int) -> FeedPost? {
        feed.first { $0.id == id } ?? openedPosts[id]
    }

    /// Fetches a post the feed does not have. Does nothing when it does.
    func loadPost(id: Int) async {
        guard let repository, post(withID: id) == nil else { return }
        let generation = connectionGeneration
        do {
            let loaded = try await repository.post(withID: id)
            guard connectionGeneration == generation else { return }
            openedPosts[id] = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
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
            exercises: []
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
            viewerHasLiked: true, viewerHasReposted: false, repostOf: nil
        )
        store.feed = [
            original,
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
