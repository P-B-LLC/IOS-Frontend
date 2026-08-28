//
//  SocialProfileView.swift
//  IOS Frontend
//
//  Profile onboarding and the public-facing athlete profile.
//

import CoreLocation
import PhotosUI
import SwiftUI
import UserNotifications

struct ProfileDestinationView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(AuthenticationStore.self) private var authentication

    var body: some View {
        if let profile = store.profile {
            SocialProfileView(profile: profile)
        } else if store.isLoading || !store.hasLoadedProfile {
            ProgressView("Loading profile from Repbase…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(store.errorMessage ?? "Repbase could not load this profile.")
            } actions: {
                if let token = authentication.token {
                    Button("Retry") {
                        Task {
                            await store.connect(
                                configuration: authentication.configuration,
                                token: token
                            )
                        }
                    }
                }
            }
        }
    }
}

/// A post id that can be presented as a sheet. `sheet(item:)` wants
/// Identifiable, and a bare Int is not.
private struct ProfileCommentTarget: Identifiable, Hashable {
    let id: Int
}

struct SocialProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(SocialProfileStore.self) private var store
    /// The feed's store, because the posts on this page are the same posts:
    /// liking one here has to be the like the feed shows.
    @Environment(SocialStore.self) private var social

    let profile: SocialProfile
    var isCurrentUser = true
    @State private var selectedSection: ProfileSection = .posts
    @State private var editingProfile = false
    @State private var showingSettings = false
#if DEBUG
    // Settings is two taps in and simctl has no tap, which is why the
    // appearance picker on it could not be checked from here.
    private let opensSettingsOnLaunch =
        ProcessInfo.processInfo.environment["REPBASE_SETTINGS"] != nil
#endif
    @State private var isFollowing = false
    /// The post whose comments are raised over the profile, if any.
    @State private var commenting: ProfileCommentTarget?
    @State private var editingExpression = false

    /// Whose profile this is. Every count, list and request on the page is
    /// keyed off it rather than off the signed-in user, which is what makes
    /// the same screen serve somebody else's profile.
    private var subjectID: Int? { profile.id ?? store.viewerID }

    /// Whether the signed-in user follows whoever this profile belongs to.
    ///
    /// Derived rather than stored, so it is right the moment the page opens
    /// and stays right when the same follow is changed from Discover.
    private var viewerFollowsSubject: Bool {
        guard let viewerID = store.viewerID, let subjectID else { return false }
        return social.followingByUser[viewerID]?
            .contains { $0.id == subjectID } == true
    }

    /// The signed-in user's own following list, which the Follow button reads.
    /// A function rather than an inline optional map: `Optional.map` cannot
    /// host an await.
    private func loadViewerRelationships() async {
        guard let viewerID = store.viewerID else { return }
        await social.loadRelationships(for: viewerID)
    }

    /// The subject in the shape the follow call wants.
    private var subjectAsAuthor: PostAuthor? {
        guard let subjectID else { return nil }
        return PostAuthor(
            id: subjectID,
            username: profile.username,
            firstName: profile.firstName,
            lastName: profile.lastName,
            photoURL: profile.profilePhotoURL
        )
    }

    private enum ProfileSection: String, CaseIterable, Identifiable {
        case posts = "Posts"
        case about = "About"
        var id: String { rawValue }
    }

    private struct AboutMetric: Identifiable {
        let title: String
        let value: String
        let badge: String?

        var id: String { title }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(spacing: 16) {
                    profileHeader(timeOfDay: timeOfDay)
                    identityCard(timeOfDay: timeOfDay)
                    sectionPicker(timeOfDay: timeOfDay)

                    if selectedSection == .posts {
                        postsSection(timeOfDay: timeOfDay)
                    } else {
                        aboutSection(timeOfDay: timeOfDay)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 4)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .minimizesBottomBarOnScroll()
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
            .fullScreenCover(isPresented: $editingProfile) {
                NavigationStack {
                    ProfileOnboardingView(seed: profile, isEditing: true)
                        .environment(store)
                }
            }
            .fullScreenCover(isPresented: $showingSettings) {
                ProfileSettingsView(profile: profile)
            }
#if DEBUG
            .task {
                if opensSettingsOnLaunch { showingSettings = true }
            }
#endif
            .fullScreenCover(isPresented: $editingExpression) {
                NavigationStack {
                    ProfileExpressionEditorView()
                }
            }
        }
        // Out here, not inside the TimelineView, which tears its contents down
        // on every tick.
        //
        // Keyed on the feed store's connection as well as the id. The stores
        // connect in order and the profile's is first, so this page is already
        // on screen — id and all — while the feed store still has no
        // repository, and a task keyed on the id alone ran once against
        // nothing and never again.
        .task(id: "\(subjectID ?? 0)-\(social.isConnected)") {
            guard let subjectID, social.isConnected else { return }
            async let posts: Void = social.loadPosts(byAuthor: subjectID)
            async let relationships: Void = social.loadRelationships(for: subjectID)
            // The viewer's own list too, which is what the Follow button reads.
            // Without it the button says "Follow" for somebody already followed.
            async let mine: Void = loadViewerRelationships()
            // Somebody else's featured lifts are their own request; the
            // signed-in user's arrive with their profile.
            async let lifts: Void = isCurrentUser
                ? ()
                : store.loadHighlights(forUser: subjectID)
            _ = await (posts, relationships, lifts, mine)
        }
    }

    /// Your own profile is a place in the app; somebody else's is somewhere you
    /// navigated to. So only the second one gets a header, carrying the name
    /// of whoever you are looking at and the way back to where you came from.
    /// Your own needs neither.
    @ViewBuilder
    private func profileHeader(timeOfDay: HomeTimeOfDay) -> some View {
        // Nothing for your own profile: the settings button sits on the name's
        // line now, and there is nothing else a header would have carried.
        if !isCurrentUser {
            HStack(alignment: .center, spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.community(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 2) {
                    Text("PROFILE")
                        .font(.community(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(timeOfDay.accent)
                    Text("@\(profile.username)")
                        .font(.community(.title3, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    /// The way into Settings, and all that is left of the old header.
    ///
    /// That header carried an ACCOUNT eyebrow over a 30pt "Profile" title,
    /// which spent the top of the page announcing the name of the tab you had
    /// just pressed to get here -- and pushed the person's own face a third of
    /// the way down the screen to do it. The avatar and the name already say
    /// whose page this is. With the title gone the row held one button, so the
    /// button moved to the name's line and the row went too.
    private func settingsButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.community(size: 18, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 44, height: 44)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and app settings")
    }

    private func identityCard(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                ProfileAvatarView(profile: profile, size: 78, timeOfDay: timeOfDay)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(profile.displayName)
                            .font(.community(.title2, weight: .bold))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if isCurrentUser {
                            settingsButton(timeOfDay: timeOfDay)
                        }
                    }

                    Text("@\(profile.username)")
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)

                    Text("\(myPostCount) posts   ·   \(followerCount) followers   ·   \(followingCount) following")
                        .font(.community(size: 11, weight: .semibold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !visibleSocialLinks.isEmpty {
                socialLinksRow(timeOfDay: timeOfDay)
            }

            if let gym = profile.gym {
                Text((gym.city.isEmpty ? gym.name : "\(gym.name) · \(gym.city)").uppercased())
                    .font(.community(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(timeOfDay.accent)
                    .lineLimit(1)
            } else if let discipline = primaryDiscipline {
                Text(discipline.uppercased())
                    .font(.community(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(timeOfDay.accent)
            }

            profileAction(timeOfDay: timeOfDay)
                .padding(.top, 4)

            // Now a separator between the identity and the sections below,
            // rather than a lid the action was tucked under.
            Rectangle()
                .fill(timeOfDay.border)
                .frame(height: 1)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    private var primaryDiscipline: String? {
        profile.disciplines
            .sorted { $0.rawValue < $1.rawValue }
            .first?.rawValue
    }

    private var visibleSocialLinks: [ProfileSocialLink] {
        profile.socialLinks ?? []
    }

    private func socialLinksRow(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(visibleSocialLinks) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        Label(link.platform.title, systemImage: link.platform.systemImage)
                            .font(.community(.footnote, weight: .semibold))
                            .foregroundStyle(timeOfDay.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens \(link.platform.title) outside Repbase")
                }
            }
        }
    }

    private var myPostCount: Int {
        subjectID.map { social.posts(byAuthor: $0).count } ?? 0
    }

    private var followerCount: Int {
        subjectID.flatMap { social.followersByUser[$0]?.count } ?? 0
    }

    private var followingCount: Int {
        subjectID.flatMap { social.followingByUser[$0]?.count } ?? 0
    }

    @ViewBuilder
    private func profileAction(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 8) {
            Group {
                if isCurrentUser {
                    Button { editingProfile = true } label: {
                        profilePrimaryActionLabel("Edit profile", timeOfDay: timeOfDay)
                    }
                } else {
                    Button {
                        guard let author = subjectAsAuthor else { return }
                        Task {
                            await social.setFollowing(
                                !viewerFollowsSubject,
                                user: author,
                                viewerID: store.viewerID
                            )
                        }
                    } label: {
                        profilePrimaryActionLabel(
                            viewerFollowsSubject ? "Following" : "Follow",
                            timeOfDay: timeOfDay
                        )
                    }
                    .disabled(subjectAsAuthor.map { social.changingFollowFor.contains($0.id) } ?? true)
                }
            }
            .buttonStyle(.plain)

            ShareLink(item: "Meet \(profile.displayName) (@\(profile.username)) on Repbase.") {
                Text("Share")
                    .font(.community(.footnote, weight: .bold))
                    .foregroundStyle(timeOfDay.accent)
                    .frame(minWidth: 68, minHeight: 36)
                    .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(timeOfDay.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func profilePrimaryActionLabel(
        _ title: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.community(.footnote, weight: .bold))
            Text("→")
                .font(.community(.subheadline, weight: .bold))
        }
        .foregroundStyle(timeOfDay.onPrimaryAction)
        .frame(minWidth: 132, minHeight: 36)
        .background(timeOfDay.primaryActionSurface, in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 11))
    }

    private func profileStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
            Text(label.uppercased())
                .font(.community(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionPicker(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 0) {
            ForEach(ProfileSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 9) {
                        Text(section.rawValue.uppercased())
                            .font(
                                .community(
                                    .caption,
                                    weight: selectedSection == section ? .bold : .semibold
                                )
                            )
                            .tracking(0.6)
                            .foregroundStyle(
                                selectedSection == section
                                    ? timeOfDay.accent
                                    : timeOfDay.secondaryText
                            )

                        // A rail under every tab, not a bar under one. The bar
                        // alone said which section was open; it said nothing
                        // about the other one being openable. Running the line
                        // under both makes it a track the accent moves along,
                        // which is the whole hint -- no chrome, no chevron.
                        Capsule()
                            .fill(
                                selectedSection == section
                                    ? timeOfDay.accent
                                    : timeOfDay.border
                            )
                            .frame(height: 2)
                    }
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile section")
    }

    /// The user's own posts, drawn by the same card the feed uses.
    ///
    /// Read out of `SocialStore` rather than kept here: it is the same post,
    /// and a like made on this page has to be the like the feed shows. Two
    /// copies each keeping their own counts is the bug this avoids.
    @ViewBuilder
    private func postsSection(timeOfDay: HomeTimeOfDay) -> some View {
        let mine = subjectID.map { social.posts(byAuthor: $0) } ?? []
        let isLoading = subjectID.map { social.isLoadingPosts(byAuthor: $0) } ?? false

        Group {
            if !mine.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(mine) { post in
                        PostCard(
                            post: post,
                            timeOfDay: timeOfDay,
                            openComments: { commenting = ProfileCommentTarget(id: post.id) }
                        )
                    }
                }
                .padding(.horizontal, 15)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.community(size: 30, weight: .medium))
                        .foregroundStyle(timeOfDay.accent)
                    Text("No posts yet").font(.community(.headline))
                    Text("Completed workouts and shared milestones will appear here.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(timeOfDay.border).frame(height: 1)
                }
            }
        }
        .sheet(item: $commenting) { target in
            PostCommentsSheet(postID: target.id, timeOfDay: timeOfDay)
        }
    }


    /// Everything the public is shown about this person, in one place.
    ///
    /// Identity first, then the measurements, because how someone trains and
    /// where is what a stranger reads a profile for; the numbers are detail
    /// underneath it, and are each behind their own switch besides.
    /// What this person has written and what they have chosen to show.
    ///
    /// Read from the store rather than the profile because both are loaded
    /// separately from it: prompts are three rows that ride along on a public
    /// profile, and highlights cost a look through the set history, so each
    /// has its own request. Only the signed-in user's are wired so far -- a
    /// visited profile has no id on it to key another person's by.
    private var myPrompts: [ProfilePromptAnswer] {
        // The signed-in user's come from the store, which loads them on
        // connect; somebody else's ride along on their public profile.
        isCurrentUser ? store.prompts : profile.prompts
    }

    private var myHighlights: [HighlightLift] {
        if isCurrentUser { return store.highlights }
        return subjectID.flatMap { store.highlightsByUser[$0] } ?? []
    }

    private func aboutSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if !myPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(myPrompts) { prompt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.questionLabel.uppercased())
                                .font(.community(size: 9, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(timeOfDay.accent)
                            Text(prompt.answer)
                                .font(.community(size: 18, weight: .semibold))
                                .foregroundStyle(timeOfDay.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !myHighlights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(myHighlights) { lift in
                        highlightRow(lift, timeOfDay: timeOfDay)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !trainingIdentityMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TRAINING IDENTITY")
                        .font(.community(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(timeOfDay.accent)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 18
                    ) {
                        ForEach(trainingIdentityMetrics) { metric in
                            aboutMetric(metric, timeOfDay: timeOfDay)
                        }
                    }
                }
            }

            if isAboutEmpty && myPrompts.isEmpty && myHighlights.isEmpty {
                Text(
                    isCurrentUser
                        ? "Nothing here yet. Add a prompt or feature a lift so people know who they are following."
                        : "This athlete hasn't shared anything about themselves yet."
                )
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(28)
            }

            if isCurrentUser {
                Button {
                    editingExpression = true
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shape your profile")
                                .font(.community(.subheadline, weight: .bold))
                                .foregroundStyle(timeOfDay.primaryText)
                            Text("Prompts, lifts and training details")
                                .font(.community(.caption2))
                                .foregroundStyle(timeOfDay.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Text("→")
                            .font(.community(.title3, weight: .bold))
                            .foregroundStyle(timeOfDay.accent)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(
                        Color.repbaseDynamic(
                            light: RepbasePalette.sage.opacity(0.20),
                            dark: RepbasePalette.sage.opacity(0.18)
                        ),

                        in: RoundedRectangle(cornerRadius: 18)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 18)
    }

    private var trainingIdentityMetrics: [AboutMetric] {
        var metrics: [AboutMetric] = []
        if !profile.disciplines.isEmpty {
            metrics.append(AboutMetric(title: "TRAINS AS", value: fullDisciplineSummary, badge: nil))
        }
        if let gym = profile.gym {
            metrics.append(
                AboutMetric(
                    title: "GYM",
                    value: gym.city.isEmpty ? gym.name : "\(gym.name) · \(gym.city)",
                    badge: isCurrentUser ? nil : "Same gym"
                )
            )
        }
        if profile.showsHeight {
            metrics.append(
                AboutMetric(
                    title: "HEIGHT",
                    value: "\(profile.heightFeet)′ \(profile.heightInches)″",
                    badge: nil
                )
            )
        }
        if profile.showsWeight || profile.showsTargetWeight {
            let current = profile.showsWeight ? "\(profile.weightPounds) lb" : "Private"
            let goal = profile.showsTargetWeight ? "\(profile.targetWeightPounds) lb" : "Private"
            metrics.append(AboutMetric(title: "WEIGHT · GOAL", value: "\(current)  →  \(goal)", badge: nil))
        }
        return metrics
    }

    private func aboutMetric(_ metric: AboutMetric, timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.community(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(timeOfDay.secondaryText)
                if let badge = metric.badge {
                    Text(badge.uppercased())
                        .font(.community(size: 7, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                }
            }
            Text(metric.value)
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(timeOfDay.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// True only when there is nothing at all to show. The old copy blamed
    /// private measurements, which read as secretive on a profile that had
    /// simply never been filled in.
    private var isAboutEmpty: Bool {
        profile.disciplines.isEmpty
            && profile.gym == nil
            && !profile.showsHeight
            && !profile.showsWeight
            && !profile.showsTargetWeight
    }

    /// Every discipline, not the first two. The header had to stay to one
    /// line; a row in a list does not.
    private var fullDisciplineSummary: String {
        Array(profile.disciplines)
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: " · ")
    }

    /// One featured lift. The set is the evidence, so it is the biggest thing
    /// in the row; the estimate is smaller beside it, because it is a
    /// calculation rather than something that happened.
    ///
    /// A typed number says so. It is the whole reason the server sends a
    /// source: a figure nobody logged must not read like one that was.
    private func highlightRow(
        _ lift: HighlightLift,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FEATURED LIFT")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(timeOfDay.accent)
                Spacer()
                Text(liftSourceLabel(lift))
                    .font(.community(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lift.label)
                        .font(.community(.title3, weight: .bold))
                        .foregroundStyle(timeOfDay.primaryText)
                    if let estimate = lift.estimatedOneRepMaxPounds {
                        Text("Estimated 1RM · \(estimate) lb")
                            .font(.community(.caption2))
                            .foregroundStyle(timeOfDay.secondaryText)
                    } else if let name = lift.exerciseName {
                        Text(name)
                            .font(.community(.caption2))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }

                Spacer(minLength: 8)

                if let pounds = lift.displayPounds, let reps = lift.reps {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(pounds)")
                            .font(.community(size: 30, weight: .bold, design: .rounded))
                        Text("lb × \(reps)")
                            .font(.community(.subheadline, weight: .bold))
                    }
                    .foregroundStyle(timeOfDay.primaryText)
                } else {
                    Text("Nothing logged yet")
                        .font(.community(.caption, weight: .medium))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
        }
        .padding(16)
        .background(
            Color.repbaseDynamic(
                light: RepbasePalette.caramel.opacity(0.08),
                dark: RepbasePalette.caramel.opacity(0.09)
            ),

            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
    }

    private func liftSourceLabel(_ lift: HighlightLift) -> String {
        switch lift.source {
        case .logged: "FROM YOUR LOG"
        case .manual: "ENTERED BY HAND"
        case .none: "SELECTED"
        }
    }

    private func aboutRow(
        _ title: String,
        value: String,
        symbol: String,
        badge: String? = nil,
        timeOfDay: HomeTimeOfDay? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(RepbasePalette.caramel).frame(width: 28)
            Text(title).font(.community(.subheadline))
            Spacer()
            if let badge, let timeOfDay {
                Text(badge)
                    .font(.community(.caption2, weight: .bold))
                    .foregroundStyle(timeOfDay.accent)
            }
            Text(value)
                .font(.community(.subheadline, weight: .bold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 15)
    }
}

/// The hamburger menu leads here instead of scattering account-wide controls
/// across the profile. Every row uses an existing app action or destination.
private struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage(RepbaseAppearancePreference.storageKey)
    private var appearanceRawValue = RepbaseAppearancePreference.light.rawValue

    let profile: SocialProfile
    @State private var editorDestination: ProfileEditorDestination?
    @State private var showingPersonalization = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var securityMessage: String?
    @State private var legalDocument: LegalDocument?
#if DEBUG
    // The section editors are three taps in and simctl has no tap.
    private let editSectionOnLaunch = ProcessInfo.processInfo
        .environment["REPBASE_EDIT_SECTION"].flatMap(Int.init)
    // As is the personalization flow, one screen further again.
    private let opensPersonalizationOnLaunch =
        ProcessInfo.processInfo.environment["REPBASE_PERSONALIZATION"] != nil
#endif

    private enum ProfileEditorDestination: Int, Identifiable {
        case basics = 1
        case goals = 2
        case identity = 3
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let timeOfDay = HomeTimeOfDay(date: context.date)

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        settingsHeader(timeOfDay: timeOfDay)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("APP SETTINGS")
                                .font(.community(size: 10, weight: .bold))
                                .tracking(1.3)
                                .foregroundStyle(timeOfDay.accent)
                            Text("Everything in one place.")
                                .font(.community(size: 34, weight: .bold))
                            Text("Manage your public identity, nutrition targets, workout data, and account.")
                                .font(.community(.subheadline))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        settingsSection("PROFILE", timeOfDay: timeOfDay) {
                            VStack(spacing: 0) {
                                Button { editorDestination = .basics } label: {
                                    settingsRow(
                                        "Profile details",
                                        detail: "Name, username, and bio",
                                        symbol: "person.crop.circle"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                NavigationLink {
                                    SocialLinksEditorView()
                                } label: {
                                    settingsRow(
                                        "Social links",
                                        detail: "The accounts shown on your profile",
                                        symbol: "link"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                Button { editorDestination = .goals } label: {
                                    settingsRow(
                                        "Body goals & privacy",
                                        detail: "Height, weight, target weight, and visibility",
                                        symbol: "scope"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                Button { editorDestination = .identity } label: {
                                    settingsActivityRow(
                                        "Training identity",
                                        detail: "Photo, disciplines, and gym",
                                        icon: .lifting
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        settingsSection("PERSONALIZATION", timeOfDay: timeOfDay) {
                            Button { showingPersonalization = true } label: {
                                settingsRow(
                                    "Your Repbase",
                                    detail: "Training types, weekly goal, and what home leads with",
                                    symbol: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        settingsSection("APPEARANCE", timeOfDay: timeOfDay) {
                            Picker("Appearance", selection: $appearanceRawValue) {
                                ForEach(RepbaseAppearancePreference.allCases) { appearance in
                                    Label(appearance.title, systemImage: appearance.symbol)
                                        .tag(appearance.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 14)
                            .accessibilityHint("Changes the appearance throughout Repbase")
                        }

                        settingsSection("PRIVACY & PERMISSIONS", timeOfDay: timeOfDay) {
                            VStack(spacing: 0) {
                                // Blocking acts on one tap from a post, with
                                // nothing to confirm. This is the way back
                                // from a tap that was not meant.
                                NavigationLink {
                                    BlockedAccountsView()
                                } label: {
                                    settingsRow(
                                        "Blocked accounts",
                                        detail: "People you cannot see, and who cannot see you",
                                        symbol: "hand.raised"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                NavigationLink {
                                    AppleHealthConnectionView()
                                } label: {
                                    settingsRow(
                                        "Apple Health",
                                        detail: "Steps and completed workout imports",
                                        symbol: "heart.text.square"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                NavigationLink {
                                    NotificationPreferencesView()
                                } label: {
                                    settingsRow(
                                        "Notifications",
                                        detail: "Training, nutrition, and community updates",
                                        symbol: "bell"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                NavigationLink {
                                    PrivacyAndPermissionsView()
                                } label: {
                                    settingsRow(
                                        "Privacy & permissions",
                                        detail: "Location, photos, and how Repbase uses data",
                                        symbol: "hand.raised"
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                Button {
                                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                    openURL(url)
                                } label: {
                                    settingsRow(
                                        "Open iOS settings",
                                        detail: "Change Repbase system permissions",
                                        symbol: "gearshape"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        settingsSection("FOOD", timeOfDay: timeOfDay) {
                            NavigationLink {
                                NutritionGoalsView()
                            } label: {
                                settingsRow(
                                    "Nutrition goals",
                                    detail: "Calories, protein, carbohydrates, and fat",
                                    symbol: "fork.knife"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        settingsSection("WORKOUTS", timeOfDay: timeOfDay) {
                            Button { workoutStore.retryPersistence() } label: {
                                settingsRow(
                                    "Refresh workout data",
                                    detail: "Sync the latest plans and sessions",
                                    symbol: "arrow.clockwise"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        settingsSection("ACCOUNT", timeOfDay: timeOfDay) {
                            VStack(spacing: 0) {
                                Button {
                                    Task {
                                        do {
                                            try await authentication.rotateSessionToken()
                                            securityMessage = "Your saved account credential was replaced. You are still signed in on this device."
                                        } catch {
                                            deleteError = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    settingsRow(
                                        "Refresh account security",
                                        detail: "Replace the credential saved on this device",
                                        symbol: "key.horizontal",
                                        color: timeOfDay.accent
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                Button(role: .destructive) {
                                    Task { await authentication.signOut() }
                                } label: {
                                    settingsRow(
                                        "Sign out",
                                        detail: "End this Repbase session",
                                        symbol: "rectangle.portrait.and.arrow.right",
                                        color: .red
                                    )
                                }
                                .buttonStyle(.plain)

                                Rectangle().fill(timeOfDay.border).frame(height: 1)

                                Button(role: .destructive) {
                                    showingDeleteConfirmation = true
                                } label: {
                                    settingsRow(
                                        "Delete account",
                                        detail: "Permanently delete your account and its data",
                                        symbol: "trash",
                                        color: .red
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .disabled(authentication.isWorking)
                        }

                        settingsSection("ABOUT", timeOfDay: timeOfDay) {
                            VStack(spacing: 0) {
                                ForEach(LegalDocuments.all) { document in
                                    Button {
                                        legalDocument = document
                                    } label: {
                                        settingsRow(
                                            document.title,
                                            detail: document.summary,
                                            symbol: document.symbol
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Rectangle().fill(timeOfDay.border).frame(height: 1)
                                }

                                settingsValueRow(
                                    "Repbase version",
                                    value: versionLabel,
                                    symbol: "info.circle"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .toolbar(.hidden, for: .navigationBar)
                .homeTimeScreen(timeOfDay)
            }
        }
#if DEBUG
        .task {
            if let step = editSectionOnLaunch {
                editorDestination = ProfileEditorDestination(rawValue: step)
            }
            if opensPersonalizationOnLaunch { showingPersonalization = true }
        }
#endif
        .fullScreenCover(item: $editorDestination) { destination in
            NavigationStack {
                ProfileOnboardingView(
                    seed: profile,
                    isEditing: true,
                    initialStep: destination.rawValue
                )
                    .environment(store)
            }
        }
        .fullScreenCover(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(document: document)
            }
        }
        .fullScreenCover(isPresented: $showingPersonalization) {
            RepbaseOnboardingView {
                showingPersonalization = false
            }
        }
        .confirmationDialog(
            "Delete your Repbase account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account and Data", role: .destructive) {
                Task {
                    do {
                        try await authentication.deleteAccount()
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your profile and all associated Repbase data. This cannot be undone.")
        }
        .alert("Account Request Could Not Be Completed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "Please try again.")
        }
        .alert("Account Security Updated", isPresented: Binding(
            get: { securityMessage != nil },
            set: { if !$0 { securityMessage = nil } }
        )) {
            Button("Done", role: .cancel) { securityMessage = nil }
        } message: {
            Text(securityMessage ?? "Your account security was updated.")
        }
        // Settings is its own presentation, and a colour scheme reaches the
        // nearest enclosing one and stops. Set on the app root it recoloured
        // the profile behind this screen and left this screen alone -- so the
        // picker moved, nothing else did, and the only way to see that the
        // toggle had worked was to close Settings. Applied here it lands on
        // the screen the toggle is on, which is the one place it has to.
        .preferredColorScheme(appearance.colorScheme)
    }

    private var appearance: RepbaseAppearancePreference {
        RepbaseAppearancePreference(rawValue: appearanceRawValue) ?? .light
    }

    private func settingsHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Text("Settings")
                .font(.community(.headline, weight: .bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.community(size: 17, weight: .semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        timeOfDay: HomeTimeOfDay,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.community(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(timeOfDay.accent)
                .padding(.bottom, 10)

            Rectangle().fill(timeOfDay.border).frame(height: 1)
            content()
            Rectangle().fill(timeOfDay.border).frame(height: 1)
        }
    }

    private func settingsRow(
        _ title: String,
        detail: String,
        symbol: String,
        color: Color? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.community(size: 17, weight: .semibold))
                .foregroundStyle(color ?? RepbasePalette.caramel)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.community(.headline))
                    .foregroundStyle(color ?? .primary)
                Text(detail)
                    .font(.community(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(color ?? .secondary)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func settingsActivityRow(
        _ title: String,
        detail: String,
        icon: ActivityIconKind
    ) -> some View {
        HStack(spacing: 14) {
            ActivityIconArtwork(
                kind: icon,
                size: 21,
                color: RepbasePalette.caramel
            )
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.community(.headline))
                Text(detail).font(.community(.caption)).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func settingsValueRow(
        _ title: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.community(size: 17, weight: .semibold))
                .foregroundStyle(RepbasePalette.caramel)
                .frame(width: 28)
            Text(title)
                .font(.community(.headline))
            Spacer()
            Text(value)
                .font(.community(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct PrivacyAndPermissionsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(ActivityStore.self) private var activity
    /// Held rather than made on each read. `CLLocationManager.authorizationStatus`
    /// without parentheses is the class method itself, not the status it
    /// returns, so this was a `() -> CLAuthorizationStatus` and the switch
    /// below had nothing it could match.
    @State private var locationManager = CLLocationManager()
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRIVACY & PERMISSIONS")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text("You stay in control.")
                            .font(.community(size: 32, weight: .bold))
                        Text("Repbase asks for access only when a feature needs it. You can change access at any time in iOS Settings.")
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }

                    permissionExplanation(
                        "Location",
                        detail: "Used only during a route workout you start, to map distance and pace.",
                        symbol: "location",
                        status: locationLabel
                    )
                    permissionExplanation(
                        "Photos",
                        detail: "Used when you choose a profile photo. Repbase does not browse your library in the background.",
                        symbol: "photo",
                        status: "Selected items only"
                    )
                    permissionExplanation(
                        "Apple Health",
                        detail: "Read-only access to steps and completed workouts. Repbase never writes to Health.",
                        symbol: "heart.text.square",
                        status: activity.hasAskedHealth ? "Access requested" : "Not connected"
                    )
                    permissionExplanation(
                        "Notifications",
                        detail: "Used only for reminders you enable in Repbase.",
                        symbol: "bell",
                        status: notificationLabel
                    )
                    permissionExplanation(
                        "Your data",
                        detail: "Profile, workout, planner, and nutrition data are stored with your Repbase account so they sync across sessions.",
                        symbol: "lock.shield",
                        status: "Account protected"
                    )

                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open iOS Settings", systemImage: "arrow.up.right")
                            .font(.community(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(timeOfDay.accent)
                }
                .padding(22)
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
            .task { await refreshPermissionStatus() }
        }
    }

    private func permissionExplanation(_ title: String, detail: String, symbol: String, status: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.community(size: 18, weight: .semibold))
                .foregroundStyle(RepbasePalette.caramel)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.community(.headline))
                    Spacer()
                    Text(status).font(.community(.caption2, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text(detail).font(.community(.subheadline)).foregroundStyle(.secondary)
            }
        }
    }

    private var locationLabel: String {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Allowed"
        case .denied, .restricted: return "Off"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    private var notificationLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Off"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    private func refreshPermissionStatus() async {
        locationStatus = locationManager.authorizationStatus
        notificationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }
}

struct ProfileOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialProfileStore.self) private var store
    @Environment(AuthenticationStore.self) private var authentication

    let isEditing: Bool
    @State private var draft: SocialProfile
    @State private var step: Int
    /// Only used when creating: an account already exists when editing.
    @State private var email = ""
    @State private var password = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var gymSearch = ""
    @State private var gymResults: [GymIdentity] = []
    @State private var isCreatingGym = false
    @State private var newGymName = ""
    @State private var newGymCity = ""
    @State private var newGymCountry = ""

    /// Editing one section rather than walking the whole profile.
    ///
    /// Settings offers the sections as separate rows, which is a promise that
    /// picking one of them changes that one thing. It did not keep it: every
    /// row opened the same three-step flow at a different page and then made
    /// you press Continue through the rest to reach a Save. Changing a
    /// username meant being asked again about your target weight.
    ///
    /// Passing a step means that step and nothing else. Creating an account
    /// passes none, and still walks all four.
    private let editsOneSection: Bool

    init(seed: SocialProfile, isEditing: Bool = false, initialStep: Int? = nil) {
        self.isEditing = isEditing
        self.editsOneSection = isEditing && initialStep != nil
        _draft = State(initialValue: seed)
        _step = State(initialValue: initialStep ?? (isEditing ? 1 : 0))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            VStack(spacing: 0) {
                onboardingHeader(timeOfDay: timeOfDay)
                stepProgress(timeOfDay: timeOfDay)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        stepHeading
                        stepContent(timeOfDay: timeOfDay)

                        if let error = store.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.community(.footnote))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)

                bottomAction(timeOfDay: timeOfDay)
            }
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { draft.profileImageData = data }
                    }
                }
            }
            .task(id: gymSearch) {
                let query = gymSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    gymResults = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                gymResults = await store.searchGyms(query)
            }
        }
    }

    private func onboardingHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Button {
                if !editsOneSection, step > (isEditing ? 1 : 0) {
                    withAnimation(.easeOut(duration: 0.2)) { step -= 1 }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: canGoBack ? "chevron.left" : "xmark")
            }
            .buttonStyle(RepbaseSculptedIconButtonStyle(timeOfDay: timeOfDay))

            Spacer()
            Text(sectionTitle)
                .font(.community(.headline, weight: .bold))
                .lineLimit(1)
            Spacer()
            // A count of one is not worth printing, and neither is the page
            // number of a page you did not arrive at by turning.
            if editsOneSection {
                Color.clear.frame(width: 44, height: 44)
            } else {
                Text("\(step - firstStep + 1)/\(stepCount)")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func stepProgress(timeOfDay: HomeTimeOfDay) -> some View {
        if !editsOneSection {
            HStack(spacing: 6) {
                ForEach(firstStep..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? timeOfDay.accent : timeOfDay.surfaceRaised)
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 15)
        }
    }

    private var firstStep: Int { isEditing ? 1 : 0 }
    private var stepCount: Int { 4 - firstStep }

    /// The back arrow means a page to go back to. On a single section there
    /// is none, so it is a close.
    private var canGoBack: Bool {
        !editsOneSection && step > (isEditing ? 1 : 0)
    }

    /// What this screen is for, said at the top.
    ///
    /// "Edit Profile" is right for a walk through all of it and wrong for one
    /// section: somebody who tapped Body goals should see that they are in
    /// body goals.
    private var sectionTitle: String {
        guard editsOneSection else {
            return isEditing ? "Edit Profile" : "Create Profile"
        }
        switch step {
        case 1: return "Profile Details"
        case 2: return "Body Goals"
        default: return "Training Identity"
        }
    }

    @ViewBuilder
    private var stepHeading: some View {
        switch step {
        case 0:
            heading("Create your login", detail: "This is how you’ll get back into Repbase.")
        case 1:
            heading("What should we call you?", detail: "Your name and username identify you across Repbase.")
        case 2:
            heading("Set your goals", detail: "Keep these private or choose exactly what appears publicly.")
        default:
            heading("Build your identity", detail: "Show people how you train and where you belong.")
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.community(size: 29, weight: .bold, design: .rounded))
            Text(detail).font(.community(.subheadline)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepContent(timeOfDay: HomeTimeOfDay) -> some View {
        switch step {
        case 0: providerStep(timeOfDay: timeOfDay)
        case 1: nameStep(timeOfDay: timeOfDay)
        case 2: goalsStep(timeOfDay: timeOfDay)
        default: identityStep(timeOfDay: timeOfDay)
        }
    }

    /// Where the account itself is created.
    ///
    /// Apple and Google are what this page is meant to be, but neither can
    /// work until the app has an Apple Developer membership and a Google
    /// client id, and these builds carry no entitlements at all. An email and
    /// a password make an account that works today; a provider can be linked
    /// to the same account once those exist.
    private func providerStep(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(13)
                .repbaseControlSurface(cornerRadius: 12)

            SecureField("Password", text: $password)
                .textContentType(.newPassword)
                .padding(13)
                .repbaseControlSurface(cornerRadius: 12)

            Text("Use at least 8 characters.")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = authentication.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.community(.footnote))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Label(
                "Signing in with Apple or Google is coming. Your account will link to one when it does.",
                systemImage: "lock.fill"
            )
            .font(.community(.caption))
            .foregroundStyle(timeOfDay.secondaryText)
            .padding(.top, 8)
        }
    }

    private func providerButton(
        _ provider: ConnectedAccountProvider,
        symbol: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        Button {
            draft.provider = provider
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.community(.title3))
                Text("Continue with \(provider.title)").font(.community(.headline))
                Spacer()
                Image(systemName: draft.provider == provider ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.provider == provider ? timeOfDay.accent : timeOfDay.secondaryText)
            }
            .padding(.horizontal, 18)
            .frame(height: 62)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(draft.provider == provider ? timeOfDay.accent : timeOfDay.border, lineWidth: draft.provider == provider ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func nameStep(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 13) {
            profileField("First name", text: $draft.firstName, contentType: .givenName, timeOfDay: timeOfDay)
            profileField("Last name", text: $draft.lastName, contentType: .familyName, timeOfDay: timeOfDay)

            VStack(alignment: .leading, spacing: 7) {
                Text("Username").font(.community(.caption, weight: .semibold)).foregroundStyle(timeOfDay.secondaryText)
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(timeOfDay.accent).font(.community(.headline))
                    TextField("username", text: $draft.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                }
                .padding(.horizontal, 15)
                .frame(height: 54)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 17))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Bio (optional)").font(.community(.caption, weight: .semibold)).foregroundStyle(timeOfDay.secondaryText)
                TextField("What are you training for?", text: $draft.bio, axis: .vertical)
                    .lineLimit(3...4)
                    .padding(15)
                    .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 17))
            }
        }
    }

    private func profileField(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.community(.caption, weight: .semibold)).foregroundStyle(timeOfDay.secondaryText)
            TextField(title, text: text)
                .textContentType(contentType)
                .padding(.horizontal, 15)
                .frame(height: 54)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 17))
        }
    }

    private func goalsStep(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 13) {
            measurementCard("Height", symbol: "ruler", timeOfDay: timeOfDay) {
                HStack(spacing: 8) {
                    measurementInput(value: $draft.heightFeet, unit: "ft", timeOfDay: timeOfDay)
                    measurementInput(value: $draft.heightInches, unit: "in", timeOfDay: timeOfDay)
                }
            } privacy: {
                Toggle("Show on profile", isOn: $draft.showsHeight).tint(timeOfDay.accent)
            }

            measurementCard("Current weight", symbol: "scalemass", timeOfDay: timeOfDay) {
                measurementInput(value: $draft.weightPounds, unit: "lb", timeOfDay: timeOfDay)
            } privacy: {
                Toggle("Show on profile", isOn: $draft.showsWeight).tint(timeOfDay.accent)
            }

            measurementCard("Target weight", symbol: "scope", timeOfDay: timeOfDay) {
                measurementInput(value: $draft.targetWeightPounds, unit: "lb", timeOfDay: timeOfDay)
            } privacy: {
                Toggle("Show on profile", isOn: $draft.showsTargetWeight).tint(timeOfDay.accent)
            }

            Label("Private measurements still support your personal goals and progress.", systemImage: "eye.slash.fill")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private func measurementCard<Content: View, Privacy: View>(
        _ title: String,
        symbol: String,
        timeOfDay: HomeTimeOfDay,
        @ViewBuilder content: () -> Content,
        @ViewBuilder privacy: () -> Privacy
    ) -> some View {
        VStack(spacing: 14) {
            HStack {
                Label(title, systemImage: symbol).font(.community(.headline))
                Spacer()
                content()
            }
            Divider()
            privacy()
                .font(.community(.subheadline, weight: .medium))
        }
        .padding(17)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(timeOfDay.border, lineWidth: 1) }
    }

    private func measurementInput(value: Binding<Int>, unit: String, timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 42)
            Text(unit).font(.community(.caption)).foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(timeOfDay.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func identityStep(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ProfileAvatarView(profile: draft, size: 78, timeOfDay: timeOfDay)
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                            .font(.community(.subheadline, weight: .bold))
                    }
                    Button("Set it later") { draft.profileImageData = nil }
                        .font(.community(.caption, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How do you train?").font(.community(.headline))
                Text("Choose all that fit.").font(.community(.caption)).foregroundStyle(timeOfDay.secondaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 9)], spacing: 9) {
                    ForEach(AthleteDiscipline.allCases) { discipline in
                        disciplineButton(discipline, timeOfDay: timeOfDay)
                    }
                }
            }

            gymDirectory(timeOfDay: timeOfDay)
        }
    }

    private func disciplineButton(_ discipline: AthleteDiscipline, timeOfDay: HomeTimeOfDay) -> some View {
        let selected = draft.disciplines.contains(discipline)
        return Button {
            if selected { draft.disciplines.remove(discipline) }
            else { draft.disciplines.insert(discipline) }
        } label: {
            HStack(spacing: 8) {
                ActivityIconArtwork(
                    kind: discipline.activityIcon,
                    size: 18,
                    color: selected ? .white : timeOfDay.primaryText
                )
                Text(discipline.rawValue).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark") }
            }
            .font(.community(.caption, weight: .semibold))
            .foregroundStyle(selected ? Color.white : timeOfDay.primaryText)
            .padding(.horizontal, 11)
            .frame(height: 44)
            .background(selected ? timeOfDay.accent : timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func gymDirectory(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your gym").font(.community(.headline))
                    Text("Join a gym to find members who train there.")
                        .font(.community(.caption)).foregroundStyle(timeOfDay.secondaryText)
                }
                Spacer()
                Image(systemName: "building.2.fill").foregroundStyle(timeOfDay.accent)
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(timeOfDay.secondaryText)
                TextField("Search gym or city", text: $gymSearch)
                    .textInputAutocapitalization(.words)
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 15))

            ForEach(gymResults.prefix(3)) { gym in
                Button { draft.gym = gym } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 34, height: 34)
                            .background(timeOfDay.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gym.name).font(.community(.subheadline, weight: .semibold))
                            Text("\(gym.location) · \(gym.memberCount) members")
                                .font(.community(.caption2)).foregroundStyle(timeOfDay.secondaryText)
                        }
                        Spacer()
                        Image(systemName: draft.gym?.id == gym.id ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(timeOfDay.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) { isCreatingGym.toggle() }
            } label: {
                Label("Can’t find it? Create a gym", systemImage: "plus")
                    .font(.community(.subheadline, weight: .semibold))
            }

            if isCreatingGym {
                VStack(spacing: 9) {
                    TextField("Gym name", text: $newGymName)
                    TextField("City", text: $newGymCity)
                    TextField("Country", text: $newGymCountry)
                    Button("Create and join") {
                        Task {
                            if let gym = await store.createGym(
                                name: newGymName,
                                city: newGymCity,
                                country: newGymCountry
                            ) {
                                draft.gym = gym
                                isCreatingGym = false
                            }
                        }
                    }
                        .font(.community(.subheadline, weight: .bold))
                        .foregroundStyle(timeOfDay.accent)
                        .disabled(newGymName.isEmpty || newGymCity.isEmpty || newGymCountry.isEmpty)
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(17)
        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(timeOfDay.border, lineWidth: 1) }
    }

    private func bottomAction(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            if !editsOneSection, step < 3 {
                withAnimation(.easeOut(duration: 0.2)) { step += 1 }
            } else {
                finish()
            }
        } label: {
            HStack {
                if authentication.isWorking || store.isSaving {
                    ProgressView().tint(Color.white)
                }
                Text(isSaveStep ? (isEditing ? "Save Changes" : "Create Profile") : "Continue")
                Spacer()
                Image(systemName: isSaveStep ? "checkmark" : "arrow.right")
            }
            .font(.community(.headline, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.42)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    /// Creates the account, then keeps the rest of the answers.
    ///
    /// The account has to exist before anything else can be saved against it,
    /// so the flow stays open until the server accepts it. A taken username or
    /// a rejected password lands back on this page with the reason, rather
    /// than closing on a profile that was never created.
    private func finish() {
        Task {
            if isEditing {
                if await store.save(draft) { dismiss() }
                return
            }

            await authentication.register(
                username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                firstName: draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: draft.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // Holding a token is the only thing that means signed in. An
            // absent error does not: `authenticate` returns without doing
            // anything if a request is already running, which left the flow
            // closing on a login screen having created nothing.
            guard authentication.token != nil else {
                withAnimation(.easeOut(duration: 0.2)) { step = 0 }
                return
            }

            // Optional profile details are configured later from Settings,
            // after the authenticated profile repository is connected.
            dismiss()
        }
    }

    /// Whether pressing the button finishes rather than turns the page.
    private var isSaveStep: Bool { editsOneSection || step == 3 }

    private var canContinue: Bool {

        switch step {
        case 0:
            // Editing already has an account; creating needs one that the
            // server will accept.
            guard !isEditing else { return true }
            return email.contains("@")
                && password.count >= 8
                && !authentication.isWorking
        case 1:
            return !draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !draft.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2:
            return isEditing
                || (draft.heightFeet > 0 && draft.weightPounds > 0 && draft.targetWeightPounds > 0)
        case 3:
            return isEditing || !draft.disciplines.isEmpty
        default:
            return true
        }
    }
}

private struct ProfileAvatarView: View {
    let profile: SocialProfile
    let size: CGFloat
    let timeOfDay: HomeTimeOfDay

    var body: some View {
        Group {
            if let data = profile.profileImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let photo = profile.profilePhotoURL,
                      let url = URL(string: photo) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color.white, lineWidth: 4) }
        .shadow(color: timeOfDay.shadow, radius: 9, x: 4, y: 6)
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(
                colors: [timeOfDay.accent, timeOfDay.heroEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(profile.initials.isEmpty ? "R" : profile.initials)
                .font(.community(size: size * 0.30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
    }
}
