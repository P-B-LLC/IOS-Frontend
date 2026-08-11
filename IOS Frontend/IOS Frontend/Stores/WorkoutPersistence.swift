//
//  WorkoutPersistence.swift
//  IOS Frontend
//
//  The seam where a real database plugs in later.
//

import Foundation

/// The complete workout state exchanged with the persistence layer.
///
/// Scheduled workouts are intentionally day-owned. A future database-backed
/// library of reusable workout templates is a separate concern and can be
/// added without changing this schedule contract.
struct WorkoutSnapshot: Equatable, Codable, Sendable {
    var schedule: [Weekday: Workout]

    static let empty = WorkoutSnapshot(schedule: [:])
}

/// Abstraction over wherever workout data will eventually live.
///
/// The app only talks to `WorkoutStore`. A synchronous local database adapter,
/// such as SwiftData, can implement this protocol and be injected at the app
/// entry point without changing any views. Remote sync can be layered on when
/// the backend is chosen.
protocol WorkoutPersistence {
    func load() throws -> WorkoutSnapshot
    func save(_ snapshot: WorkoutSnapshot) throws
}

/// Empty, session-only storage used until a real database is connected.
///
/// `WorkoutStore` keeps edits alive while the app is open; this adapter simply
/// avoids writing them anywhere between launches. An initial snapshot can be
/// supplied for previews without introducing sample data into production.
struct EphemeralWorkoutPersistence: WorkoutPersistence {
    private let initialSnapshot: WorkoutSnapshot

    init(initialSnapshot: WorkoutSnapshot = .empty) {
        self.initialSnapshot = initialSnapshot
    }

    func load() throws -> WorkoutSnapshot { initialSnapshot }
    func save(_ snapshot: WorkoutSnapshot) throws { }
}
