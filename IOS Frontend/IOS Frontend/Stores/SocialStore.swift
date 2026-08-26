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
    private(set) var people: [PostAuthor] = []
    private(set) var followersByUser: [Int: [PostAuthor]] = [:]
    private(set) var followingByUser: [Int: [PostAuthor]] = [:]
    private(set) var changingFollowFor: Set<Int> = []

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
            errorMessage = error.userFacingMessage
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
        people = []
        followersByUser = [:]
        followingByUser = [:]
        changingFollowFor = []
        // One account's threads must never be shown to the next.
        comments = [:]
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
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
        }
    }

    func loadPeople() async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            let loaded = try await repository.people()
            guard connectionGeneration == generation else { return }
            people = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
        }
    }

    func setFollowing(_ follows: Bool, user: PostAuthor, viewerID: Int?) async {
        guard let repository, !changingFollowFor.contains(user.id) else { return }
        changingFollowFor.insert(user.id)
        defer { changingFollowFor.remove(user.id) }
        do {
            if follows { try await repository.follow(user.id) }
            else { try await repository.unfollow(user.id) }
            applyToAuthor(user.id) { $0.viewerFollowsAuthor = follows }
            if let viewerID { await loadRelationships(for: viewerID) }
        } catch {
            errorMessage = error.userFacingMessage
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
                showsWeights: showsWeights,
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
            errorMessage = error.userFacingMessage
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
                errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
        }
    }

    // MARK: - Discover

    /// Everyone's posts, not just the people you follow. Kept apart from
    /// `feed` because they answer different questions and a reader switching
    /// tabs should not have to wait for the other one to reload.
    private(set) var discoverPosts: [FeedPost] = []
    private(set) var isLoadingDiscover = false

    func loadDiscover() async {
        guard let repository, !isLoadingDiscover else { return }
        let generation = connectionGeneration
        isLoadingDiscover = true
        defer { if connectionGeneration == generation { isLoadingDiscover = false } }

        do {
            let loaded = try await repository.allPosts()
            guard connectionGeneration == generation else { return }
            discoverPosts = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
        }
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
        loadingPostsFor.insert(authorID)
        defer {
            if connectionGeneration == generation {
                loadingPostsFor.remove(authorID)
            }
        }

        do {
            let loaded = try await repository.posts(byAuthor: authorID)
            guard connectionGeneration == generation else { return }
            authorPosts[authorID] = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
        }
    }

    // MARK: - Taking a workout for yourself

    /// What the last save produced, for a message the reader can dismiss.
    var lastSavedWorkout: SavedWorkoutOutcome?
    var lastSavedMeal: SavedMealOutcome?
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
            lastSavedMeal = outcome
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
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
    ) async {
        guard let repository else { return }
        let generation = connectionGeneration
        do {
            let already = try await repository.report(
                postID: post.id,
                reason: reason,
                detail: detail
            )
            guard connectionGeneration == generation else { return }
            lastModerationMessage = already
                ? "You had already reported this post. We are looking at it."
                : "Thanks. We will take a look at this post."
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
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
            feed.removeAll { $0.displayed.author.id == author.id }
            discoverPosts.removeAll { $0.displayed.author.id == author.id }
            people.removeAll { $0.id == author.id }
            lastModerationMessage =
                "Blocked \(author.displayName). You will not see each other's posts."
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
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
            blockedPeople.removeAll { $0.id == blocked.id }
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
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
            lastSavedWorkout = outcome
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
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
            errorMessage = error.userFacingMessage
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
        // And on a profile, which is a third place the same post is drawn.
        for author in authorPosts.keys {
            guard let index = authorPosts[author]?.firstIndex(where: { $0.id == postID })
            else { continue }
            change(&authorPosts[author]![index])
        }
    }

    private func applyToAuthor(_ authorID: Int, _ change: (inout FeedPost) -> Void) {
        for index in feed.indices where feed[index].author.id == authorID {
            change(&feed[index])
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
        for author in authorPosts.keys {
            guard let index = authorPosts[author]?.firstIndex(where: { $0.id == post.id })
            else { continue }
            authorPosts[author]![index] = post
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
            errorMessage = error.userFacingMessage
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
