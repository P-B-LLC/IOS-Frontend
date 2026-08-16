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
    var name: String
    var city: String
    var country: String
    var memberCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        city: String,
        country: String,
        memberCount: Int = 1
    ) {
        self.id = id
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

    private(set) var profile: SocialProfile?
    private(set) var posts: [SocialPost] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            profile = try? JSONDecoder().decode(SocialProfile.self, from: data)
        }
    }

    func save(_ profile: SocialProfile) {
        self.profile = profile
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        profile = nil
        defaults.removeObject(forKey: storageKey)
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
