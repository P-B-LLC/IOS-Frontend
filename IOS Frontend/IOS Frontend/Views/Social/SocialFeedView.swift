//
//  SocialFeedView.swift
//  IOS Frontend
//
//  For You, the people you follow, and everybody else.
//

import Foundation
import SwiftUI

/// A post id that can be presented as a sheet.
private struct CommentedPost: Identifiable, Hashable {
    let id: Int
}

/// A person id being navigated to. Its own type rather than a bare Int so it
/// does not collide with the post destination, which is also an Int.
private struct VisitedPerson: Identifiable, Hashable {
    let id: Int
}

struct SocialFeedView: View {
    /// What a tab's first load depends on: which tab is showing, and whether
    /// there is a connection to load it through.
    ///
    /// Keyed on both because keying on the tab alone lost the first load
    /// every time. Restoring the session is asynchronous, so the task fires
    /// once with no repository behind the store, returns at its own guard,
    /// and -- the tab never having changed -- is never asked again. The feed
    /// then sits on "Nothing here yet" while the server has posts to give
    /// it, which reads as an empty account rather than a dropped request.
    private struct FeedLoad: Equatable {
        let mode: FeedMode
        let isConnected: Bool
    }

    /// The three tabs.
    ///
    /// For You is ranked for the reader by the server -- everybody's posts,
    /// best first, each saying why it is there. Following is the people the
    /// reader chose, newest first, and nothing else. It was folded into For
    /// You once, when For You was only that feed with strangers appended and
    /// a Following tab beside it showed nothing For You did not. Now that For
    /// You is ranked, the plain list of the people you follow is something
    /// only its own tab gives.
    private enum FeedMode: String, CaseIterable, Identifiable {
        /// Picked by the server, best first.
        case forYou = "For you"
        /// The people you follow, newest first.
        case following = "Following"
        /// People worth following and everybody's latest.
        case discover = "Discover"
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .forYou: "For you"
            case .following: "Following"
            case .discover: "Discover"
            }
        }
    }

    @Environment(SocialStore.self) private var store
    @Environment(SocialProfileStore.self) private var profileStore
    @Environment(\.repbaseNavigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var searchTransition

    /// Opens straight onto a post's thread. Only set by the preview launch
    /// mode: `simctl` cannot tap, so pushing on arrival is the only way to
    /// see that tapping a card leads anywhere at all — which is exactly what
    /// was broken and shipped once already.
    var initiallyOpened: Int?

    @State private var isComposing = false
    /// The post whose page is open, if one is.
    @State private var opened: Int?
    /// The post whose comments are raised over the feed, if any. Wrapped
    /// because `sheet(item:)` wants Identifiable and a bare Int is not —
    /// unlike `navigationDestination(item:)`, which only wants Hashable.
    @State private var commenting: CommentedPost?
    @State private var feedMode: FeedMode = .forYou
    @State private var isSearching = false
    @State private var initialSearchText = ""
    /// Whether the For You tuning sheet is up.
    @State private var isTuning = false
    /// Whose profile is open, if anyone's.
    @State private var visiting: VisitedPerson?

    var body: some View {
        screen(timeOfDay: HomeTimeOfDay.current)
        // Out here, not inside the TimelineView. In there it is torn down and
        // re-declared on every tick, and a push never happened: liking a post
        // worked because it needs no navigation, while tapping a card or its
        // comment button did nothing at all.
        .navigationDestination(item: $opened) { id in
            PostDetailView(postID: id)
        }
        .navigationDestination(item: $visiting) { person in
            PersonProfileView(userID: person.id)
        }
        .task {
#if DEBUG
            // Types into the search box, because simctl cannot. Deliberately
            // the real signed-in feed against the real server rather than the
            // preview harness: what is worth looking at here is whether the
            // server's answer draws correctly, which sample data cannot show.
            // Opens the composer, which opens the cropper over it. The whole
            // route rather than the cropper alone: presented this way it had
            // no top safe area and Cancel sat under the Dynamic Island, and a
            // preview of the cropper on its own showed none of that.
            if ProcessInfo.processInfo.environment["REPBASE_COMPOSER_CROP"] != nil {
                isComposing = true
            }
            if let seeded = ProcessInfo.processInfo.environment["REPBASE_SOCIAL_SEARCH"] {
                initialSearchText = seeded
                isSearching = true
            }
            // Opens a real post inside the real signed-in app, tab bar and
            // all. The preview harness renders this page on a bare stack,
            // which is not the layout anyone actually gets.
            if let raw = ProcessInfo.processInfo.environment["REPBASE_SOCIAL_OPEN"],
               let id = Int(raw) {
                opened = id
                return
            }
            if let raw = ProcessInfo.processInfo.environment["REPBASE_SOCIAL_COMMENT"],
               let id = Int(raw) {
                commenting = CommentedPost(id: id)
                return
            }
#endif
            if let initiallyOpened { opened = initiallyOpened }
            await store.refreshUnreadNotificationCount()
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if feedMode == .discover, !store.suggestedPeople.isEmpty {
                    suggestionsSection(timeOfDay: timeOfDay)
                }

                if feedMode == .forYou, let receipt = store.publicationReceipt,
                   store.forYou.contains(where: { $0.id == receipt.postID }) {
                    publicationConfirmation(id: receipt.id, timeOfDay: timeOfDay)
                }

                if let message = store.errorMessage {
                    notice(message, symbol: "exclamationmark.triangle.fill", timeOfDay: timeOfDay)
                        .padding(.horizontal, RepbaseDesign.pageInset)
                        .padding(.vertical, 8)
                }

                // Saves are confirmed by a toast over the page rather than a
                // notice inserted into it. See saveConfirmation below.

                // Reporting and blocking both act out of sight -- one goes to
                // a queue, the other quietly empties part of the feed -- so
                // both say so here rather than leaving the tap unanswered.
                if let message = store.lastModerationMessage {
                    notice(
                        message,
                        symbol: "checkmark.circle.fill",
                        timeOfDay: timeOfDay
                    )
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .padding(.vertical, 8)
                    .onTapGesture { store.lastModerationMessage = nil }

                    if let pending = store.lastPosted,
                       pending.publicationMessage == message,
                       pending.moderationStatus != "rejected" {
                        Button("Check post status") {
                            Task { await store.refreshPublicationStatuses() }
                        }
                        .font(.community(.footnote, weight: .semibold))
                        .frame(minHeight: 44)
                        .buttonStyle(.bordered)
                        .padding(.bottom, 8)
                    }
                }

                if isListLoading && displayedPosts.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if displayedPosts.isEmpty {
                    emptyState(timeOfDay: timeOfDay)
                } else {
                    ForEach(displayedPosts) { post in
                        if feedMode == .forYou, let how = store.dismissals[post.id] {
                            dismissedRow(post, how: how, timeOfDay: timeOfDay)
                        } else {
                            // The card is not itself a button: the action bar
                            // inside it has four of its own, and a button
                            // holding buttons swallows their taps. A tap
                            // anywhere else opens the post.
                            PostCard(
                                post: post,
                                timeOfDay: timeOfDay,
                                // The button raises the threads over the feed
                                // so a comment can be left without losing your
                                // place in it; tapping the card opens the post.
                                openComments: { commenting = CommentedPost(id: post.id) },
                                openAuthor: { visiting = VisitedPerson(id: $0) }
                            )
                                .contentShape(Rectangle())
                                .onTapGesture { opened = post.id }
                                // What was on screen, and for how long, is
                                // how For You tells a post somebody stopped
                                // on from one they flicked past. Mostly on
                                // screen counts, as on the web.
                                .onScrollVisibilityChange(threshold: 0.6) { visible in
                                    guard feedMode == .forYou, !isSearching, !isComposing else { return }
                                    if visible {
                                        store.impressionShown(post.id)
                                    } else {
                                        store.impressionHidden(post.id)
                                    }
                                }
                                .task {
                                    // The last card asks for the next page as
                                    // it comes into view, so the feed keeps
                                    // going without a button to press.
                                    // Discover is a capped read, not a cursor
                                    // walk, and has no next page to ask for.
                                    switch feedMode {
                                    case .forYou where post.id == store.forYou.last?.id:
                                        await store.loadMoreForYou()
                                    case .following where post.id == store.feed.last?.id:
                                        await store.loadMore()
                                    default:
                                        break
                                    }
                                }
                        }
                    }

                    if isLoadingMore {
                        ProgressView().padding(.vertical, 12)
                    } else if feedMode == .following, store.hasReachedEnd {
                        caughtUpDivider(timeOfDay: timeOfDay)
                    }
                }
            }
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        // Search, Post and the feed tabs remain reachable while the feed
        // scrolls. Presenting search does not replace or reset this scroll.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                socialHeader(timeOfDay: timeOfDay)
                modePicker(timeOfDay: timeOfDay)
            }
            .background(Color(.systemBackground))
        }
        .scrollIndicators(.hidden)
        .minimizesBottomBarOnScroll()
        // Pulls down on whichever list the tab is actually showing. For You
        // ranks again from the top, which is what a pull means there: what
        // was just seen moves down, and what was just liked counts.
        .refreshable {
            switch feedMode {
            case .forYou:
                await store.loadForYou()
            case .following:
                await store.refresh()
            case .discover:
                await store.loadDiscover()
                await store.loadSuggestedPeople()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
        .repbaseToast(saveConfirmation) { destination in
            navigate(destination)
        }
        .fullScreenCover(isPresented: $isComposing, onDismiss: {
            Task { await store.refreshPublicationStatuses() }
        }) {
            PostComposerView()
        }
        .fullScreenCover(isPresented: $isSearching, onDismiss: {
            initialSearchText = ""
            store.clearSearch()
        }) {
            if reduceMotion {
                SocialSearchView(initialQuery: initialSearchText)
            } else {
                SocialSearchView(initialQuery: initialSearchText)
                    .navigationTransition(.zoom(sourceID: "social.search", in: searchTransition))
            }
        }
        .sheet(item: $commenting) { target in
            PostCommentsSheet(postID: target.id, timeOfDay: timeOfDay)
        }
        // Ranks again once the sheet is gone, if anything in it changed, so
        // the page under it is never the one the old choices made.
        .sheet(isPresented: $isTuning, onDismiss: {
            if store.forYouNeedsReranking {
                Task { await store.loadForYou() }
            }
        }) {
            ForYouSettingsView(timeOfDay: timeOfDay)
        }
        .task(id: FeedLoad(mode: feedMode, isConnected: store.isConnected)) {
            guard store.isConnected else { return }
            switch feedMode {
            case .forYou:
                // Once per connection. Coming back to the tab keeps the page
                // somebody was reading; pulling down is how to rank again.
                if !store.hasLoadedForYou { await store.loadForYou() }
            case .following:
                // Loaded on connecting, and refreshed by pulling down.
                break
            case .discover:
                await store.loadDiscover()
                if !store.hasLoadedSuggestions { await store.loadSuggestedPeople() }
            }
            if let viewerID = profileStore.viewerID {
                await store.loadRelationships(for: viewerID)
            }
        }
        // Viewings still open when the page goes -- another tab, a pushed
        // post, the app to the background -- are closed and sent then, or
        // they would describe a reader staring at a post for an hour.
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                Task { await store.finishImpressions() }
            } else {
                Task { await store.refreshPublicationStatuses() }
            }
        }
        .onChange(of: feedMode) {
            Task { await store.finishImpressions() }
        }
        .onChange(of: isSearching) {
            if isSearching { Task { await store.finishImpressions() } }
        }
        .onDisappear {
            Task { await store.finishImpressions() }
        }
    }

    private func socialHeader(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Social")
                        .font(.community(.title, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                    Text("A little inspiration. A lot of you.")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink {
                    NotificationsView()
                } label: {
                    Image(systemName: "bell")
                        .font(.community(.headline))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .frame(width: 44, height: 44)
                        .background(SocialSearchStyle.softSurface, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if store.unreadNotifications > 0 {
                                Circle()
                                    .fill(timeOfDay.accent)
                                    .frame(width: 7, height: 7)
                                    .padding(8)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
                .accessibilityValue(store.unreadNotifications > 0 ? Text("Unread notifications") : Text("No unread notifications"))
            }

            // One persistent transition source, not duplicate sources inside
            // ViewThatFits. The icon-only control leaves room for every
            // localized Post label without filling the row with a prompt.
            HStack(spacing: 10) {
                searchButton(timeOfDay: timeOfDay)
                Spacer(minLength: 0)
                postButton(timeOfDay: timeOfDay)
            }
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func searchButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            isSearching = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.community(.headline, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .frame(width: 72, height: 44)
                .modifier(SocialSearchGlass())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: "social.search", in: searchTransition)
        .accessibilityLabel("Search people or hashtags")
        .accessibilityHint("Search by name, handle, hashtag, or words in a post")
        .accessibilityIdentifier("social.search")
    }

    private func postButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            isComposing = true
        } label: {
            Label("Post", systemImage: "plus")
                .font(.community(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .fixedSize()
                .padding(.horizontal, 22)
                .frame(minHeight: 44)
                .background(timeOfDay.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create post")
    }

    private func modePicker(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 6) {
            ForEach(FeedMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        feedMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.community(.footnote, weight: feedMode == mode ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(
                            feedMode == mode
                                ? timeOfDay.onPrimaryAction
                                : timeOfDay.canvasSecondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .background(feedMode == mode ? timeOfDay.primaryActionSurface : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(feedMode == mode ? [.isSelected] : [])
            }
            if feedMode == .forYou {
                Button {
                    isTuning = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.community(.headline))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tune For You")
                .accessibilityHint("Adjust topics and recommendations")
            }
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 8)
    }

    private func publicationConfirmation(id: UUID, timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 8) {
            Label("Posted. Your update is in For You.", systemImage: "checkmark.circle.fill")
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 0)
            Button {
                store.consumePublicationReceipt(id: id)
            } label: {
                Image(systemName: "xmark")
                    .font(.community(.caption))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss posting confirmation")
        }
        .tint(timeOfDay.accent)
        .padding(.horizontal, RepbaseDesign.pageInset)
        .task(id: id) {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            store.consumePublicationReceipt(id: id)
        }
    }


    private var isListLoading: Bool {
        switch feedMode {
        case .forYou:
            // Also before the first load has started, so the tab opens on a
            // spinner rather than flashing "nothing here" -- unless that load
            // failed, when the message above says why and a pull retries.
            return store.isLoadingForYou
                || (!store.hasLoadedForYou && store.isConnected && store.errorMessage == nil)
        case .following:
            return store.isLoading
        case .discover:
            return store.isLoadingDiscover
        }
    }

    private var isLoadingMore: Bool {
        switch feedMode {
        case .forYou: return store.isLoadingMoreForYou
        case .following: return store.isLoadingMore
        case .discover: return false
        }
    }

    /// What the list shows, which is a different question per tab.
    ///
    /// For You is the server's ranking for this reader. Following is the
    /// people they follow, newest first. Discover is everybody else's latest,
    /// while search has its own presentation and never replaces a feed.
    ///
    /// Results arrive already narrowed by a server that also decided what
    /// this reader may see, so nothing is filtered here: a second pass could
    /// only ever remove rows the server allowed.
    private var displayedPosts: [FeedPost] {
        switch feedMode {
        case .forYou:
            return store.forYou
        case .following:
            return store.feed
        case .discover:
            return store.discoverPosts
        }
    }

    /// Opens the composer. Kept beside the title rather than floating over the
    /// feed: the bottom bar already sits there, and a second round button above
    /// it read as part of the same control.
    private func composeButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            isComposing = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.community(size: 16, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 44, height: 44)
                .background(timeOfDay.accent.opacity(0.11), in: Circle())
                .overlay {
                    Circle().strokeBorder(timeOfDay.canvasBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New post")
    }

    /// A post the reader said "not interested" or "fewer like this" to, held
    /// in place with the way back. The card goes; the space it was in says
    /// what happened.
    private func dismissedRow(
        _ post: FeedPost,
        how: ForYouDismissal,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: how == .fewerLikeThis ? "hand.thumbsdown" : "eye.slash")
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            Text(how == .fewerLikeThis
                 ? "Hidden. You will see less of this kind of post."
                 : "Hidden. You will see fewer posts like this.")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Undo") {
                Task {
                    switch how {
                    case .notInterested:
                        await store.setNotInterested(false, post: post)
                    case .fewerLikeThis:
                        await store.setFewerLikeThis(false, post: post)
                    }
                }
            }
            .font(.community(.caption, weight: .bold))
            .foregroundStyle(timeOfDay.accent)
            .buttonStyle(.plain)
            .accessibilityHint("Shows this post again")
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// People the server suggests following, on Discover before a search.
    private func suggestionsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SUGGESTED FOR YOU")
                .font(.community(.caption2, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(timeOfDay.accent)
                .padding(.bottom, 8)

            ForEach(Array(store.suggestedPeople.enumerated()), id: \.element.id) { index, suggestion in
                if store.dismissedSuggestionIDs.contains(suggestion.id) {
                    HStack(spacing: 10) {
                        Text("You will not see @\(suggestion.person.username) suggested for a while.")
                            .font(.community(.caption))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Undo") {
                            Task { await store.setSuggestionDismissed(false, person: suggestion) }
                        }
                        .font(.community(.caption, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                } else {
                    suggestionRow(suggestion, timeOfDay: timeOfDay)
                }
                if index < store.suggestedPeople.count - 1 { Divider() }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, RepbaseDesign.pageInset)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func suggestionRow(_ suggestion: SuggestedPerson, timeOfDay: HomeTimeOfDay) -> some View {
        let person = suggestion.person
        return HStack(spacing: 12) {
            Circle()
                .fill(timeOfDay.accent.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(person.initials)
                        .font(.community(.caption, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .lineLimit(1)
                // Why, rather than the handle alone: "followed by 2 people you
                // follow" is the reason to tap Follow, and the handle is one
                // tap away on their profile.
                Text(suggestion.label)
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
                // The gap is part of the row, so the whole line opens the
                // profile rather than just the name.
                .contentShape(Rectangle())
            FollowButton(
                person: person,
                relationship: store.relationship(with: person.id, viewerID: profileStore.viewerID),
                viewerID: profileStore.viewerID
            )

            Button {
                Task { await store.setSuggestionDismissed(true, person: suggestion) }
            } label: {
                Image(systemName: "xmark")
                    .font(.community(size: 11, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not interested in \(person.displayName)")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // Not a Button wrapping the row: it holds two buttons of its own.
        .onTapGesture { visiting = VisitedPerson(id: person.id) }
    }

    /// The line at the end of the people you follow.
    private func caughtUpDivider(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(timeOfDay.canvasSecondaryText.opacity(0.25))
                .frame(height: 1)
            Text("YOU'RE ALL CAUGHT UP")
                .font(.community(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize()
            Rectangle()
                .fill(timeOfDay.canvasSecondaryText.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 22)
    }


    private func emptyState(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 10) {
            Image(systemName: feedMode == .discover ? "person.2.badge.plus" : "person.2")
                .font(.community(size: 30, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
            Text(feedMode == .discover ? "Nobody new right now" : "Nothing here yet")
                .font(.community(.headline))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text(emptyExplanation)
                .font(.community(.subheadline))
                .multilineTextAlignment(.center)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Repeats the header's button where the eye already is. An empty
            // feed is exactly when the one in the corner goes unnoticed.
            // Not on Discover: nothing there is waiting on the reader to post.
            if feedMode != .discover {
                Button("Write a post") { isComposing = true }
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 22)
    }

    private var emptyExplanation: LocalizedStringKey {
        switch feedMode {
        case .forYou:
            return "Nothing to recommend yet. As people post, the best of it shows up here -- and what you like teaches it what to pick."
        case .following:
            return "Posts from the people you follow show up here, newest first. Share a workout, a meal, or something off your calendar to start your own."
        case .discover:
            return "Posts from people you don't follow yet show up here. Search above to find somebody by name."
        }
    }

    /// What to say over the page after a save, and how to stop saying it.
    ///
    /// One binding over two outcomes, because they cannot both be new: a tap
    /// saves a workout or a meal, never both, and whichever landed last is
    /// the one worth reading. Clearing it clears both, so nothing is left
    /// behind to reappear the next time the other one fires.
    private var saveConfirmation: Binding<RepbaseToastPresentation?> {
        Binding(
            get: {
                if let workout = store.lastSavedWorkout {
                    return RepbaseToastPresentation(
                        title: workout.wasAlreadySaved
                            ? String(localized: "Workout already saved", bundle: .app, locale: .app)
                            : String(localized: "Workout saved", bundle: .app, locale: .app),
                        accessibilityMessage: workout.message,
                        actionTitle: String(localized: "View", bundle: .app, locale: .app, comment: "Toast button that opens the saved workout"),
                        destination: .workouts
                    )
                }
                if let meal = store.lastSavedMeal {
                    return RepbaseToastPresentation(
                        title: meal.wasAlreadySaved
                            ? String(localized: "Meal already saved", bundle: .app, locale: .app)
                            : String(localized: "Meal saved", bundle: .app, locale: .app),
                        accessibilityMessage: meal.message,
                        actionTitle: String(localized: "Log", bundle: .app, locale: .app, comment: "Toast button that opens Food to log the saved meal"),
                        destination: .food
                    )
                }
                return nil
            },
            set: { updated in
                guard updated == nil else { return }
                store.lastSavedWorkout = nil
                store.lastSavedMeal = nil
            }
        )
    }

    private func notice(
        _ message: String,
        symbol: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(timeOfDay.accent)
            Text(message)
            Spacer(minLength: 0)
        }
        .font(.community(.caption))
        .foregroundStyle(timeOfDay.canvasSecondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One post. The body is chosen by which snapshot came back rather than by
/// `kind`, so a post whose kind this build does not know still draws whatever
/// of it is recognisable.
struct PostCard: View {
    /// How much of the post this drawing is meant to show.
    ///
    /// One switch rather than two, because the two things it decides always
    /// move together. A feed wants the summary and the small photo; the
    /// post's own page wants everything and the picture as it was posted.
    enum Presentation {
        /// Name, the numbers worth scanning, and the card-sized photo.
        case feed
        /// The whole thing: the recipe under a meal, every exercise under a
        /// workout, and the photo at the size it was uploaded.
        case detail
    }

    @Environment(SocialStore.self) private var store

    let post: FeedPost
    let timeOfDay: HomeTimeOfDay
    /// Feed by default, because that is where most of these are drawn.
    var presentation: Presentation = .feed
    /// Opens the thread. Nil on the detail page, where the card is already
    /// the thing being read and must not push another copy of itself.
    var openComments: (() -> Void)?
    /// Opens the author's profile. Nil where there is nowhere to push to, or
    /// where the profile being read is already theirs.
    var openAuthor: ((Int) -> Void)?

    /// Set when Report was chosen, which raises the reasons.
    @State private var reportingPost: FeedPost?

    /// The shape the photo was posted at, once its bytes have arrived.
    ///
    /// Nil until then, and it cannot be otherwise: no dimensions travel with
    /// a post, so the card reserves `PostPhotoRatio.unloaded` and settles
    /// when the image lands.
    @State private var photoRatio: CGFloat?

    /// What is drawn: the original when this is a repost, itself otherwise.
    /// The engagement figures always come from `post`.
    private var shown: RepostedPost { post.displayed }

    var body: some View {
        VStack(spacing: 0) {
            if post.repostOf != nil {
                repostHeader
                    .padding(.horizontal, 70)
                    .padding(.top, 10)
            }

            // Who wrote it stays beside the avatar; what they posted does
            // not. Everything used to sit in the column right of a 36pt
            // avatar, so a photo had 64pt of margin on its left and 16pt on
            // its right and read as shoved off-centre. The picture, the
            // attachments and the actions now use the full width.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    authorAvatar
                        .contentShape(Circle())
                        .onTapGesture { openAuthor?(shown.author.id) }
                        .accessibilityAddTraits(openAuthor == nil ? [] : .isButton)

                    VStack(alignment: .leading, spacing: 10) {
                        authorLine

                        // Why For You picked it. Quiet: it explains the card,
                        // it is not the card. Feed only -- on the post's own
                        // page the question has already been answered.
                        if presentation == .feed, !post.viewerIsAuthor,
                           let recommendation = post.recommendation {
                            Text(recommendation.label)
                                .font(.community(.caption, weight: .semibold))
                                .foregroundStyle(timeOfDay.canvasSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, -6)
                        }

                    }
                }

                if !shown.caption.isEmpty {
                    Text(shown.caption)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = post.publicationMessage {
                    Label(message, systemImage: post.moderationStatus == "rejected" ? "exclamationmark.shield" : "clock")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if post.isPublished, let video = shown.video {
                    PostVideoView(postID: shown.id, video: video,
                                  canReplace: post.viewerIsAuthor && post.repostOf == nil)
                }

                if let imageURL = drawnPhotoURL(shown) {
                    photo(imageURL, meal: shown.meal)

                    if let workout = shown.workout {
                        compactWorkoutAttachment(workout, imageAttached: true)
                    } else if let meal = shown.meal {
                        // A meal with a photo used to stop here, at the photo
                        // and a Save button. The strip across the picture
                        // carries the name and the calories, so it looked
                        // complete in a feed -- but the macros were missing,
                        // and opening the post showed the same picture again
                        // with no ingredients and no recipe under it. Every
                        // meal post that had a photo, which is most of the
                        // ones worth reading.
                        compactMealAttachment(meal, imageAttached: true)
                    } else if let planner = shown.planner {
                        compactPlannerAttachment(planner)
                    }
                } else if let workout = shown.workout {
                    compactWorkoutAttachment(workout, imageAttached: false)
                } else if let meal = shown.meal {
                    compactMealAttachment(meal, imageAttached: false)
                } else if let planner = shown.planner {
                    compactPlannerAttachment(planner)
                } else {
                    unsupportedBody
                }

                if post.isPublished {
                    PostActionBar(post: post, timeOfDay: timeOfDay, openComments: openComments)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $reportingPost) { target in
            PostReportSheet(post: target, timeOfDay: timeOfDay)
        }
    }

    /// Who passed it on, above the post itself — so the name beside the
    /// avatar stays the person who actually trained.
    private var repostHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.community(size: 11, weight: .semibold))
            Text("\(post.author.displayName) reposted")
                .font(.community(.caption, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(timeOfDay.canvasSecondaryText)
    }

    /// The author's photo, above the numbers it was posted with.
    ///
    /// A failure draws nothing rather than a broken-image placeholder: the
    /// card's real content is the snapshot underneath, and it should still
    /// read cleanly when the picture cannot be fetched.
    /// The photo, at the shape it was posted at.
    ///
    /// It used to be a fixed 176pt band with the image cropped to fill it,
    /// which threw away what somebody framed: an upright plate of food
    /// arrived as a strip through its middle. The box now follows the photo,
    /// clamped by `PostPhotoRatio` so neither a panorama nor a screenshot
    /// can take the layout over.
    ///
    /// A clear shape sets the box and the image fills it, rather than the
    /// image sizing itself -- that keeps the placeholder, the failure mark
    /// and the photo all one shape, so nothing resizes as it swaps between
    /// them.
    /// Which URL this card should actually pull.
    ///
    /// Both fall back to the other, so a post with a picture always draws one
    /// whichever size was asked for — an older server that does not send the
    /// small copy still fills a feed, and a variant that was never made still
    /// fills a detail page.
    private func drawnPhotoURL(_ shown: RepostedPost) -> URL? {
        switch presentation {
        case .feed: return shown.feedImageURL ?? shown.imageURL
        case .detail: return shown.imageURL ?? shown.feedImageURL
        }
    }

    /// Whether this drawing shows what is inside the post, or only names it.
    private var showsContents: Bool { presentation == .detail }

    private func photo(_ url: URL, meal: PostMealSnapshot?) -> some View {
        Color.clear
            .aspectRatio(
                PostPhotoRatio.clamped(photoRatio ?? PostPhotoRatio.unloaded),
                contentMode: .fit
            )
            .overlay {
                RemoteImage(
                    url: url,
                    maxPixel: 1_200,
                    onNaturalSize: { size in
                        photoRatio = PostPhotoRatio.clamped(size)
                    }
                ) {
                    RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                        .fill(timeOfDay.primaryText.opacity(0.06))
                        .overlay { ProgressView() }
                } failure: {
                    // Says the photo is missing rather than drawing nothing.
                    // Nothing is indistinguishable from a post that never
                    // had one.
                    RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                        .fill(timeOfDay.primaryText.opacity(0.06))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.community(.title3))
                                .foregroundStyle(timeOfDay.secondaryText)
                        }
                }
                .scaledToFill()
            }
            .clipped()
        .overlay(alignment: .bottom) {
            if let meal {
                HStack(spacing: 6) {
                    Text(meal.name)
                    Text("·")
                    Text("\(meal.totalCalories.nutritionText) kcal")
                    Spacer(minLength: 0)
                }
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.black.opacity(0.82))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(timeOfDay.canvasBorder, lineWidth: 1)
        }
    }

    /// Whoever made the post being shown. On a repost that is the original
    /// author, not the person passing it on — they are named in the line
    /// above, and putting a reposter's name over someone else's training
    /// would credit them with it.
    private var authorLine: some View {
        HStack(spacing: 6) {
            // Four labels on one line, each held to it, which at the
            // accessibility sizes left "Aar... @a... - 1..." -- a byline that
            // no longer says who posted. Stacked, the name gets its own line
            // and the handle and age share the next.
            VStack(alignment: .leading, spacing: 3) {
                Text(shown.author.displayName)
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)

                // Deliberately a plain row: the handle, the separator and the
                // age are one phrase, and stacking them too would spend three
                // lines saying what one says.
                HStack(spacing: 6) {
                    Text(post.viewerIsAuthor && post.repostOf == nil
                         ? String(localized: "Your post", bundle: .app, locale: .app)
                         : "@" + shown.author.username)
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(timeOfDay.canvasSecondaryText)

                    Text(shown.displayDate, format: .relative(presentation: .numeric))
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openAuthor?(shown.author.id) }
            .accessibilityAddTraits(openAuthor == nil ? [] : .isButton)
            .accessibilityHint(openAuthor == nil ? "" : "Opens this person's profile")

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if post.visibility != .publicToAll {
                    Image(systemName: post.visibility.symbol)
                        .font(.community(size: 9, weight: .semibold))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                if post.viewerIsAuthor || post.offersModeration {
                    Menu {
                        if post.viewerIsAuthor {
                            Button(role: .destructive) {
                                store.delete(post)
                            } label: {
                                Label("Delete post", systemImage: "trash")
                            }
                        } else {
                            // Only on For You, the one list the server picks.
                            // Elsewhere a post is there because of who wrote it,
                            // and the answer to that is unfollowing.
                            if post.recommendation != nil {
                                // A toggle, so the menu shows the choice and
                                // is the way to take it back; the card stays.
                                Toggle(isOn: Binding(
                                    get: { store.wantedPostIDs.contains(post.id) },
                                    set: { more in
                                        Task { await store.setMoreLikeThis(more, post: post) }
                                    }
                                )) {
                                    Label("More like this", systemImage: "hand.thumbsup")
                                }
                                Button {
                                    Task { await store.setFewerLikeThis(true, post: post) }
                                } label: {
                                    Label("Fewer like this", systemImage: "hand.thumbsdown")
                                }
                                Button {
                                    Task { await store.setNotInterested(true, post: post) }
                                } label: {
                                    Label("Not interested", systemImage: "eye.slash")
                                }
                            }
                            // Report asks a question, so it opens a sheet.
                            // Block does not: it acts on the tap, the way
                            // every destructive control in this app does.
                            Button {
                                reportingPost = post
                            } label: {
                                Label("Report post", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                Task { await store.block(shown.author) }
                            } label: {
                                Label(
                                    "Block \(shown.author.displayName)",
                                    systemImage: "hand.raised"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.community(size: 14, weight: .semibold))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let photo = shown.author.photoURL, let url = URL(string: photo) {
            RemoteImage(url: url, maxPixel: 132) {
                avatarInitials
            } failure: {
                avatarInitials
            }
            .scaledToFill()
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            avatarInitials
        }
    }

    private var avatarInitials: some View {
        Text(shown.author.initials)
            .font(.community(.footnote, weight: .semibold))
            .foregroundStyle(timeOfDay.canvasPrimaryText)
            .frame(width: 44, height: 44)
            .background(SocialSearchStyle.softSurface, in: Circle())
    }

    // MARK: - Bodies

    private func compactWorkoutAttachment(
        _ workout: PostWorkoutSnapshot,
        imageAttached: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: imageAttached ? 0 : 8) {
            HStack(spacing: 8) {
                Text(workout.routeDistanceKm == nil ? "WORKOUT" : "RUN")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(timeOfDay.accent)

                // Always, photo or not. It used to be dropped whenever a
                // picture was attached, which left the card showing a shape
                // and two numbers and never saying which workout it was.
                Text(workout.title)
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if post.offersWorkoutToSave {
                    saveWorkoutButton
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.community(size: 10, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                }
            }

            // The work and the time it took, which is what a reader is
            // actually comparing against their own. Duration used to be
            // dropped whenever a photo was attached, for no reason beyond
            // the layout being written twice.
            HStack(spacing: 6) {
                Text(workoutSummary(workout))
                if let duration = workout.durationSeconds, duration > 0 {
                    Text("·")
                    Text(Self.duration(duration))
                }
            }
            .font(.community(.caption, weight: imageAttached ? .semibold : .regular))
            .foregroundStyle(timeOfDay.secondaryText)
            .padding(.top, imageAttached ? 5 : 0)

            // Every exercise and its sets, on the post's own page only. This
            // is what somebody opened the post to read: a card saying "6 sets"
            // does not say which six.
            if showsContents, !workout.exercises.isEmpty {
                Divider().padding(.vertical, 6)

                VStack(spacing: 8) {
                    ForEach(workout.exercises) { line in
                        HStack(spacing: 8) {
                            Text(line.name)
                                .font(.community(size: 12, weight: .semibold))
                                .foregroundStyle(timeOfDay.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // The same summary the post's expanded body uses,
                            // which already knows that a workout posted
                            // without weights says "4 × 5" and not "4 × 5 @ 0".
                            Text(Self.setSummary(line, showsWeights: post.showsWeights))
                                .font(.community(size: 11, weight: .semibold))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .layoutPriority(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, imageAttached ? 12 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func compactMealAttachment(
        _ meal: PostMealSnapshot,
        imageAttached: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Skipped when a photo is above: the strip across it already
            // carries the name and the calories, and saying them twice in
            // eighty points of card reads as a mistake.
            if !imageAttached {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MEAL")
                            .font(.community(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(RepbaseDesign.success)
                        Text(meal.name)
                            .font(.community(.subheadline, weight: .bold))
                            .foregroundStyle(timeOfDay.primaryText)
                    }
                    Spacer(minLength: 4)
                    Text("\(meal.totalCalories.nutritionText) kcal")
                        .font(.community(.subheadline, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                }
            }

            // The recipe, on the post's own page only.
            //
            // A feed is scanned: the name, the calories and three macros are
            // what somebody reads deciding whether to stop, and eight lines
            // of ingredients under every card push the next post off the
            // screen. Opening one is the moment somebody wants to cook it.
            if showsContents, !meal.entries.isEmpty {
                Divider().padding(.vertical, 2)

                Text("INGREDIENTS")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(RepbaseDesign.success)

                VStack(spacing: 6) {
                    ForEach(meal.entries) { line in
                        HStack(spacing: 8) {
                            Text(line.name)
                                .font(.community(size: 12, weight: .semibold))
                                .foregroundStyle(timeOfDay.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(servingsText(line.servings))
                                .font(.community(size: 11))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .layoutPriority(1)
                            Text("\(line.totalCalories.nutritionText) kcal")
                                .font(.community(size: 11, weight: .semibold))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .layoutPriority(1)
                        }
                    }
                }
            }

            if showsContents, !meal.cookingInstructions.isEmpty {
                Divider().padding(.vertical, 2)

                Text("HOW IT WAS MADE")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(RepbaseDesign.success)

                // Whatever the author typed, line breaks and all: a recipe is
                // a list of steps, and the steps are the line breaks.
                Text(meal.cookingInstructions)
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 14) {
                macro("\(meal.totalProteinGrams.nutritionText)g", "protein", RepbasePalette.caramel)
                macro("\(meal.totalCarbohydrateGrams.nutritionText)g", "carbs", Color(hex: 0x3F8C92))
                macro("\(meal.totalFatGrams.nutritionText)g", "fat", Color(hex: 0x9D5A8F))
                Spacer(minLength: 0)
                if post.offersMealToSave { saveMealButton }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(imageAttached ? Color.clear : RepbaseDesign.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func macro(_ value: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value).foregroundStyle(color)
            Text(label).foregroundStyle(timeOfDay.secondaryText)
        }
        .font(.community(size: 10, weight: .bold))
    }

    private func compactPlannerAttachment(_ planner: PostPlannerSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: planner.kind == "event" ? "calendar" : "checkmark.circle")
                .font(.community(size: 15, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(planner.title)
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
                Text([planner.scheduledDate, planner.scheduledTime].compactMap { $0 }.joined(separator: " · "))
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            Spacer(minLength: 0)

            if planner.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(RepbaseDesign.success)
            }
        }
        .padding(12)
        .background(timeOfDay.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func workoutSummary(_ workout: PostWorkoutSnapshot) -> LocalizedStringKey {
        if let distance = workout.routeDistanceKm {
            let miles = ImperialUnits.miles(fromKilometers: distance.nutritionDouble)
            return "\(String(format: "%.2f", miles)) mi · \(Self.pace(duration: workout.durationSeconds, miles: miles)) pace"
        }
        // The sets, not the exercise count. What a reader compares against
        // their own is how much work was done and how long it took; how many
        // movements it was spread over is detail for the page itself, where
        // every one of them is listed anyway.
        let sets = workout.totalSetCount
        return sets == 1 ? "1 working set" : "\(sets) working sets"
    }

    private func workoutBody(_ workout: PostWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            shareHeader(
                workout.routeDistanceKm == nil ? "Workout" : "Run",
                symbol: workout.routeDistanceKm == nil
                    ? ActivityIconKind.lifting.systemName
                    : ActivityIconKind.running.systemName
            )

            workoutStatistics(workout)

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, line in
                        HStack(spacing: 6) {
                            Text(line.name)
                                .font(.community(size: 13, weight: .medium))
                                .foregroundStyle(timeOfDay.primaryText)
                            Spacer(minLength: 6)
                            Text(Self.setSummary(line, showsWeights: post.showsWeights))
                                .font(.community(size: 12).monospacedDigit())
                                .foregroundStyle(timeOfDay.secondaryText)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(timeOfDay.accent)
                        .frame(width: 2)
                        .offset(x: -10)
                }
            }
        }
    }

    private func workoutStatistics(_ workout: PostWorkoutSnapshot) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let distance = workout.routeDistanceKm {
                let miles = ImperialUnits.miles(fromKilometers: distance.nutritionDouble)
                statistic(String(format: "%.2f", miles), "mi")
                statistic(Self.pace(duration: workout.durationSeconds, miles: miles), "pace")
                statistic(Self.duration(workout.durationSeconds), "time")
            } else {
                statistic("\(workout.exerciseCount)", "exercises")
                statistic("\(workout.totalSetCount)", "sets")
                statistic(Self.duration(workout.durationSeconds), "time")
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var postTitle: some View {
        if let workout = shown.workout {
            postTitleText(workout.title)
        } else if let meal = shown.meal {
            postTitleText(mealTitle(meal))
        } else if let planner = shown.planner {
            postTitleText(planner.title)
        }
    }

    /// "Meal 1 · Chicken Bowl · 800 kcal".
    ///
    /// A meal's own name is a slot · Meal 1, Meal 2 · which says when it
    /// was eaten and nothing about what was in it. So the title says the whole
    /// meal: what was in it and what it came to.
    ///
    /// Everything the card used to repeat underneath. The items were listed
    /// again below, and the calories again beside the macros, which meant a
    /// one-item meal stated itself three times.
    ///
    /// Every item, joined: the title wraps rather than truncating, so a long
    /// meal costs a second line instead of losing its ingredients.
    private func mealTitle(_ meal: PostMealSnapshot) -> String {
        var parts = [meal.name]
        let eaten = meal.entries.map(\.name).joined(separator: ", ")
        if !eaten.isEmpty { parts.append(eaten) }
        parts.append("\(meal.totalCalories.nutritionText) kcal")
        return parts.joined(separator: " · ")
    }

    private func postTitleText(_ text: String) -> some View {
        Text(text)
            .font(.community(size: 22, weight: .bold))
            .tracking(-0.35)
            .foregroundStyle(timeOfDay.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Takes the workout into your own. Offered only on somebody else's post:
    /// your own is already in your workouts.
    @ViewBuilder
    private var saveWorkoutButton: some View {
        saveChip(
            isSaving: store.isSavingWorkout(from: post.id),
            isSaved: post.viewerHasSaved,
            tint: timeOfDay.accent
        ) {
            await store.saveWorkout(from: post)
        }
    }

    private func mealBody(_ meal: PostMealSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            shareHeader("Meal", symbol: "fork.knife")

            // The macros only. Calories moved to the title, and repeating
            // them here was the same number twice on one card; the list of
            // items that used to sit under this said nothing the title does
            // not already say.
            HStack(alignment: .top, spacing: 0) {
                statistic("\(meal.totalProteinGrams.nutritionText)g", "protein")
                statistic("\(meal.totalCarbohydrateGrams.nutritionText)g", "carbs")
                statistic("\(meal.totalFatGrams.nutritionText)g", "fat")
            }
            .padding(.vertical, 10)
        }
    }

    private func plannerBody(_ planner: PostPlannerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            shareHeader(
                planner.kind == "event" ? "Event" : "Task",
                symbol: planner.kind == "event" ? "calendar" : "checkmark.circle"
            )

            VStack(alignment: .leading, spacing: 0) {
                plannerLine("Date", value: planner.scheduledDate)
                if let time = planner.scheduledTime {
                    plannerLine("Time", value: time.hasSuffix(":00") ? String(time.dropLast(3)) : time)
                }
                plannerLine("Category", value: planner.category)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(timeOfDay.accent)
                    .frame(width: 2)
                    .offset(x: -10)
            }

            if planner.isComplete {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(RepbaseDesign.success)
            }
        }
    }

    /// A post of a kind this build has never heard of. Drawn as a placeholder
    /// rather than skipped, so the feed does not silently go short.
    private var unsupportedBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
            Text("This post needs a newer version of Rytivo.")
            Spacer(minLength: 0)
        }
        .font(.community(.caption))
        .foregroundStyle(timeOfDay.secondaryText)
    }

    // MARK: - Pieces

    private func shareHeader(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.community(size: 10, weight: .bold))
                .tracking(1.15)
                .foregroundStyle(timeOfDay.accent)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            if post.offersWorkoutToSave {
                saveWorkoutButton
            }
            if post.offersMealToSave {
                saveMealButton
            }
        }
    }

    /// The meal equivalent of Save workout. A meal is worth keeping for the
    /// same reason a workout is: you want to eat it again without typing it
    /// back in food by food.
    private var saveMealButton: some View {
        saveChip(
            isSaving: store.isSavingMeal(from: post.id),
            isSaved: post.viewerHasSaved,
            tint: RepbaseDesign.success
        ) {
            await store.saveMeal(from: post)
        }
    }

    /// "Save", as a chip rather than a line of text with a glyph in front.
    ///
    /// It sits inside a card that already says MEAL or WORKOUT, so the noun
    /// was being read twice and the button was the longest thing on its row.
    /// A filled capsule also gives it an edge to aim at: bare label text
    /// hit-tests the glyphs, which is a smaller target than it looks.
    ///
    /// Tinted to the card it sits in, so the one green thing on a green card
    /// is the only control on it.
    private func saveChip(
        isSaving: Bool,
        isSaved: Bool,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        // Done, and drawn as done: a tick, the word, and the tint dropped to
        // the muted grey every other finished thing in the app uses. The
        // filled accent capsule reads as "press me", and pressing it again
        // could only ever answer that there was nothing to do.
        let done = isSaved && !isSaving
        let colour = done ? timeOfDay.secondaryText : tint

        return Button {
            Task { await action() }
        } label: {
            HStack(spacing: 5) {
                if isSaving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: done ? "checkmark" : "plus")
                        .font(.community(size: 10, weight: .bold))
                }
                Text(isSaving ? "Saving" : (done ? "Saved" : "Save"))
                    .font(.community(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(colour)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(colour.opacity(done ? 0.10 : 0.15)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSaving || done)
        // Says why it cannot be pressed, rather than only looking unpressable.
        .accessibilityHint(done ? "Already saved to your library" : "")
    }

    /// "1 serving", "2 servings" -- the amount, not just the food.
    private func servingsText(_ value: Decimal) -> LocalizedStringKey {
        let text = value.nutritionText
        return text == "1" ? "1 serving" : "\(text) servings"
    }

    private func statistic(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.community(size: 15, weight: .bold))
                .foregroundStyle(timeOfDay.primaryText)
            Text(label)
                .font(.community(size: 9, weight: .medium))
                .foregroundStyle(timeOfDay.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plannerLine(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(timeOfDay.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(timeOfDay.primaryText)
        }
        .font(.community(size: 13, weight: .medium))
        .padding(.vertical, 8)
    }

    private static func duration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let minutes = seconds / 60
        if minutes < 60 { return String(localized: "\(minutes)m", bundle: .app, locale: .app, comment: "A duration in minutes, abbreviated") }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private static func pace(duration: Int?, miles: Double) -> String {
        guard let duration, duration > 0, miles > 0 else { return "—" }
        let secondsPerMile = Int((Double(duration) / miles).rounded())
        return String(format: "%d:%02d", secondsPerMile / 60, secondsPerMile % 60)
    }

    /// Reps without a load still say something, so they are printed on their
    /// own rather than collapsing to a bare set count. Which is the point of
    /// posting without weights: "4 × 5" is what was done, and it is the load
    /// people hold back, not the count.
    private static func setSummary(
        _ line: PostExerciseLine,
        showsWeights: Bool
    ) -> String {
        guard let reps = line.topSetReps else { return String(localized: "\(line.setCount) sets", bundle: .app, locale: .app) }
        guard showsWeights, let weight = line.topSetWeightKg else {
            return "\(line.setCount) × \(reps)"
        }
        return "\(line.setCount) × \(reps) @ \(weight.nutritionText) kg"
    }
}
