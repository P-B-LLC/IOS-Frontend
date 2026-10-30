//
//  WorkoutPreferences.swift
//  IOS Frontend
//
//  How weights are shown and how rests behave, shared by every screen.
//

import Foundation
import Observation

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
@Observable
final class WorkoutPreferences {
    static let defaultRestKey = "workout.defaultRestSeconds"
    static let autoStartRestKey = "workout.autoStartRest"
    static let restAlertsKey = "workout.restAlerts"
    static let liveActivityKey = "workout.liveActivity"

    private let defaults: UserDefaults

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
    func adoptAccountUnit(_ unit: WorkoutWeightUnit) {
        defaultWeightUnit = unit
        hasLoadedUnit = true
        if temporaryWeightUnit == unit { temporaryWeightUnit = nil }
    }

    /// Shows weights in this unit for now, leaving the default alone.
    func useTemporarily(_ unit: WorkoutWeightUnit) {
        temporaryWeightUnit = unit == defaultWeightUnit ? nil : unit
    }

    /// Makes this unit the account default. Shown at once; the account is
    /// written behind it, and a failure puts the old default back and says so.
    func makeDefault(_ unit: WorkoutWeightUnit, using store: WorkoutStore) async {
        let previous = defaultWeightUnit
        defaultWeightUnit = unit
        temporaryWeightUnit = nil
        unitError = nil
        isSavingUnit = true
        defer { isSavingUnit = false }
        do {
            defaultWeightUnit = try await store.savePreferredWeightUnit(unit)
        } catch {
            defaultWeightUnit = previous
            unitError = error.userFacingMessage
                ?? String(localized: "Your unit could not be saved. Try again.", bundle: .app, locale: .app)
        }
    }

    /// One account's choices must not show for the next.
    func reset() {
        defaultWeightUnit = .metric
        temporaryWeightUnit = nil
        hasLoadedUnit = false
        unitError = nil
    }
}
