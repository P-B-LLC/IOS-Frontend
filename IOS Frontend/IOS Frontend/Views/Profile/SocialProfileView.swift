//
//  SocialProfileView.swift
//  IOS Frontend
//
//  Profile onboarding and the public-facing athlete profile.
//

import PhotosUI
import SwiftUI

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

struct SocialProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(SocialProfileStore.self) private var store

    let profile: SocialProfile
    var isCurrentUser = true
    @State private var selectedSection: ProfileSection = .posts
    @State private var editingProfile = false
    @State private var showingSettings = false
    @State private var isFollowing = false

    private enum ProfileSection: String, CaseIterable, Identifiable {
        case posts = "Posts"
        case about = "About"
        var id: String { rawValue }
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
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
            .sheet(isPresented: $editingProfile) {
                NavigationStack {
                    ProfileOnboardingView(seed: profile, isEditing: true)
                        .environment(store)
                }
            }
            .sheet(isPresented: $showingSettings) {
                ProfileSettingsView(profile: profile)
            }
        }
    }

    private func profileHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACCOUNT / PUBLIC PROFILE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.25)
                    .foregroundStyle(timeOfDay.accent)
                Text("Profile")
                    .font(.system(size: 34, weight: .bold))
            }

            Spacer()

            Menu {
                Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                }
                Button("Edit Profile", systemImage: "pencil") {
                    editingProfile = true
                }
                Button("Refresh Workouts", systemImage: "arrow.clockwise") {
                    workoutStore.retryPersistence()
                }
                Divider()
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await authentication.signOut() }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile and app settings")
        }
        .padding(.bottom, 8)
    }

    private func identityCard(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 22) {
                ProfileAvatarView(profile: profile, size: 88, timeOfDay: timeOfDay)

                HStack(spacing: 18) {
                    profileStat("\(store.posts.count)", label: "Posts")
                    profileStat("0", label: "Followers")
                    profileStat("0", label: "Following")
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 22, weight: .bold))
                Text("@\(profile.username)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !profile.disciplines.isEmpty {
                    Label(disciplineSummary, systemImage: "figure.strengthtraining.traditional")
                }
                if let gym = profile.gym {
                    HStack(spacing: 6) {
                        Label("\(gym.name) · \(gym.city)", systemImage: "building.2")
                        if !isCurrentUser {
                            Text("Same gym")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(timeOfDay.accent)
                        }
                    }
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(timeOfDay.secondaryText)

            profileAction(timeOfDay: timeOfDay)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle().fill(timeOfDay.border).frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(timeOfDay.border).frame(height: 1)
                }
        }
    }

    private var disciplineSummary: String {
        Array(profile.disciplines)
            .sorted { $0.rawValue < $1.rawValue }
            .prefix(2)
            .map(\.rawValue)
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func profileAction(timeOfDay: HomeTimeOfDay) -> some View {
        if isCurrentUser {
            Button { editingProfile = true } label: {
                Label("Edit profile", systemImage: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.accent)
        } else {
            Button { isFollowing.toggle() } label: {
                Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
            }
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.accent)
        }
    }

    private func profileStat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionPicker(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 32) {
            ForEach(ProfileSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selectedSection = section }
                } label: {
                    VStack(spacing: 7) {
                        Label(section.rawValue, systemImage: section == .posts ? "square.grid.2x2" : "person.text.rectangle")
                            .font(.subheadline.weight(.semibold))
                        Capsule()
                            .fill(selectedSection == section ? timeOfDay.accent : Color.clear)
                            .frame(height: 3)
                    }
                    .foregroundStyle(selectedSection == section ? timeOfDay.primaryText : timeOfDay.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(timeOfDay.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func postsSection(timeOfDay: HomeTimeOfDay) -> some View {
        if store.posts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(timeOfDay.accent)
                Text("No posts yet").font(.headline)
                Text("Completed workouts and shared milestones will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(timeOfDay.border).frame(height: 1)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.posts) { post in
                    HStack(spacing: 14) {
                        Image(systemName: post.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 48, height: 48)
                            .background(timeOfDay.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(post.title).font(.headline)
                                Spacer()
                                Text(post.timestamp).font(.caption).foregroundStyle(timeOfDay.secondaryText)
                            }
                            Text(post.detail).font(.subheadline).foregroundStyle(timeOfDay.secondaryText)
                            HStack(spacing: 14) {
                                Label("\(post.likes)", systemImage: "heart")
                                Label("\(post.comments)", systemImage: "bubble.left")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)

                    if post.id != store.posts.last?.id {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(timeOfDay.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(timeOfDay.border).frame(height: 1) }
        }
    }

    private func aboutSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 0) {
            if profile.showsHeight {
                aboutRow("Height", value: "\(profile.heightFeet)′ \(profile.heightInches)″", symbol: "ruler")
            }
            if profile.showsWeight {
                aboutRow("Weight", value: "\(profile.weightPounds) lb", symbol: "scalemass")
            }
            if profile.showsTargetWeight {
                aboutRow("Target weight", value: "\(profile.targetWeightPounds) lb", symbol: "scope")
            }
            if !profile.showsHeight && !profile.showsWeight && !profile.showsTargetWeight {
                Text("This athlete keeps their body measurements private.")
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(timeOfDay.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(timeOfDay.border).frame(height: 1) }
    }

    private func aboutRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color(hex: 0xF86722)).frame(width: 28)
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.bold))
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

    let profile: SocialProfile
    @State private var editorDestination: ProfileEditorDestination?

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
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.3)
                                .foregroundStyle(timeOfDay.accent)
                            Text("Everything in one place.")
                                .font(.system(size: 34, weight: .bold))
                            Text("Manage your public identity, nutrition targets, workout data, and account.")
                                .font(.subheadline)
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
                                    settingsRow(
                                        "Training identity",
                                        detail: "Photo, disciplines, and gym",
                                        symbol: "figure.strengthtraining.traditional"
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
                            .disabled(authentication.isWorking)
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
        .sheet(item: $editorDestination) { destination in
            NavigationStack {
                ProfileOnboardingView(
                    seed: profile,
                    isEditing: true,
                    initialStep: destination.rawValue
                )
                    .environment(store)
            }
        }
    }

    private func settingsHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Text("Settings")
                .font(.headline.weight(.bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
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
                .font(.system(size: 10, weight: .bold))
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color ?? Color(hex: 0xF86722))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color ?? .primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(color ?? .secondary)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
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

    init(seed: SocialProfile, isEditing: Bool = false, initialStep: Int? = nil) {
        self.isEditing = isEditing
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
                                .font(.footnote)
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
                if step > (isEditing ? 1 : 0) {
                    withAnimation(.easeOut(duration: 0.2)) { step -= 1 }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: step > (isEditing ? 1 : 0) ? "chevron.left" : "xmark")
            }
            .buttonStyle(RepbaseSculptedIconButtonStyle(timeOfDay: timeOfDay))

            Spacer()
            Text(isEditing ? "Edit Profile" : "Create Profile")
                .font(.headline.weight(.bold))
            Spacer()
            Text("\(step - firstStep + 1)/\(stepCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func stepProgress(timeOfDay: HomeTimeOfDay) -> some View {
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

    private var firstStep: Int { isEditing ? 1 : 0 }
    private var stepCount: Int { 4 - firstStep }

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
            Text(title).font(.system(size: 29, weight: .bold, design: .rounded))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = authentication.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Label(
                "Signing in with Apple or Google is coming. Your account will link to one when it does.",
                systemImage: "lock.fill"
            )
            .font(.caption)
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
                Image(systemName: symbol).font(.title3)
                Text("Continue with \(provider.title)").font(.headline)
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
                Text("Username").font(.caption.weight(.semibold)).foregroundStyle(timeOfDay.secondaryText)
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(timeOfDay.accent).font(.headline)
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
                Text("Bio (optional)").font(.caption.weight(.semibold)).foregroundStyle(timeOfDay.secondaryText)
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
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(timeOfDay.secondaryText)
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
                .font(.caption)
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
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                content()
            }
            Divider()
            privacy()
                .font(.subheadline.weight(.medium))
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
            Text(unit).font(.caption).foregroundStyle(timeOfDay.secondaryText)
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
                            .font(.subheadline.weight(.bold))
                    }
                    Button("Set it later") { draft.profileImageData = nil }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How do you train?").font(.headline)
                Text("Choose all that fit.").font(.caption).foregroundStyle(timeOfDay.secondaryText)
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
                Image(systemName: discipline.symbol)
                Text(discipline.rawValue).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark") }
            }
            .font(.caption.weight(.semibold))
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
                    Text("Your gym").font(.headline)
                    Text("Join a gym to find members who train there.")
                        .font(.caption).foregroundStyle(timeOfDay.secondaryText)
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
                            Text(gym.name).font(.subheadline.weight(.semibold))
                            Text("\(gym.location) · \(gym.memberCount) members")
                                .font(.caption2).foregroundStyle(timeOfDay.secondaryText)
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
                    .font(.subheadline.weight(.semibold))
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
                        .font(.subheadline.weight(.bold))
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
            if step < 3 {
                withAnimation(.easeOut(duration: 0.2)) { step += 1 }
            } else {
                finish()
            }
        } label: {
            HStack {
                if authentication.isWorking || store.isSaving {
                    ProgressView().tint(Color.white)
                }
                Text(step == 3 ? (isEditing ? "Save Profile" : "Create Profile") : "Continue")
                Spacer()
                Image(systemName: step == 3 ? "checkmark" : "arrow.right")
            }
            .font(.headline.weight(.bold))
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
                .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
    }
}
