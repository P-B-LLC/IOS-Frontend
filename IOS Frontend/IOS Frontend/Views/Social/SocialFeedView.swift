//
//  SocialFeedView.swift
//  IOS Frontend
//
//  What the people you follow have posted.
//

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
    private enum FeedMode: String, CaseIterable, Identifiable {
        case following = "Following"
        case discover = "Discover"
        var id: String { rawValue }
    }

    @Environment(SocialStore.self) private var store
    @Environment(SocialProfileStore.self) private var profileStore

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
    @State private var feedMode: FeedMode = .following
    @State private var searchText = ""
    /// Whose profile is open, if anyone's.
    @State private var visiting: VisitedPerson?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
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
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                modePicker(timeOfDay: timeOfDay)

                if feedMode == .discover {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(timeOfDay.accent)
                        TextField("Search people or posts", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .repbaseDepthSurface(cornerRadius: 18)

                    peopleSection(timeOfDay: timeOfDay)
                }

                if let message = store.errorMessage {
                    notice(message, symbol: "exclamationmark.triangle.fill", timeOfDay: timeOfDay)
                }

                // Said rather than assumed: the name a saved workout lands
                // under is not always the one on the post.
                if let saved = store.lastSavedWorkout {
                    notice(
                        saved.message,
                        symbol: "checkmark.circle.fill",
                        timeOfDay: timeOfDay
                    )
                    .onTapGesture { store.lastSavedWorkout = nil }
                }

                if let saved = store.lastSavedMeal {
                    notice(
                        saved.message,
                        symbol: "checkmark.circle.fill",
                        timeOfDay: timeOfDay
                    )
                    .onTapGesture { store.lastSavedMeal = nil }
                }

                // Reporting and blocking both act out of sight -- one goes to
                // a queue, the other quietly empties part of the feed -- so
                // both say so here rather than leaving the tap unanswered.
                if let message = store.lastModerationMessage {
                    notice(
                        message,
                        symbol: "checkmark.circle.fill",
                        timeOfDay: timeOfDay
                    )
                    .onTapGesture { store.lastModerationMessage = nil }
                }

                if isListLoading && displayedPosts.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if displayedPosts.isEmpty {
                    emptyState(timeOfDay: timeOfDay)
                } else {
                    ForEach(displayedPosts) { post in
                        // The card is not itself a button: the action bar
                        // inside it has four of its own, and a button holding
                        // buttons swallows their taps. A tap anywhere else
                        // opens the post.
                        PostCard(
                            post: post,
                            timeOfDay: timeOfDay,
                            // The button raises the threads over the feed so
                            // a comment can be left without losing your place
                            // in it; tapping the card itself opens the post.
                            openComments: { commenting = CommentedPost(id: post.id) },
                            openAuthor: { visiting = VisitedPerson(id: $0) }
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { opened = post.id }
                            .task {
                                // The last card asks for the next page as it
                                // comes into view, so the feed keeps going
                                // without a button to press.
                                if feedMode == .following, post.id == store.feed.last?.id {
                                    await store.loadMore()
                                }
                            }
                    }

                    if store.isLoadingMore {
                        ProgressView().padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 4)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
        .sheet(isPresented: $isComposing) {
            PostComposerView()
        }
        .sheet(item: $commenting) { target in
            PostCommentsSheet(postID: target.id, timeOfDay: timeOfDay)
        }
        .task(id: feedMode) {
            guard feedMode == .discover else { return }
            await store.loadDiscover()
            await store.loadPeople()
            if let viewerID = profileStore.viewerID {
                await store.loadRelationships(for: viewerID)
            }
        }
    }

    private func modePicker(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 26) {
            ForEach(FeedMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        feedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.community(size: 14, weight: .semibold))
                        .foregroundStyle(
                            feedMode == mode
                                ? timeOfDay.canvasPrimaryText
                                : timeOfDay.canvasSecondaryText
                        )
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(feedMode == mode ? timeOfDay.accent : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            // The feed's own header used to carry this, above a SOCIAL eyebrow
            // and a "Community" title that named the tab you had just pressed
            // to get here. The tabs were already a row; the button fits on it.
            Button {
                isComposing = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.community(size: 13, weight: .bold))
                    Text("Post")
                        .font(.community(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                // Under the tabs' own height, so the row does not grow and
                // push the underline off the divider it sits on.
                .frame(height: 34)
                .background(timeOfDay.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create post")
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func peopleSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PEOPLE")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(timeOfDay.accent)
                Spacer()
                Text("\(filteredPeople.count) found")
                    .font(.community(.caption2))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            .padding(.bottom, 8)

            ForEach(Array(filteredPeople.prefix(8).enumerated()), id: \.element.id) { index, person in
                HStack(spacing: 12) {
                    Circle()
                        .fill(timeOfDay.accent.opacity(0.12))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Text(person.initials)
                                .font(.community(.caption, weight: .bold))
                                .foregroundStyle(timeOfDay.accent)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.community(.subheadline, weight: .semibold))
                        Text("@\(person.username)")
                            .font(.community(.caption))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }
                    Spacer()
                        // The gap is part of the row, so the whole line opens
                        // the profile rather than just the name.
                        .contentShape(Rectangle())
                    if person.id != profileStore.viewerID {
                        Button(isFollowing(person) ? "Following" : "Follow") {
                            Task {
                                await store.setFollowing(
                                    !isFollowing(person),
                                    user: person,
                                    viewerID: profileStore.viewerID
                                )
                            }
                        }
                        .font(.community(.caption, weight: .bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(store.changingFollowFor.contains(person.id))
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                // Not a Button wrapping the row: it holds the Follow button,
                // and a button inside a button swallows the inner tap.
                .onTapGesture { visiting = VisitedPerson(id: person.id) }
                if index < min(filteredPeople.count, 8) - 1 { Divider() }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var filteredPeople: [PostAuthor] {
        let viewerID = profileStore.viewerID
        let available = store.people.filter { $0.id != viewerID }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        return available.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    private func isFollowing(_ person: PostAuthor) -> Bool {
        guard let viewerID = profileStore.viewerID else { return false }
        return store.followingByUser[viewerID]?.contains(where: { $0.id == person.id }) == true
    }

    private var isListLoading: Bool {
        feedMode == .discover ? store.isLoadingDiscover : store.isLoading
    }

    /// What the list shows: the people you follow, or everybody.
    ///
    /// Discover reads its own list rather than filtering the feed. The feed is
    /// deliberately only the people you follow, so filtering it could never
    /// surface a stranger — which is the entire point of Discover.
    private var displayedPosts: [FeedPost] {
        guard feedMode == .discover else { return store.feed }
        let everyone = store.discoverPosts
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return everyone }
        return everyone.filter { post in
            let shown = post.displayed
            return shown.author.displayName.lowercased().contains(query)
                || shown.author.username.lowercased().contains(query)
                || shown.caption.lowercased().contains(query)
                || shown.workout?.title.lowercased().contains(query) == true
                || shown.meal?.name.lowercased().contains(query) == true
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

    private func emptyState(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.community(size: 30, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
            Text("Nothing here yet")
                .font(.community(.headline))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("Posts from people you follow show up here. Share a workout, a meal, or something off your calendar to start your own.")
                .font(.community(.subheadline))
                .multilineTextAlignment(.center)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Repeats the header's button where the eye already is. An empty
            // feed is exactly when the one in the corner goes unnoticed.
            Button("Write a post") { isComposing = true }
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 22)
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
    @Environment(SocialStore.self) private var store

    let post: FeedPost
    let timeOfDay: HomeTimeOfDay
    /// Opens the thread. Nil on the detail page, where the card is already
    /// the thing being read and must not push another copy of itself.
    var openComments: (() -> Void)?
    /// Opens the author's profile. Nil where there is nowhere to push to, or
    /// where the profile being read is already theirs.
    var openAuthor: ((Int) -> Void)?

    /// Set when Report was chosen, which raises the reasons.
    @State private var reportingPost: FeedPost?

    /// What is drawn: the original when this is a repost, itself otherwise.
    /// The engagement figures always come from `post`.
    private var shown: RepostedPost { post.displayed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if post.repostOf != nil {
                repostHeader
            }

            author

            postTitle

            if let imageURL = shown.imageURL {
                photo(imageURL)
            }

            if let workout = shown.workout {
                workoutBody(workout)
            } else if let meal = shown.meal {
                mealBody(meal)
            } else if let planner = shown.planner {
                plannerBody(planner)
            } else {
                unsupportedBody
            }

            // Above the buttons, not below them. The caption is the last
            // thing the poster said about the post, so it belongs with the
            // post; the action row is where the post stops and what a reader
            // can do about it starts.
            if !shown.caption.isEmpty {
                Text(shown.caption)
                    .font(.community(size: 14))
                    .foregroundStyle(timeOfDay.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PostActionBar(post: post, timeOfDay: timeOfDay, openComments: openComments)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $reportingPost) { target in
            PostReportSheet(post: target, timeOfDay: timeOfDay)
        }
        // The only rule on a card, and it is between cards rather than inside
        // one. A post used to be ruled off internally -- above and below its
        // numbers, between every exercise or ingredient -- which chopped one
        // thing into five and left nothing saying where the post itself
        // ended. Spacing groups it now; the line only says "next post".
        .overlay(alignment: .bottom) { Divider() }
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
    private func photo(_ url: URL) -> some View {
        RemoteImage(url: url, maxPixel: 1_200) {
            // The card keeps its shape while the photo arrives, so the rows
            // under it do not jump once it does.
            RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                .fill(timeOfDay.primaryText.opacity(0.06))
                .overlay { ProgressView() }
        } failure: {
            // Says the photo is missing rather than drawing nothing. Nothing
            // is indistinguishable from a post that never had one.
            RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                .fill(timeOfDay.primaryText.opacity(0.06))
                .overlay {
                    Image(systemName: "photo")
                        .font(.community(.title3))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
        }
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Whoever made the post being shown. On a repost that is the original
    /// author, not the person passing it on — they are named in the line
    /// above, and putting a reposter's name over someone else's training
    /// would credit them with it.
    private var author: some View {
        HStack(spacing: 10) {
            // The avatar and the name together are the way to the person.
            // Not a Button around the row: the row ends in the timestamp and
            // the card itself opens the post, so only the identity is theirs.
            HStack(spacing: 10) {
                authorAvatar

                VStack(alignment: .leading, spacing: 1) {
                    Text(shown.author.displayName)
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                    Text("@" + shown.author.username)
                        .font(.community(.caption2))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openAuthor?(shown.author.id) }
            .accessibilityAddTraits(openAuthor == nil ? [] : .isButton)
            .accessibilityHint(openAuthor == nil ? "" : "Opens this person's profile")

            Spacer()

            HStack(spacing: 9) {
                Text(shown.createdAt, format: .relative(presentation: .named))
                    .font(.community(.caption2))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
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
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let photo = shown.author.photoURL, let url = URL(string: photo) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                avatarInitials
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarInitials
        }
    }

    private var avatarInitials: some View {
        Text(shown.author.initials)
            .font(.community(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 36, height: 36)
            .background(timeOfDay.accent, in: Circle())
    }

    // MARK: - Bodies

    private func workoutBody(_ workout: PostWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            shareHeader(
                workout.routeDistanceKm == nil ? "Workout" : "Run",
                symbol: workout.routeDistanceKm == nil ? "dumbbell.fill" : "figure.run"
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
        let isSaving = store.isSavingWorkout(from: post.id)
        Button {
            Task { await store.saveWorkout(from: post) }
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.community(size: 12, weight: .semibold))
                }
                Text("Save workout")
                    .font(.community(.caption, weight: .semibold))
            }
            .foregroundStyle(timeOfDay.accent)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
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
            Text("This post needs a newer version of Repbase.")
            Spacer(minLength: 0)
        }
        .font(.community(.caption))
        .foregroundStyle(timeOfDay.secondaryText)
    }

    // MARK: - Pieces

    private func shareHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.community(size: 10, weight: .bold))
                .tracking(1.15)
                .foregroundStyle(timeOfDay.accent)
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
        let isSaving = store.isSavingMeal(from: post.id)
        return Button {
            Task { await store.saveMeal(from: post) }
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.community(size: 12, weight: .semibold))
                }
                Text("Save meal")
                    .font(.community(.caption, weight: .semibold))
            }
            .foregroundStyle(timeOfDay.accent)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func statistic(_ value: String, _ label: String) -> some View {
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

    private func plannerLine(_ label: String, value: String) -> some View {
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
        if minutes < 60 { return "\(minutes)m" }
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
        guard let reps = line.topSetReps else { return "\(line.setCount) sets" }
        guard showsWeights, let weight = line.topSetWeightKg else {
            return "\(line.setCount) × \(reps)"
        }
        return "\(line.setCount) × \(reps) @ \(weight.nutritionText) kg"
    }
}
