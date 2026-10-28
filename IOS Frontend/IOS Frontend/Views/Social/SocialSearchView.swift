import SwiftUI

/// The approved soft search surface, adapted to the app's dark appearance.
enum SocialSearchStyle {
    static let softSurface = Color.repbaseDynamic(
        light: Color(hex: 0xFFF2E9), dark: Color(hex: 0x302720)
    )
}

/// Shared by the compact trigger and expanded text field. Native glass adapts
/// to light/dark appearance; accessibility preferences get an opaque surface.
struct SocialSearchGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(.secondarySystemBackground), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            content.glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}

/// Search is independent of the three feeds. Closing it leaves the selected
/// feed and its scroll position intact; all results still use the normal
/// post/profile navigation and server visibility rules.
struct SocialSearchView: View {
    private struct Request: Equatable {
        let query: String
        let connected: Bool
        let retry: Int
    }
    private struct PersonDestination: Hashable { let id: Int }
    private struct CommentDestination: Identifiable { let id: Int }

    @Environment(SocialStore.self) private var store
    @Environment(SocialProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var scope: SocialSearchScope
    @State private var retry = 0
    @State private var openedPost: Int?
    @State private var openedPerson: PersonDestination?
    @State private var comments: CommentDestination?
    @State private var actionFeedback: String?
    @State private var didFocusOnPresentation = false
    @FocusState private var isQueryFocused: Bool
    private let theme = HomeTimeOfDay.current

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
        _scope = State(initialValue: SocialSearchPolicy.preferredScope(
            for: initialQuery, previousQuery: "", currentScope: .people
        ))
    }

    private var normalizedQuery: String { SocialSearchPolicy.normalizedQuery(query) }
    private var hasCurrentResults: Bool { store.searchQuery == normalizedQuery }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    results
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 14) {
                    queryField
                    scopePicker
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Search")
                        .font(.community(.title, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isQueryFocused = false
                        store.clearSearch()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close search")
                }
            }
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .homeTimeScreen(theme)
            .navigationDestination(item: $openedPost) { id in
                PostDetailView(postID: id)
            }
            .navigationDestination(item: $openedPerson) { person in
                PersonProfileView(userID: person.id)
            }
            .sheet(item: $comments) { target in
                PostCommentsSheet(postID: target.id, timeOfDay: theme)
            }
            // Results retain the normal post actions. A save, report, follow
            // failure or block must still answer the tap inside this modal.
            .safeAreaInset(edge: .bottom) {
                if let message = actionFeedback {
                    HStack(spacing: 8) {
                        Text(message).font(.community(.footnote))
                        Spacer(minLength: 0)
                        Button {
                            actionFeedback = nil
                        } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss message")
                    }
                    .foregroundStyle(theme.canvasPrimaryText)
                    .padding(.leading, 16)
                    .background(SocialSearchStyle.softSurface, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .task(id: message) {
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        actionFeedback = nil
                    }
                }
            }
            .onChange(of: store.errorMessage) { _, message in
                if let message { actionFeedback = message }
            }
            .onChange(of: store.lastModerationMessage) { _, message in
                if let message { actionFeedback = message }
            }
            .onChange(of: store.lastSavedWorkout?.message) { _, message in
                if let message { actionFeedback = message }
            }
            .onChange(of: store.lastSavedMeal?.message) { _, message in
                if let message { actionFeedback = message }
            }
            .task(id: Request(query: normalizedQuery, connected: store.isConnected, retry: retry)) {
                // Invalidate the old response before the debounce window, so
                // a slow previous query cannot appear beneath the new text.
                store.clearSearch()
                guard store.isConnected, !normalizedQuery.isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                await store.search(normalizedQuery)
            }
            .onChange(of: query) { old, new in
                scope = SocialSearchPolicy.preferredScope(
                    for: new, previousQuery: old, currentScope: scope
                )
            }
            .onChange(of: store.isConnected) { _, connected in
                guard !connected else { return }
                actionFeedback = nil
                isQueryFocused = false
                query = ""
                openedPost = nil
                openedPerson = nil
                comments = nil
                dismiss()
            }
            .task {
                // Focus once when the expanded field is mounted. Returning
                // from a profile/post must not unexpectedly raise a keyboard.
                guard !didFocusOnPresentation else { return }
                didFocusOnPresentation = true
                isQueryFocused = query.isEmpty
            }
        }
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.community(.headline))
            TextField("Name, @handle or #hashtag", text: $query)
                .font(.community(.callout, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isQueryFocused)
                .onSubmit { isQueryFocused = false }
                .accessibilityIdentifier("social.search.query")
            if !query.isEmpty {
                Button {
                    query = ""
                    store.clearSearch()
                    isQueryFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.canvasSecondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(theme.canvasPrimaryText)
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 4)
        .frame(minHeight: 48)
        .modifier(SocialSearchGlass())
    }

    private var scopePicker: some View {
        HStack(spacing: 8) {
            ForEach(SocialSearchScope.allCases) { option in
                Button {
                    scope = option
                } label: {
                    Text(scopeTitle(option))
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(scope == option ? theme.onPrimaryAction : theme.canvasSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(scope == option ? theme.primaryActionSurface : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope == option ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder private var results: some View {
        if normalizedQuery.isEmpty {
            explanation("Find your people. Find your inspiration.",
                        detail: "Search a name or @handle to find someone, or a #hashtag to explore posts.")
        } else if !store.isConnected {
            explanation("Search is unavailable", detail: "Check your connection or sign in again, then retry.")
        } else if !hasCurrentResults || store.isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        } else if let error = store.searchErrorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn’t complete this search")
                    .font(.community(.headline, weight: .bold))
                Text(error).font(.community(.subheadline))
                    .foregroundStyle(theme.canvasSecondaryText)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            Button("Retry search") { retry += 1 }
                .buttonStyle(.bordered)
                .padding(.horizontal, RepbaseDesign.pageInset)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(resultHeading)
                    .font(.community(.headline, weight: .bold))
                    .foregroundStyle(theme.canvasPrimaryText)
                Text(resultHint)
                    .font(.community(.footnote))
                    .foregroundStyle(theme.canvasSecondaryText)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)

            if scope == .people {
                if store.searchedPeople.isEmpty {
                    explanation("No people found", detail: "Try a different name or @handle, or look in Posts.")
                } else {
                    ForEach(store.searchedPeople, id: \.id) { person in
                        personRow(person)
                    }
                }
            } else if store.searchedPosts.isEmpty {
                explanation("No posts found", detail: "Try another hashtag or a word from the post.")
            } else {
                ForEach(store.searchedPosts) { post in
                    PostCard(post: post, timeOfDay: theme,
                             openComments: { comments = CommentDestination(id: post.id) },
                             openAuthor: { openedPerson = PersonDestination(id: $0) })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isQueryFocused = false
                            openedPost = post.id
                        }
                }
            }
        }
    }

    private var resultHeading: LocalizedStringKey {
        switch scope {
        case .people: "People matching \(normalizedQuery)"
        case .posts: "Posts matching \(normalizedQuery)"
        }
    }

    private var resultHint: LocalizedStringKey {
        scope == .posts ? "Find people by name or @handle, too." : "Try Posts to explore a #hashtag or words from a post."
    }

    private func scopeTitle(_ scope: SocialSearchScope) -> LocalizedStringKey {
        switch scope {
        case .people: "People"
        case .posts: "Posts"
        }
    }

    private func explanation(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.community(.headline, weight: .bold))
                .foregroundStyle(theme.canvasPrimaryText)
            Text(detail).font(.community(.subheadline))
                .foregroundStyle(theme.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 16)
    }

    private func personRow(_ person: PostAuthor) -> some View {
        HStack(spacing: 12) {
            Button {
                isQueryFocused = false
                openedPerson = PersonDestination(id: person.id)
            } label: {
                HStack(spacing: 12) {
                    Text(person.initials)
                        .font(.community(.footnote, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(SocialSearchStyle.softSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.displayName).font(.community(.subheadline, weight: .bold))
                        Text("@\(person.username)").font(.community(.caption))
                            .foregroundStyle(theme.canvasSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(theme.canvasPrimaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this person's profile")

            if person.id != profileStore.viewerID {
                Button {
                    Task {
                        await store.setFollowing(!isFollowing(person), user: person, viewerID: profileStore.viewerID)
                    }
                } label: {
                    Text(followTitle(person))
                        .font(.community(.caption, weight: .semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(store.changingFollowFor.contains(person.id) || store.requestedUserIDs.contains(person.id))
            }
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 4)
    }

    private func isFollowing(_ person: PostAuthor) -> Bool {
        guard let viewerID = profileStore.viewerID else { return false }
        return store.followingByUser[viewerID]?.contains(where: { $0.id == person.id }) == true
    }

    private func followTitle(_ person: PostAuthor) -> LocalizedStringKey {
        if isFollowing(person) { return "Following" }
        return store.requestedUserIDs.contains(person.id) ? "Requested" : "Follow"
    }
}
