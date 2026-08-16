//
//  SocialProfileStore.swift
//  IOS Frontend
//
//  Local profile state for the social profile experience. The model is kept
//  separate from authentication so it can move to the API without changing UI.
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
    private let defaults: UserDefaults
    private let storageKey = "repbase.social-profile.v1"
    private var repository: ProfileAPIRepository?
    private var connectionGeneration = UUID()

    private(set) var profile: SocialProfile?
    private(set) var posts: [SocialPost] = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            profile = try? JSONDecoder().decode(SocialProfile.self, from: data)
        }
    }

    func save(_ profile: SocialProfile) {
        self.profile = profile
        cache(profile)
        guard repository != nil else { return }
        Task { await push(profile) }
    }

    func clear() {
        profile = nil
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: - The server

    /// The device copy, which is what the screens read while a request is in
    /// flight and what they fall back to when the app opens without a network.
    private func cache(_ profile: SocialProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        do {
            let repository = try ProfileAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository
            let remote = try await repository.profile()
            guard connectionGeneration == generation else { return }
            // The server is the record. A device copy that disagrees with it
            // is stale, not authoritative.
            let merged = Self.merge(remote, into: profile)
            self.profile = merged
            cache(merged)
        } catch {
            // The cached copy stays on screen: being offline is not a reason
            // to show someone an empty profile.
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        errorMessage = nil
        // The profile itself is left alone; `clear()` is what signing out uses.
    }

    private func push(_ profile: SocialProfile) async {
        guard let repository else { return }
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
        } catch {
            guard connectionGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Server values win, except for what the server does not hold.
    ///
    /// The photo is kept as bytes on the device because the API returns a URL,
    /// and the sign-in provider has no home on the server at all yet.
    private static func merge(
        _ remote: RemoteProfile,
        into local: SocialProfile?
    ) -> SocialProfile {
        let height = ProfileUnits.feetAndInches(centimetres: remote.heightCentimetres)
        return SocialProfile(
            provider: local?.provider ?? .apple,
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
            profileImageData: local?.profileImageData
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
        let suite = UserDefaults(suiteName: "repbase.profile.preview.\(UUID().uuidString)")!
        let store = SocialProfileStore(defaults: suite)
        store.save(
            SocialProfile(
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
        )
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

extension GymIdentity {
    static let directorySamples: [GymIdentity] = [
        GymIdentity(name: "Iron District", city: "New York", country: "United States", memberCount: 284),
        GymIdentity(name: "Barbell Culture", city: "Austin", country: "United States", memberCount: 176),
        GymIdentity(name: "North Shore Strength", city: "Toronto", country: "Canada", memberCount: 92),
        GymIdentity(name: "The Foundry", city: "London", country: "United Kingdom", memberCount: 318),
        GymIdentity(name: "Kraftwerk Athletics", city: "Berlin", country: "Germany", memberCount: 141),
        GymIdentity(name: "Harbour Performance", city: "Sydney", country: "Australia", memberCount: 205)
    ]
}
