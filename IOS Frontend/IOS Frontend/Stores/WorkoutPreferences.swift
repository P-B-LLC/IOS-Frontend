//
//  WorkoutPreferences.swift
//  IOS Frontend
//
//  How weights are shown and how rests behave, shared by every screen.
//

import Foundation
import Observation

/// The existing account preference write, kept small so saving and account
/// changes can be tested without a network connection or a workout screen.
@MainActor
protocol WorkoutWeightUnitSaving {
    func savePreferredWeightUnit(_ unit: WorkoutWeightUnit) async throws -> WorkoutWeightUnit
}

/// Workout settings every screen reads from one place, so a change on one
/// screen shows on all of them at once.
///
/// The weight unit has two layers. The account's `unit_preference` is the
/// default and is remembered across sessions and devices. A quick switch on a
/// workout screen changes what is shown right away without touching that
/// default -- somebody reading a plate in pounds at a hotel gym should not
/// have to change their account to do it -- and lasts until the app is next
/// opened or the default is changed. Either way only the display changes:
/// every stored weight stays in kilograms.
///
/// Rest settings live on the device. They describe how this phone behaves
/// between sets, which is not something the backend models.
@MainActor
@Observable
final class WorkoutPreferences {
    static let defaultRestKey = "workout.defaultRestSeconds"
    static let autoStartRestKey = "workout.autoStartRest"
    static let restAlertsKey = "workout.restAlerts"
    static let liveActivityKey = "workout.liveActivity"

    private let defaults: UserDefaults
    @ObservationIgnored private var unitSaveGeneration = UUID()
    @ObservationIgnored private var unitSaveRequestID: UUID?
    @ObservationIgnored private(set) var accountUnitReadRevision = UUID()

    /// The account's saved unit.
    private(set) var defaultWeightUnit: WorkoutWeightUnit = .metric
    /// A unit chosen for now, different from the default. Nil follows it.
    private(set) var temporaryWeightUnit: WorkoutWeightUnit?
    private(set) var isSavingUnit = false
    private(set) var unitError: String?
    private(set) var hasLoadedUnit = false

    var weightUnit: WorkoutWeightUnit { temporaryWeightUnit ?? defaultWeightUnit }
    var isUsingTemporaryUnit: Bool { temporaryWeightUnit != nil }

    var defaultRestSeconds: Int {
        didSet { defaults.set(defaultRestSeconds, forKey: Self.defaultRestKey) }
    }
    /// Whether logging a set starts the rest on its own.
    var autoStartRest: Bool {
        didSet { defaults.set(autoStartRest, forKey: Self.autoStartRestKey) }
    }
    /// Whether a notification says when a rest is over while the app is in
    /// the background.
    var restAlerts: Bool {
        didSet { defaults.set(restAlerts, forKey: Self.restAlertsKey) }
    }
    /// Whether a lifting session shows on the Lock Screen and Dynamic Island.
    var liveActivity: Bool {
        didSet { defaults.set(liveActivity, forKey: Self.liveActivityKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRest = defaults.object(forKey: Self.defaultRestKey) as? Int
        defaultRestSeconds = storedRest.map { min(max($0, 0), Int(RestTimer.maximumSeconds)) }
            ?? RestDurationOptions.standardDefault
        autoStartRest = defaults.object(forKey: Self.autoStartRestKey) as? Bool ?? true
        restAlerts = defaults.object(forKey: Self.restAlertsKey) as? Bool ?? true
        liveActivity = defaults.object(forKey: Self.liveActivityKey) as? Bool ?? true
    }

    /// Takes the account's unit, as read at connection. A temporary choice
    /// survives this, because it was made after the account was read.
    func adoptAccountUnit(_ unit: WorkoutWeightUnit, ifUnchangedSince revision: UUID? = nil) {
        // The initial read can be slower than an explicit save. It must not
        // replace that freshly confirmed value with its older response.
        if let revision, revision != accountUnitReadRevision { return }
        defaultWeightUnit = unit
        hasLoadedUnit = true
        if temporaryWeightUnit == unit { temporaryWeightUnit = nil }
    }

    /// Shows weights in this unit for now, leaving the default alone.
    func useTemporarily(_ unit: WorkoutWeightUnit) {
        temporaryWeightUnit = unit == defaultWeightUnit ? nil : unit
        unitError = nil
    }

    /// Show the selected unit immediately, but do not claim the account
    /// default was saved until the server confirms it. A failure keeps the
    /// temporary display choice and exposes Retry instead of changing inputs.
    func makeDefault(_ unit: WorkoutWeightUnit, using store: any WorkoutWeightUnitSaving) async {
        guard !isSavingUnit else { return }
        let generation = unitSaveGeneration
        let requestID = UUID()
        unitSaveRequestID = requestID
        useTemporarily(unit)
        unitError = nil
        isSavingUnit = true
        defer {
            // A previous account's completion must not unlock a newer save.
            if generation == unitSaveGeneration, unitSaveRequestID == requestID {
                isSavingUnit = false
                unitSaveRequestID = nil
            }
        }
        do {
            let saved = try await store.savePreferredWeightUnit(unit)
            guard generation == unitSaveGeneration, unitSaveRequestID == requestID else { return }
            let displayed = weightUnit
            defaultWeightUnit = saved
            accountUnitReadRevision = UUID()
            // The user may have switched the display again while awaiting
            // this response. Saving an account preference must not undo that.
            temporaryWeightUnit = displayed == saved ? nil : displayed
            hasLoadedUnit = true
        } catch {
            guard generation == unitSaveGeneration, unitSaveRequestID == requestID else { return }
            unitError = error.userFacingMessage
                ?? String(localized: "Your unit could not be saved. Try again.", bundle: .app, locale: .app)
        }
    }

    /// One account's choices must not show for the next.
    func reset() {
        unitSaveGeneration = UUID()
        unitSaveRequestID = nil
        accountUnitReadRevision = UUID()
        isSavingUnit = false
        defaultWeightUnit = .metric
        temporaryWeightUnit = nil
        hasLoadedUnit = false
        unitError = nil
    }
}
