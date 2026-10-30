//
//  WorkoutSetType.swift
//  IOS Frontend
//
//  What a set is for, and what that changes about how it is logged.
//

import Foundation

/// The kind of set a row is. Mirrors the API `set_type` values; the raw values
/// must stay in step with the generated `SetTypeEnum`.
///
/// Each kind changes what happens, not only what the row is called:
/// - a warm-up is not a working set. It takes no number in the working count,
///   and the server leaves it out of records, progress and highlights, so a
///   light ramp-up never reads as a regression;
/// - a drop set follows the set before it without a break, so finishing the
///   set before one does not start the rest timer;
/// - a failure set is a working set taken as far as it goes. It counts like a
///   normal one and records the reps actually completed.
nonisolated enum WorkoutSetType: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case normal
    case warmup
    case drop
    case failure

    var id: String { rawValue }

    /// Whether this set is part of the work itself rather than preparation.
    var countsAsWorkingSet: Bool { self != .warmup }

    /// A drop set is done straight after the set before it. Resting first
    /// would turn it back into an ordinary lighter set.
    var followsWithoutRest: Bool { self == .drop }

    var title: String {
        switch self {
        case .normal: return String(localized: "Normal set", bundle: .app, locale: .app, comment: "A kind of workout set: an ordinary working set")
        case .warmup: return String(localized: "Warm-up set", bundle: .app, locale: .app, comment: "A kind of workout set: a lighter set before the working sets")
        case .drop: return String(localized: "Drop set", bundle: .app, locale: .app, comment: "A kind of workout set: done straight after the previous set with less weight")
        case .failure: return String(localized: "Failure set", bundle: .app, locale: .app, comment: "A kind of workout set: taken until no more reps are possible")
        }
    }

    /// The one-letter mark a set row shows in place of its number. A normal
    /// set has none: it shows its place in the working count instead.
    var badge: String? {
        switch self {
        case .normal: return nil
        case .warmup: return String(localized: "W", bundle: .app, locale: .app, comment: "One-letter mark for a warm-up set, shown in place of the set number")
        case .drop: return String(localized: "D", bundle: .app, locale: .app, comment: "One-letter mark for a drop set, shown in place of the set number")
        case .failure: return String(localized: "F", bundle: .app, locale: .app, comment: "One-letter mark for a failure set, shown in place of the set number")
        }
    }

    /// One line on what choosing this type changes, for the type menu.
    var explanation: String {
        switch self {
        case .normal: return String(localized: "Counts toward your records and progress.", bundle: .app, locale: .app)
        case .warmup: return String(localized: "Prepares you. Left out of records and progress.", bundle: .app, locale: .app)
        case .drop: return String(localized: "Starts straight after the set before it, with no rest.", bundle: .app, locale: .app)
        case .failure: return String(localized: "A working set taken as far as you can go.", bundle: .app, locale: .app)
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "number"
        case .warmup: return "flame"
        case .drop: return "arrow.down.right"
        case .failure: return "bolt.fill"
        }
    }
}
