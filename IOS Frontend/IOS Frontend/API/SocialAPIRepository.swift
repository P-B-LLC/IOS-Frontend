//
//  SocialAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated feed, posting and following operations.
//

import Foundation
import RepbaseAPI

/// One page of the feed, and where the next one starts.
nonisolated struct FeedPage: Equatable, Sendable {
    var posts: [FeedPost]
    /// The opaque cursor for the following page. Nil at the end of the feed.
    var nextCursor: String?
}

actor SocialAPIRepository {
    private let configuration: APIConfiguration
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        self.configuration = configuration
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    // MARK: - Reading

    /// A page of what the people you follow have posted, newest first.
    ///
    /// Paged by cursor rather than by number because the feed is written to
    /// while it is read: someone posts, everything slides down one, and a
    /// numbered page two would repeat a post page one already showed.
    func feed(after cursor: String? = nil) async throws -> FeedPage {
        let output = try await client.socialFeedList(query: .init(cursor: cursor))
        switch output {
        case .ok(let response):
            let body = try response.body.json
            return FeedPage(
                posts: body.results.map(Self.post(from:)),
                nextCursor: try nextCursor(body.next)
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// One person's posts, already narrowed by the server to what the reader
    /// is allowed to see.
    /// Everyone's posts, newest first — what Discover shows.
    ///
    /// The unfiltered post list, not the feed. The feed is deliberately only
    /// the people you follow; this is the same visibility rules applied to
    /// everybody, so a stranger's public post is here and their private one
    /// is not.
    /// - Parameter fromFollowing: `false` for the people the reader does not
    ///   follow, which is what Discover is; `true` for the ones they do; nil
    ///   for everybody. The split is the server's rather than a filter over a
    ///   page it happened to send, because this list is capped — filtering
    ///   five pages down to the strangers in them would leave a Discover tab
    ///   whose length depended on how much of the page was people you already
    ///   follow.
    func allPosts(
        matching search: String? = nil,
        fromFollowing: Bool? = nil,
        limitPages: Int = 5
    ) async throws -> [FeedPost] {
        let term = Self.searchTerm(search)
        var page: Int?
        var visited: Set<Int> = []
        var values: [FeedPost] = []
        var pagesRead = 0
        repeat {
            let output = try await client.socialPostsList(
                query: .init(fromFollowing: fromFollowing, page: page, search: term)
            )
            let body: Components.Schemas.PaginatedPostList
            switch output {
            case .ok(let response):
                body = try response.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: body.results.map(Self.post(from:)))
            pagesRead += 1
            // Capped. Every post on the server is not a thing to pull down in
            // one go, and nobody scrolls past the first few hundred.
            page = pagesRead < limitPages
                ? try nextPage(body.next, visited: &visited)
                : nil
        } while page != nil
        return values
    }

    func posts(byAuthor authorID: Int) async throws -> [FeedPost] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [FeedPost] = []
        // Paged through rather than stopping at the first page: a profile is
        // the one place somebody scrolls back through everything they have
        // posted, and a count that stops at twenty would be wrong.
        repeat {
            let output = try await client.socialPostsList(
                query: .init(author: authorID, page: page)
            )
            let body: Components.Schemas.PaginatedPostList
            switch output {
            case .ok(let response):
                body = try response.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: body.results.map(Self.post(from:)))
            page = try nextPage(body.next, visited: &visited)
        } while page != nil
        return values
    }

    // MARK: - Posting

    /// Posts something the signed-in user owns.
    ///
    /// Only which object, never its contents: the server reads the workout,
    /// meal or entry itself and builds the snapshot from it, so nothing the
    /// phone sends can decide what a post claims was done.
    @discardableResult
    func post(
        kind: PostKind,
        sourceID: Int,
        caption: String,
        visibility: PostVisibility,
        showsWeights: Bool = true,
        photo: PostPhoto? = nil,
        // How the meal was made. The server keeps it on a meal post's
        // snapshot and ignores it for any other kind.
        cookingInstructions: String = ""
    ) async throws -> FeedPost {
        guard let kindPayload = Components.Schemas.CreatePostKindEnum(
            rawValue: kind.apiValue
        ), let visibilityPayload = Components.Schemas.VisibilityEnum(
            rawValue: visibility.rawValue
        ) else {
            throw APIServiceError.malformedResponse
        }

        // A type the contract does not list is refused here rather than sent
        // and refused there, since the 400 would name a field the user never
        // saw. Nil for both halves means no photo, which is the normal case.
        var contentType: Components.Schemas.ContentTypeEnum?
        if let photo {
            guard let accepted = Components.Schemas.ContentTypeEnum(
                rawValue: photo.contentType
            ) else {
                throw APIServiceError.malformedResponse
            }
            contentType = accepted
        }

        try await ModerationConsent.require()
        let output = try await client.socialPostsCreate(
            body: .json(
                Components.Schemas.CreatePostRequest(
                    kind: kindPayload,
                    sourceId: sourceID,
                    caption: caption,
                    showsWeights: showsWeights,
                    visibility: .init(value1: visibilityPayload),
                    contentType: contentType,
                    imageBase64: photo?.base64,
                    // Omitted rather than sent blank, so an empty box does
                    // not read as somebody having written nothing on purpose.
                    cookingInstructions: cookingInstructions.isEmpty
                        ? nil
                        : cookingInstructions
                )
            )
        )
        switch output {
        case .created(let response):
            return Self.post(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// The caption and who can see it. The snapshot is a record of what
    /// happened and the API will not take an edit to it.
    @discardableResult
    func update(
        _ postID: Int,
        caption: String,
        visibility: PostVisibility
    ) async throws -> FeedPost {
        guard let visibilityPayload = Components.Schemas.VisibilityEnum(
            rawValue: visibility.rawValue
        ) else {
            throw APIServiceError.malformedResponse
        }

        try await ModerationConsent.require()
        let output = try await client.socialPostsPartialUpdate(
            path: .init(id: postID),
            body: .json(
                // Unwrapped, unlike the create request: an optional field is
                // generated as the enum itself rather than behind a payload.
                Components.Schemas.PatchedUpdatePostRequest(
                    caption: caption,
                    visibility: visibilityPayload
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.post(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func delete(_ postID: Int) async throws {
        let output = try await client.socialPostsDestroy(path: .init(id: postID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Liking, reposting, commenting

    /// Sets whether the reader likes this post, and answers with the card as
    /// it now stands.
    ///
    /// The server sends the whole post back rather than a count, so the reply
    /// also carries any likes and comments that arrived while this one was in
    /// flight. Both directions are idempotent: a second tap, or a retry of a
    /// request whose answer was lost, lands on the same state.
    func setLiked(_ liked: Bool, postID: Int) async throws -> FeedPost {
        if liked {
            switch try await client.socialPostsLikeCreate(path: .init(id: postID)) {
            case .ok(let response):
                return Self.post(from: try response.body.json)
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }
        switch try await client.socialPostsLikeDestroy(path: .init(id: postID)) {
        case .ok(let response):
            return Self.post(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Passes the post on to the reader's followers, or takes it back.
    ///
    /// Answers with the **original**, which is not always the post asked
    /// about: reposting a repost passes on what it points at, and the counts
    /// that changed are the original's.
    func setReposted(_ reposted: Bool, postID: Int) async throws -> FeedPost {
        if reposted {
            switch try await client.socialPostsRepostCreate(path: .init(id: postID)) {
            case .ok(let response):
                return Self.post(from: try response.body.json)
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }
        switch try await client.socialPostsRepostDestroy(path: .init(id: postID)) {
        case .ok(let response):
            return Self.post(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Copies a posted workout into the reader's own workouts.
    ///
    /// Exercises and their set counts, not weights: what is saved is a plan to
    /// follow, not a record of somebody else's session. The name comes back
    /// because it is not always the one on the post — a copy of a workout you
    /// already have is named after who it came from.
    func saveWorkout(fromPost postID: Int) async throws -> SavedWorkoutOutcome {
        let output = try await client.socialPostsSaveWorkoutCreate(
            path: .init(id: postID)
        )
        switch output {
        case .created(let response):
            let result = try response.body.json
            return SavedWorkoutOutcome(
                name: result.name,
                exerciseCount: result.exerciseCount,
                wasRenamed: result.renamed
            )
        // 200 rather than 201: this post had been saved before and the
        // server handed back the copy instead of making a second one.
        case .ok(let response):
            let result = try response.body.json
            return SavedWorkoutOutcome(
                name: result.name,
                exerciseCount: result.exerciseCount,
                wasRenamed: result.renamed,
                wasAlreadySaved: true
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Copies a posted meal into the reader's own saved meals.
    ///
    /// Returns the name for the same reason the workout call does: saved meal
    /// names are unique per person and everyone has a "Meal 1", so the copy
    /// very often lands under a different one.
    func saveMeal(fromPost postID: Int) async throws -> SavedMealOutcome {
        let output = try await client.socialPostsSaveMealCreate(
            path: .init(id: postID)
        )
        switch output {
        case .created(let response):
            let result = try response.body.json
            return SavedMealOutcome(
                name: result.name,
                itemCount: result.itemCount,
                wasRenamed: result.renamed
            )
        // See saveWorkout: 200 means it was already there.
        case .ok(let response):
            let result = try response.body.json
            return SavedMealOutcome(
                name: result.name,
                itemCount: result.itemCount,
                wasRenamed: result.renamed,
                wasAlreadySaved: true
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Reports a post.
    ///
    /// Returns whether this reader had already reported it. The server answers
    /// 200 rather than an error in that case, so both outcomes are successes
    /// and the difference is only what the app says afterwards.
    func report(
        postID: Int,
        reason: PostReportReason,
        detail: String
    ) async throws -> Bool {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try await client.socialPostsReportCreate(
            path: .init(id: postID),
            body: .json(
                Components.Schemas.ReportPostRequest(
                    reason: Components.Schemas.ReasonEnum(rawValue: reason.rawValue)
                        ?? .other,
                    detail: trimmed.isEmpty ? nil : trimmed
                )
            )
        )
        switch output {
        case .created:
            return false
        case .ok:
            return true
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Blocks somebody. The server drops any following in either direction.
    func block(userID: Int) async throws {
        let output = try await client.socialBlocksCreate(
            body: .json(Components.Schemas.BlockRequest(blocked: userID))
        )
        switch output {
        case .created:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Everyone this reader has blocked, so a block can be lifted again.
    func blocks() async throws -> [BlockedPerson] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [BlockedPerson] = []
        repeat {
            let output = try await client.socialBlocksList(query: .init(page: page))
            let response: Components.Schemas.PaginatedBlockList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.map(Self.blocked(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    /// Lifts a block, by the id of the block itself rather than the person.
    func unblock(blockID: Int) async throws {
        let output = try await client.socialBlocksDestroy(path: .init(id: blockID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private static func blocked(
        from payload: Components.Schemas.Block
    ) -> BlockedPerson {
        BlockedPerson(
            id: payload.id,
            person: author(from: payload.blockedUser.value1)
        )
    }

    /// One post, for a page opened from somewhere the feed does not cover.
    func post(withID id: Int) async throws -> FeedPost {
        switch try await client.socialPostsRetrieve(path: .init(id: id)) {
        case .ok(let response):
            return Self.post(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Every thread on a post, oldest first, replies nested inside each.
    func comments(forPost postID: Int) async throws -> [PostComment] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [PostComment] = []
        repeat {
            let output = try await client.socialCommentsList(
                query: .init(page: page, post: postID)
            )
            let response: Components.Schemas.PaginatedPostCommentList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.map(Self.comment(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    @discardableResult
    func addComment(
        _ body: String,
        toPost postID: Int,
        replyingTo parentID: Int?
    ) async throws -> PostComment {
        try await ModerationConsent.require()
        let output = try await client.socialCommentsCreate(
            body: .json(
                Components.Schemas.PostCommentRequest(
                    post: postID,
                    parent: parentID,
                    body: body
                )
            )
        )
        switch output {
        case .created(let response):
            return Self.comment(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func deleteComment(_ commentID: Int) async throws {
        let output = try await client.socialCommentsDestroy(path: .init(id: commentID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Following

    /// Everybody, or the people matching a search.
    ///
    /// The search is the server's rather than a filter over what was already
    /// downloaded. The people worth finding are mostly the ones not on screen
    /// yet — somebody who has never posted appears in no feed at all — and a
    /// client-side filter can only ever narrow what it already holds.
    func people(matching search: String? = nil) async throws -> [PostAuthor] {
        let term = Self.searchTerm(search)
        return try await pagedPeople { page in
            switch try await self.client.usersList(
                query: .init(page: page, search: term)
            ) {
            case .ok(let response): return try response.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }
    }

    /// A term worth sending, or nil for no search at all.
    ///
    /// Whitespace alone is not a search. Sent as an empty string the
    /// parameter would be present and blank, which this server happens to
    /// read as no filter — but relying on that makes an empty box depend on
    /// a server-side detail, and the day it changes the page silently empties.
    private static func searchTerm(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func followers(of userID: Int) async throws -> [PostAuthor] {
        try await pagedPeople { page in
            switch try await self.client.usersFollowersList(
                path: .init(id: userID),
                query: .init(page: page)
            ) {
            case .ok(let response): return try response.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }
    }

    func following(of userID: Int) async throws -> [PostAuthor] {
        try await pagedPeople { page in
            switch try await self.client.usersFollowingList(
                path: .init(id: userID),
                query: .init(page: page)
            ) {
            case .ok(let response): return try response.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        }
    }

    private func pagedPeople(
        request: (Int?) async throws -> Components.Schemas.PaginatedPublicRepbaseUserList
    ) async throws -> [PostAuthor] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [PostAuthor] = []
        repeat {
            let body = try await request(page)
            values.append(contentsOf: body.results.map(Self.author(from:)))
            page = try nextPage(body.next, visited: &visited)
        } while page != nil
        return values
    }

    /// What happened when the button was pressed.
    ///
    /// A closed profile cannot be followed outright, so the same tap means
    /// two different things and the button has to know which.
    enum FollowOutcome {
        case following
        case requested
    }

    @discardableResult
    func follow(_ userID: Int) async throws -> FollowOutcome {
        let output = try await client.usersFollowCreate(path: .init(id: userID))
        switch output {
        case .created, .ok:
            return .following
        case .accepted:
            return .requested
        case .conflict:
            // A block stands between the two people. Reported rather than
            // retried: nothing the app does will make this succeed.
            throw APIServiceError.undocumentedStatus(409)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func unfollow(_ userID: Int) async throws {
        let output = try await client.usersFollowDestroy(path: .init(id: userID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Requests waiting on you

    func followRequests() async throws -> [FollowRequestSummary] {
        let output = try await client.socialFollowRequestsList(query: .init())
        switch output {
        case .ok(let response):
            return try response.body.json.results.map {
                FollowRequestSummary(
                    id: $0.id,
                    requesterID: $0.requesterId,
                    username: $0.username,
                    firstName: $0.firstName,
                    lastName: $0.lastName,
                    photoURL: $0.profilePhotoUrl
                )
            }
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - What has happened to you

    func notifications() async throws -> [SocialNotification] {
        let output = try await client.socialNotificationsList(query: .init())
        switch output {
        case .ok(let response):
            return try response.body.json.results.map { row in
                SocialNotification(
                    id: row.id,
                    kind: SocialNotification.Kind(rawValue: row.kind.rawValue)
                        ?? .unknown,
                    actorID: row.actorId,
                    actorUsername: row.actorUsername,
                    actorFirstName: row.actorFirstName,
                    actorLastName: row.actorLastName,
                    actorPhotoURL: row.actorPhotoUrl,
                    postID: row.post,
                    commentBody: row.commentBody,
                    isRead: row.isRead
                )
            }
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    @discardableResult
    func unreadNotificationCount() async throws -> Int {
        let output = try await client.socialNotificationsUnreadCountRetrieve()
        switch output {
        case .ok(let response):
            return try response.body.json.unread
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func markNotificationsRead() async throws {
        let output = try await client.socialNotificationsReadCreate()
        switch output {
        case .ok:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func approveFollowRequest(_ id: Int) async throws {
        let output = try await client.socialFollowRequestsApproveCreate(
            path: .init(id: id)
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func declineFollowRequest(_ id: Int) async throws {
        let output = try await client.socialFollowRequestsDestroy(
            path: .init(id: id)
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

    private static func post(from payload: Components.Schemas.Post) -> FeedPost {
        FeedPost(
            id: payload.id,
            author: author(from: payload.author.value1),
            kind: PostKind(payload.kind),
            caption: payload.caption,
            // A URL the server built. Dropped rather than guessed at if it is
            // not one, so a card draws without its photo instead of failing.
            imageURL: payload.imageUrl.flatMap { URL(string: $0) },
            // Falls back to the original here as well as on the server. The
            // server already answers with it when no smaller copy exists, so
            // this covers only the case of a build talking to an older one.
            feedImageURL: payload.feedImageUrl.flatMap { URL(string: $0) }
                ?? payload.imageUrl.flatMap { URL(string: $0) },
            // An unknown visibility reads as the most private thing it could
            // be, so a build that has not learned a new level never draws
            // something as more widely shared than it is.
            visibility: PostVisibility(rawValue: payload.visibility) ?? .privateToMe,
            createdAt: payload.createdAt,
            viewerFollowsAuthor: payload.viewerFollowsAuthor,
            sourceID: payload.sourceId,
            workout: payload.workout.map { workout(from: $0.value1) },
            meal: payload.meal.map { meal(from: $0.value1) },
            planner: payload.planner.map { planner(from: $0.value1) },
            likeCount: payload.likeCount,
            commentCount: payload.commentCount,
            repostCount: payload.repostCount,
            viewerHasLiked: payload.viewerHasLiked,
            viewerHasReposted: payload.viewerHasReposted,
            viewerHasSaved: payload.viewerSaved,
            showsWeights: payload.showsWeights,
            viewerIsAuthor: payload.viewerIsAuthor,
            repostOf: payload.repostOf.map { reposted(from: $0.value1) }
        )
    }

    private static func reposted(
        from payload: Components.Schemas.RepostedPost
    ) -> RepostedPost {
        RepostedPost(
            id: payload.id,
            author: author(from: payload.author.value1),
            kind: PostKind(payload.kind),
            caption: payload.caption,
            imageURL: payload.imageUrl.flatMap { URL(string: $0) },
            feedImageURL: payload.feedImageUrl.flatMap { URL(string: $0) }
                ?? payload.imageUrl.flatMap { URL(string: $0) },
            createdAt: payload.createdAt,
            workout: payload.workout.map { workout(from: $0.value1) },
            meal: payload.meal.map { meal(from: $0.value1) },
            planner: payload.planner.map { planner(from: $0.value1) }
        )
    }

    private static func comment(
        from payload: Components.Schemas.PostComment
    ) -> PostComment {
        PostComment(
            id: payload.id,
            postID: payload.post,
            author: author(from: payload.author.value1),
            parentID: payload.parent,
            body: payload.body,
            replies: payload.replies.map { reply(from: $0) },
            viewerIsAuthor: payload.viewerIsAuthor,
            createdAt: payload.createdAt
        )
    }

    private static func reply(
        from payload: Components.Schemas.PostReply
    ) -> PostComment {
        PostComment(
            id: payload.id,
            postID: payload.post,
            author: author(from: payload.author.value1),
            parentID: payload.parent,
            body: payload.body,
            // A reply cannot have replies; the server refuses to make one.
            replies: [],
            viewerIsAuthor: payload.viewerIsAuthor,
            createdAt: payload.createdAt
        )
    }

    private static func author(
        from payload: Components.Schemas.PublicRepbaseUser
    ) -> PostAuthor {
        PostAuthor(
            id: payload.id,
            username: payload.username,
            firstName: payload.firstName,
            lastName: payload.lastName,
            photoURL: payload.profilePhotoUrl
        )
    }

    private static func workout(
        from payload: Components.Schemas.PostWorkout
    ) -> PostWorkoutSnapshot {
        PostWorkoutSnapshot(
            title: payload.title,
            workoutType: payload.workoutType,
            performedAt: payload.performedAt,
            durationSeconds: payload.durationSeconds,
            exerciseCount: payload.exerciseCount,
            totalSetCount: payload.totalSetCount,
            totalVolumeKg: payload.totalVolumeKg.flatMap { Decimal(string: $0) },
            routeDistanceKm: payload.routeDistanceKm.flatMap { Decimal(string: $0) },
            exercises: payload.exercises.map { exercise in
                PostExerciseLine(
                    id: exercise.id,
                    name: exercise.name,
                    setCount: exercise.setCount,
                    topSetWeightKg: exercise.topSetWeightKg.flatMap { Decimal(string: $0) },
                    topSetReps: exercise.topSetReps
                )
            }
        )
    }

    private static func meal(
        from payload: Components.Schemas.PostMeal
    ) -> PostMealSnapshot {
        PostMealSnapshot(
            name: payload.name,
            date: payload.date,
            totalCalories: FoodDecimal.value(payload.totalCalories),
            totalProteinGrams: FoodDecimal.value(payload.totalProteinGrams),
            totalCarbohydrateGrams: FoodDecimal.value(payload.totalCarbohydrateGrams),
            totalFatGrams: FoodDecimal.value(payload.totalFatGrams),
            entries: payload.entries.map { entry in
                PostFoodLine(
                    id: entry.id,
                    name: entry.name,
                    servings: FoodDecimal.value(entry.servings),
                    totalCalories: FoodDecimal.value(entry.totalCalories)
                )
            },
            cookingInstructions: payload.cookingInstructions ?? ""
        )
    }

    private static func planner(
        from payload: Components.Schemas.PostPlannerEntry
    ) -> PostPlannerSnapshot {
        PostPlannerSnapshot(
            kind: payload.kind,
            title: payload.title,
            category: payload.category,
            scheduledDate: payload.scheduledDate,
            scheduledTime: payload.scheduledTime,
            isComplete: payload.isComplete
        )
    }

    // MARK: - Paging

    /// The cursor out of the server's own `next` link.
    ///
    /// Checked against the configured host before it is used, the way the
    /// numbered pages elsewhere are: a `next` pointing somewhere else would
    /// send the token with it.
    private func nextCursor(_ next: String?) throws -> String? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              Self.sameOrigin(url, configuration.serverURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let cursor = components.queryItems?
                .first(where: { $0.name == "cursor" })?.value,
              !cursor.isEmpty else {
            throw APIServiceError.untrustedPaginationURL
        }
        return cursor
    }

    /// The same check for the numbered pages comments use.
    ///
    /// Comments are not paged by cursor: a thread is read from the top and
    /// grows at the bottom, so a page number means the same thing on the next
    /// request. `visited` stops a server that answers with a `next` pointing
    /// backwards from looping this forever.
    private func nextPage(
        _ next: String?,
        visited: inout Set<Int>
    ) throws -> Int? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              Self.sameOrigin(url, configuration.serverURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?
                .first(where: { $0.name == "page" })?.value,
              let page = Int(value),
              page > 0,
              visited.insert(page).inserted else {
            throw APIServiceError.untrustedPaginationURL
        }
        return page
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}
