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
        visibility: PostVisibility
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
                visibility: visibility
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

    func clearError() {
        errorMessage = nil
    }
}
