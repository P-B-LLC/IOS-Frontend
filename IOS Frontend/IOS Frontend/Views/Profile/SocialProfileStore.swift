//
//  SocialProfileStore.swift
//  IOS Frontend
//
//  Backend-backed profile state for the social profile experience.
//

import Foundation
import Observation

enum ConnectedAccountProvider: String, Codable, CaseIterable, Identifiable {
    case apple
    case google

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AthleteDiscipline: String, Codable, CaseIterable, Identifiable {
    case powerlifting = "Powerlifter"
    case bodybuilding = "Bodybuilder"
    case crossFit = "CrossFit"
    case rockClimbing = "Rock Climber"
    case triathlon = "Triathlon Athlete"
    case running = "Runner"
    case cycling = "Cyclist"
    case swimming = "Swimmer"
    case generalFitness = "General Fitness"

    var id: String { rawValue }

    /// What the API calls this discipline.
    ///
    /// Mapped explicitly rather than by `rawValue`: the raw values here are
    /// the words shown on screen, and the server's are its own identifiers.
    /// Tying them together would mean renaming a label silently discarded
    /// everyone's saved discipline.
    var apiValue: String {
        switch self {
        case .powerlifting: "powerlifting"
        case .bodybuilding: "bodybuilding"
        case .crossFit: "crossfit"
        case .rockClimbing: "rock_climbing"
        case .triathlon: "triathlon"
        case .running: "running"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .generalFitness: "general_fitness"
        }
    }

    init?(apiValue: String) {
        guard let match = Self.allCases.first(where: { $0.apiValue == apiValue })
        else { return nil }
        self = match
    }

    var activityIcon: ActivityIconKind {
        switch self {
        case .powerlifting, .bodybuilding, .crossFit: .lifting
        case .rockClimbing: .otherCardio
        case .triathlon, .generalFitness: .cardio
        case .running: .running
        case .cycling: .biking
        case .swimming: .swimming
        }
    }
}

struct GymIdentity: Codable, Equatable, Identifiable {
    let id: UUID
    /// The gym's identity on the server. Nil only for a gym being typed in
    /// that has not been created yet.
    ///
    /// Without this, two people choosing the same gym would each hold their
    /// own locally generated `id` and never match, which is the one thing a
    /// shared gym exists to do.
    var serverID: Int?
    var name: String
    var city: String
    var country: String
    var memberCount: Int

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        name: String,
        city: String,
        country: String,
        memberCount: Int = 1
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.city = city
        self.country = country
        self.memberCount = memberCount
    }

    var location: String { "\(city), \(country)" }
}

struct SocialProfile: Codable, Equatable {
    /// Who this profile belongs to. Nil only for one being filled in during
    /// sign-up, before the server has given it an identity.
    var id: Int?
    /// Answered questions. Carried on the profile because the public payload
    /// brings them along; the signed-in user's own come from the store, which
    /// loads them separately.
    var prompts: [ProfilePromptAnswer] = []
    var provider: ConnectedAccountProvider
    var firstName: String
    var lastName: String
    var username: String
    var bio: String
    var heightFeet: Int
    var heightInches: Int
    var weightPounds: Int
    var targetWeightPounds: Int
    var showsHeight: Bool
    var showsWeight: Bool
    var showsTargetWeight: Bool
    var disciplines: Set<AthleteDiscipline>
    var gym: GymIdentity?
    var profileImageData: Data?
    var profilePhotoURL: String? = nil

    var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var initials: String {
        let components = [firstName, lastName].filter { !$0.isEmpty }
        return components.compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// What a brand-new account starts from.
    ///
    /// Measurements start at zero rather than at a plausible-looking default:
    /// a height nobody typed is not a height, and the flow will not move past
    /// the goals page until they are actually filled in.
    static let empty = SocialProfile(
        provider: .apple,
        firstName: "",
        lastName: "",
        username: "",
        bio: "",
        heightFeet: 0,
        heightInches: 0,
        weightPounds: 0,
        targetWeightPounds: 0,
        showsHeight: false,
        showsWeight: false,
        showsTargetWeight: false,
        disciplines: [],
        gym: nil,
        profileImageData: nil
    )
}

struct SocialPost: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let symbol: String
    let timestamp: String
    let likes: Int
    let comments: Int

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        symbol: String,
        timestamp: String,
        likes: Int,
        comments: Int
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.timestamp = timestamp
        self.likes = likes
        self.comments = comments
    }
}

@MainActor
@Observable
final class SocialProfileStore {
    private var repository: ProfileAPIRepository?
    private var connectionGeneration = UUID()

    private(set) var profile: SocialProfile?
    /// The signed-in user's server id, so their posts can be asked for.
    private(set) var viewerID: Int?
    private(set) var posts: [SocialPost] = []
    private(set) var isLoading = false
    private(set) var hasLoadedProfile = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    /// Questions the signed-in user has answered, and lifts they feature.
    private(set) var prompts: [ProfilePromptAnswer] = []
    private(set) var highlights: [HighlightLift] = []
    /// Other people's featured lifts, kept by user id so a profile visited
    /// twice does not ask twice.
    private(set) var highlightsByUser: [Int: [HighlightLift]] = [:]
    /// Profiles of other people, same reasoning.
    private(set) var peopleByID: [Int: SocialProfile] = [:]

    init() {}

    /// Saves to the backend first. The UI only adopts the server response, so
    /// the phone never becomes a second source of truth for profile data.
    func save(_ profile: SocialProfile) async -> Bool {
        guard repository != nil else {
            errorMessage = "Connect to Repbase before saving profile changes."
            return false
        }
        return await push(profile)
    }

    func clear() {
        profile = nil
        hasLoadedProfile = false
    }

    // MARK: - The server

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        isLoading = true
        hasLoadedProfile = false
        errorMessage = nil
        defer {
            if connectionGeneration == generation {
                isLoading = false
                hasLoadedProfile = true
            }
        }
        do {
            let repository = try ProfileAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository

            let remote = try await repository.profile()
            guard connectionGeneration == generation else { return }
            profile = Self.profile(from: remote)
            // Kept because the profile page has to ask the feed for "posts by
            // this person", and the id is the only way to say who that is.
            viewerID = remote.id

            // Keep the server's idea of this person's day in step with the
            // phone's. Every date the server derives from a moment comes off
            // it -- which day a workout lands on, where a rotation has got to
            // -- and left on UTC those roll over mid-evening for anyone west
            // of Greenwich.
            //
            // Not worth failing sign-in over: the worst case is that dates
            // stay where they were until the next launch.
            let phoneZone = TimeZone.current.identifier
            if remote.timeZone != phoneZone {
                try? await repository.saveTimeZone(phoneZone)
            }

            // Started together: neither depends on the other, and run one
            // after the next they cost two round trips to draw one page.
            async let answersRequest = repository.prompts()
            async let liftsRequest = repository.highlights()
            let (answers, lifts) = try await (answersRequest, liftsRequest)
            guard connectionGeneration == generation else { return }
            prompts = answers
            highlights = lifts
        } catch {
            profile = nil
            errorMessage = error.userFacingMessage
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        profile = nil
        // One account's identity must never be left behind for the next.
        viewerID = nil
        prompts = []
        highlights = []
        highlightsByUser = [:]
        peopleByID = [:]
        isLoading = false
        hasLoadedProfile = false
        errorMessage = nil
    }

    private func push(_ profile: SocialProfile) async -> Bool {
        guard let repository else { return false }
        let generation = connectionGeneration
        isSaving = true
        errorMessage = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            var remote = try await repository.profile()
            remote.username = profile.username
            remote.firstName = profile.firstName
            remote.lastName = profile.lastName
            remote.bio = profile.bio
            remote.showsHeight = profile.showsHeight
            remote.showsWeight = profile.showsWeight
            remote.showsTargetWeight = profile.showsTargetWeight
            remote.disciplines = profile.disciplines.map(\.apiValue).sorted()
            remote.gymID = profile.gym?.serverID
            try await repository.save(remote)

            try await repository.saveMeasurements(
                heightCentimetres: ProfileUnits.centimetres(
                    feet: profile.heightFeet,
                    inches: profile.heightInches
                ),
                weightKilograms: ProfileUnits.kilogramsString(
                    pounds: profile.weightPounds
                ),
                targetWeightKilograms: ProfileUnits.kilogramsString(
                    pounds: profile.targetWeightPounds
                )
            )

            if let image = profile.profileImageData {
                try await repository.uploadPhoto(image, contentType: "image/jpeg")
            }

            let saved = try await repository.profile()
            guard connectionGeneration == generation else { return false }
            self.profile = Self.profile(from: saved)
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            errorMessage = error.userFacingMessage
            return false
        }
    }

    private static func profile(from remote: RemoteProfile) -> SocialProfile {
        let height = ProfileUnits.feetAndInches(centimetres: remote.heightCentimetres)
        return SocialProfile(
            id: remote.id,
            prompts: remote.prompts,
            provider: .apple,
            firstName: remote.firstName,
            lastName: remote.lastName,
            username: remote.username,
            bio: remote.bio,
            heightFeet: height.feet,
            heightInches: height.inches,
            weightPounds: ProfileUnits.pounds(kilogramsString: remote.weightKilograms),
            targetWeightPounds: ProfileUnits.pounds(
                kilogramsString: remote.targetWeightKilograms
            ),
            showsHeight: remote.showsHeight,
            showsWeight: remote.showsWeight,
            showsTargetWeight: remote.showsTargetWeight,
            disciplines: Set(remote.disciplines.compactMap(AthleteDiscipline.init(apiValue:))),
            gym: remote.gymID.map {
                GymIdentity(
                    serverID: $0,
                    name: remote.gymName ?? "",
                    city: remote.gymCity ?? "",
                    country: ""
                )
            },
            profileImageData: nil,
            profilePhotoURL: remote.photoURL
        )
    }

    // MARK: - Gyms

    /// Gyms on the server matching what was typed. Searching before creating
    /// is what keeps one gym from being listed six ways.
    // MARK: - Prompts and highlights

    /// Saves the answered questions and adopts whatever the server returns.
    @discardableResult
    func savePrompts(_ answers: [ProfilePromptAnswer]) async -> Bool {
        guard let repository else {
            errorMessage = "Connect to Repbase before editing your profile."
            return false
        }
        let generation = connectionGeneration
        isSaving = true
        errorMessage = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            let saved = try await repository.savePrompts(answers)
            guard connectionGeneration == generation else { return false }
            prompts = saved
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            errorMessage = error.userFacingMessage
            return false
        }
    }

    @discardableResult
    func saveHighlights(_ lifts: [HighlightLift]) async -> Bool {
        guard let repository else {
            errorMessage = "Connect to Repbase before editing your profile."
            return false
        }
        let generation = connectionGeneration
        isSaving = true
        errorMessage = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            let saved = try await repository.saveHighlights(lifts)
            guard connectionGeneration == generation else { return false }
            highlights = saved
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            errorMessage = error.userFacingMessage
            return false
        }
    }

    /// Somebody else's profile, read once and kept.
    ///
    /// Returns what is already held straight away, so opening a profile a
    /// second time draws immediately rather than blanking while it asks again.
    @discardableResult
    func person(_ userID: Int) async -> SocialProfile? {
        if let held = peopleByID[userID] { return held }
        guard let repository else { return nil }
        let generation = connectionGeneration
        do {
            let remote = try await repository.publicProfile(userID: userID)
            guard connectionGeneration == generation else { return nil }
            let profile = Self.profile(from: remote)
            peopleByID[userID] = profile
            return profile
        } catch {
            guard connectionGeneration == generation else { return nil }
            errorMessage = error.userFacingMessage
            return nil
        }
    }

    /// Somebody else's featured lifts, read once per profile visited.
    func loadHighlights(forUser userID: Int) async {
        guard let repository, highlightsByUser[userID] == nil else { return }
        let generation = connectionGeneration
        do {
            let lifts = try await repository.highlights(forUser: userID)
            guard connectionGeneration == generation else { return }
            highlightsByUser[userID] = lifts
        } catch {
            // A profile that will not give up its lifts is still a profile
            // worth showing, so this fails quietly rather than replacing the
            // page with an error.
            guard connectionGeneration == generation else { return }
            highlightsByUser[userID] = []
        }
    }

    func searchGyms(_ query: String) async -> [GymIdentity] {
        guard let repository, !query.trimmingCharacters(in: .whitespaces).isEmpty
        else { return [] }
        do {
            return try await repository.searchGyms(query).map(Self.identity(from:))
        } catch {
            errorMessage = error.userFacingMessage
            return []
        }
    }

    func createGym(name: String, city: String, country: String) async -> GymIdentity? {
        guard let repository else { return nil }
        do {
            let created = try await repository.createGym(
                name: name,
                city: city,
                country: country
            )
            return Self.identity(from: created)
        } catch {
            errorMessage = error.userFacingMessage
            return nil
        }
    }

    private static func identity(from gym: RemoteGym) -> GymIdentity {
        GymIdentity(
            serverID: gym.id,
            name: gym.name,
            city: gym.city,
            country: gym.country,
            memberCount: gym.memberCount
        )
    }

    static var preview: SocialProfileStore {
        let store = SocialProfileStore()
        store.profile = SocialProfile(
                provider: .apple,
                firstName: "Kajshdklf",
                lastName: "Awlehsadf",
                username: "kajshdklf",
                bio: "Training for strength, moving with purpose, and sharing the work along the way.",
                heightFeet: 5,
                heightInches: 11,
                weightPounds: 185,
                targetWeightPounds: 175,
                showsHeight: true,
                showsWeight: false,
                showsTargetWeight: true,
                disciplines: [.powerlifting, .rockClimbing],
                gym: GymIdentity(
                    name: "Iron District",
                    city: "New York",
                    country: "United States",
                    memberCount: 284
                ),
                profileImageData: nil
            )
        // Sample answers and lifts, so the About tab can be looked at before
        // anybody has filled one in. The lift figures are the shape the server
        // sends: a set that happened, and an estimate derived from it.
        store.prompts = [
            ProfilePromptAnswer(
                question: "why_i_train",
                questionLabel: "Why I train",
                answer: "So my kids never see me quit."
            ),
            ProfilePromptAnswer(
                question: "current_goal",
                questionLabel: "What I am working towards",
                answer: "A 500 lb deadlift before June."
            ),
            ProfilePromptAnswer(
                question: "training_partner",
                questionLabel: "Looking for a training partner who",
                answer: "Turns up at six and does not chat."
            )
        ]
        store.highlights = [
            HighlightLift(
                lift: .deadlift,
                label: "Deadlift",
                source: .logged,
                weightKilograms: Decimal(string: "197.50"),
                reps: 3,
                estimatedOneRepMaxKilograms: Decimal(string: "217.25"),
                performedAt: Date(timeIntervalSince1970: 1_786_000_000),
                exerciseName: "Conventional Deadlift"
            ),
            HighlightLift(
                lift: .squat,
                label: "Squat",
                source: .manual,
                weightKilograms: Decimal(string: "160.00"),
                reps: 5,
                estimatedOneRepMaxKilograms: Decimal(string: "186.67"),
                performedAt: nil,
                exerciseName: nil
            ),
            HighlightLift(
                lift: .bench,
                label: "Bench Press",
                source: .none,
                weightKilograms: nil,
                reps: nil,
                estimatedOneRepMaxKilograms: nil,
                performedAt: nil,
                exerciseName: nil
            )
        ]
        store.hasLoadedProfile = true
        store.posts = [
            SocialPost(
                title: "Upper Day",
                detail: "5 exercises · 18 working sets",
                symbol: "dumbbell.fill",
                timestamp: "Today",
                likes: 42,
                comments: 8
            ),
            SocialPost(
                title: "Morning Run",
                detail: "5.2 km · 28 min",
                symbol: "figure.run",
                timestamp: "Yesterday",
                likes: 31,
                comments: 4
            ),
            SocialPost(
                title: "New PR",
                detail: "Deadlift · 405 lb",
                symbol: "trophy.fill",
                timestamp: "Aug 12",
                likes: 86,
                comments: 17
            )
        ]
        return store
    }
}
