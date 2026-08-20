//
//  Gear.swift
//  IOS Frontend
//
//  A shoe or a bike, and the distance put through it.
//

import Foundation

nonisolated enum GearKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case shoe
    case bike

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shoe: "Shoes"
        case .bike: "Bike"
        }
    }

    /// Singular, for talking about one of them.
    var singular: String {
        switch self {
        case .shoe: "shoe"
        case .bike: "bike"
        }
    }

    var symbolName: String {
        switch self {
        case .shoe: "shoeprints.fill"
        case .bike: "bicycle"
        }
    }

    /// The sport this kind of gear belongs to. A bike is not worn on a run,
    /// and the server refuses the pairing, so the picker never offers it.
    var workoutType: WorkoutType {
        switch self {
        case .shoe: .running
        case .bike: .biking
        }
    }

    /// The gear a session of this type takes, or nil for one that takes none.
    static func forWorkoutType(_ type: WorkoutType) -> GearKind? {
        switch type {
        case .running: .shoe
        case .biking: .bike
        case .swimming, .lifting: nil
        }
    }
}

nonisolated struct Gear: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: GearKind
    var name: String
    var brand: String
    var notes: String
    /// Everything on it, including the distance it arrived with. Kilometres,
    /// as every stored distance is; miles are made at the point of display.
    let totalDistanceKilometers: Double
    /// What it had already covered before Repbase started counting.
    var initialDistanceKilometers: Double
    /// Where the user wants to be warned it is due for replacement. Nil when
    /// they have not said, which is the default: how long a shoe lasts is not
    /// something this app knows.
    var retireAtKilometers: Double?
    var isDefault: Bool
    var retiredAt: Date?
    let sessionCount: Int
    /// When it was last trained in. Nil until it has been used once.
    let lastUsedAt: Date?

    var isRetired: Bool { retiredAt != nil }

    /// How far through its stated life it is, or nil when no life was stated.
    /// Above 1 when it is overdue, which the bar is allowed to show.
    var wearFraction: Double? {
        guard let retireAtKilometers, retireAtKilometers > 0 else { return nil }
        return totalDistanceKilometers / retireAtKilometers
    }

    /// Distance left before the stated retirement point. Negative once past it.
    var remainingKilometers: Double? {
        guard let retireAtKilometers else { return nil }
        return retireAtKilometers - totalDistanceKilometers
    }

    /// What to call it in a list: the brand and name together when both are
    /// known, since "Pegasus 40" and "Nike Pegasus 40" are the same shoe but
    /// only one of them is unambiguous in a list of six.
    var displayName: String {
        brand.isEmpty ? name : "\(brand) \(name)"
    }
}
