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
                header(timeOfDay: timeOfDay)
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

                if store.isLoading && store.feed.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if store.feed.isEmpty {
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
                            openComments: { commenting = CommentedPost(id: post.id) }
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
            .padding(.top, 16)
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
            await store.loadPeople()
            if let viewerID = profileStore.viewerID {
                await store.loadRelationships(for: viewerID)
            }
        }
    }

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RepbaseScreenHeader(
                eyebrow: "SOCIAL",
                title: "Your community"
            )

            Button {
                feedMode = .discover
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(timeOfDay.accent)
            .accessibilityLabel("Discover people and posts")
        }
        .padding(.bottom, 2)
    }

    private func modePicker(timeOfDay: HomeTimeOfDay) -> some View {
        Picker("Feed", selection: $feedMode) {
            ForEach(FeedMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(3)
        .repbaseInsetSurface(cornerRadius: 16)
        .tint(RepbaseDesign.ink)
    }

    private func peopleSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PEOPLE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(timeOfDay.accent)
                Spacer()
                Text("\(filteredPeople.count) found")
                    .font(.caption2)
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
                                .font(.caption.weight(.bold))
                                .foregroundStyle(timeOfDay.accent)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.subheadline.weight(.semibold))
                        Text("@\(person.username)")
                            .font(.caption)
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }
                    Spacer()
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
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(store.changingFollowFor.contains(person.id))
                    }
                }
                .padding(.vertical, 10)
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

    private var displayedPosts: [FeedPost] {
        guard feedMode == .discover else { return store.feed }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.feed }
        return store.feed.filter { post in
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
                .font(.system(size: 16, weight: .semibold))
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
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("Posts from people you follow show up here. Share a workout, a meal, or something off your calendar to start your own.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Repeats the header's button where the eye already is. An empty
            // feed is exactly when the one in the corner goes unnoticed.
            Button("Write a post") { isComposing = true }
                .font(.subheadline.weight(.semibold))
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
        .font(.caption)
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

    /// What is drawn: the original when this is a repost, itself otherwise.
    /// The engagement figures always come from `post`.
    private var shown: RepostedPost { post.displayed }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if post.repostOf != nil {
                repostHeader
            }

            author

            if let imageURL = shown.imageURL {
                photo(imageURL)
            }

            if !shown.caption.isEmpty {
                Text(shown.caption)
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
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

            PostActionBar(post: post, timeOfDay: timeOfDay, openComments: openComments)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Who passed it on, above the post itself — so the name beside the
    /// avatar stays the person who actually trained.
    private var repostHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 11, weight: .semibold))
            Text("\(post.author.displayName) reposted")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(timeOfDay.secondaryText)
    }

    /// The author's photo, above the numbers it was posted with.
    ///
    /// A failure draws nothing rather than a broken-image placeholder: the
    /// card's real content is the snapshot underneath, and it should still
    /// read cleanly when the picture cannot be fetched.
    private func photo(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius))
    }

    /// Whoever made the post being shown. On a repost that is the original
    /// author, not the person passing it on — they are named in the line
    /// above, and putting a reposter's name over someone else's training
    /// would credit them with it.
    private var author: some View {
        HStack(spacing: 10) {
            Text(shown.author.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(timeOfDay.accent, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(shown.author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                Text("@" + shown.author.username)
                    .font(.caption2)
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shown.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(timeOfDay.secondaryText)
                if post.visibility != .publicToAll {
                    Image(systemName: post.visibility.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
        }
    }

    // MARK: - Bodies

    private func workoutBody(_ workout: PostWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            kindLabel("Workout", symbol: "dumbbell.fill")

            Text(workout.title)
                .font(.headline)
                .foregroundStyle(timeOfDay.primaryText)

            HStack(spacing: 16) {
                statistic("\(workout.exerciseCount)", "exercises")
                statistic("\(workout.totalSetCount)", "sets")
                if let volume = workout.totalVolumeKg {
                    statistic(volume.nutritionText, "kg lifted")
                }
                if let distance = workout.routeDistanceKm {
                    statistic(
                        String(
                            format: "%.2f",
                            ImperialUnits.miles(fromKilometers: distance.nutritionDouble)
                        ),
                        "mi"
                    )
                }
            }

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workout.exercises.prefix(4)) { line in
                        HStack(spacing: 6) {
                            Text(line.name)
                                .font(.caption)
                                .foregroundStyle(timeOfDay.primaryText)
                            Spacer(minLength: 6)
                            Text(Self.setSummary(line))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(timeOfDay.secondaryText)
                        }
                    }
                    if workout.exercises.count > 4 {
                        Text("+\(workout.exercises.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }
                .padding(.top, 2)
            }

            if post.offersWorkoutToSave {
                saveWorkoutButton
            }
        }
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
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("Save workout")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(timeOfDay.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(timeOfDay.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .padding(.top, 4)
    }

    private func mealBody(_ meal: PostMealSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            kindLabel("Meal", symbol: "fork.knife")

            Text(meal.name)
                .font(.headline)
                .foregroundStyle(timeOfDay.primaryText)

            HStack(spacing: 16) {
                statistic(meal.totalCalories.nutritionText, "kcal")
                statistic("\(meal.totalProteinGrams.nutritionText)g", "protein")
                statistic("\(meal.totalCarbohydrateGrams.nutritionText)g", "carbs")
                statistic("\(meal.totalFatGrams.nutritionText)g", "fat")
            }

            if !meal.entries.isEmpty {
                Text(meal.entries.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func plannerBody(_ planner: PostPlannerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            kindLabel(planner.kind == "event" ? "Event" : "Task", symbol: "checklist")

            Text(planner.title)
                .font(.headline)
                .foregroundStyle(timeOfDay.primaryText)

            HStack(spacing: 8) {
                Text(planner.scheduledDate)
                if let time = planner.scheduledTime {
                    Text(time.hasSuffix(":00") ? String(time.dropLast(3)) : time)
                }
                if planner.isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(timeOfDay.secondaryText)
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
        .font(.caption)
        .foregroundStyle(timeOfDay.secondaryText)
    }

    // MARK: - Pieces

    private func kindLabel(_ title: String, symbol: String) -> some View {
        Label(title.uppercased(), systemImage: symbol)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(timeOfDay.accent)
    }

    private func statistic(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(timeOfDay.primaryText)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    /// Reps without a load still say something, so they are printed on their
    /// own rather than collapsing to a bare set count. Which is the point of
    /// posting without weights: "4 × 5" is what was done, and it is the load
    /// people hold back, not the count.
    private static func setSummary(_ line: PostExerciseLine) -> String {
        guard let reps = line.topSetReps else { return "\(line.setCount) sets" }
        guard let weight = line.topSetWeightKg else {
            return "\(line.setCount) × \(reps)"
        }
        return "\(line.setCount) × \(reps) @ \(weight.nutritionText) kg"
    }
}
