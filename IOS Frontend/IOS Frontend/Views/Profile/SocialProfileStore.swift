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

    var symbol: String {
        switch self {
        case .powerlifting: "figure.strengthtraining.traditional"
        case .bodybuilding: "dumbbell.fill"
        case .crossFit: "figure.cross.training"
        case .rockClimbing: "figure.climbing"
        case .triathlon: "figure.triathlon"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .generalFitness: "figure.mixed.cardio"
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
    private(set) var posts: [SocialPost] = []
    private(set) var isLoading = false
    private(set) var hasLoadedProfile = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

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
        } catch {
            profile = nil
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        profile = nil
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
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func profile(from remote: RemoteProfile) -> SocialProfile {
        let height = ProfileUnits.feetAndInches(centimetres: remote.heightCentimetres)
        return SocialProfile(
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
    func searchGyms(_ query: String) async -> [GymIdentity] {
        guard let repository, !query.trimmingCharacters(in: .whitespaces).isEmpty
        else { return [] }
        do {
            return try await repository.searchGyms(query).map(Self.identity(from:))
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
