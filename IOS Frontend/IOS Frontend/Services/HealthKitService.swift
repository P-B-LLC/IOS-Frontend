//
//  HealthKitService.swift
//  IOS Frontend
//
//  Reading what the iPhone and Apple Watch already recorded.
//
//  Read-only, always. Repbase never writes to Health: everything it knows how
//  to record it records itself, and writing back would give the same workout
//  two homes and no way to say which is right.
//

import Foundation
import HealthKit
import Observation

/// One day's step count, as Health reports it.
nonisolated struct DailyStepCount: Identifiable, Hashable, Sendable {
    /// Midnight local, the day the steps were taken.
    let day: Date
    let steps: Int

    var id: Date { day }
}

/// One workout Health holds, reduced to what Repbase can use.
nonisolated struct HealthWorkout: Identifiable, Hashable, Sendable {
    /// Health's own identifier. Carried through to the server so importing the
    /// same workout twice updates one row rather than making a second.
    let externalID: String
    let activity: WorkoutType
    let startedAt: Date
    let endedAt: Date
    let distanceKilometres: Double?
    let energyKilocalories: Double?

    var id: String { externalID }

    /// Whether this overlaps something Repbase recorded itself.
    ///
    /// A run tracked in the app and by the Watch is one run. The app's own
    /// recording wins, because it has the route and the barometric climb, and
    /// this one is skipped rather than counted a second time.
    func overlaps(start: Date, end: Date) -> Bool {
        startedAt < end && start < endedAt
    }
}

@Observable
final class HealthKitService {
    /// Why Health is unavailable, or nil when it can be used.
    enum Unavailable: Equatable {
        /// iPad without Health, or a platform that has none.
        case notSupported
        /// The user has not been asked yet.
        case notRequested
        /// The user was asked and said no, or the entitlement is missing.
        ///
        /// HealthKit deliberately does not distinguish "denied" from "no such
        /// data" for reads, so a refusal looks exactly like an empty Health
        /// app. Both end here, and the wording avoids accusing the user of
        /// having refused when they may simply have no data.
        case noData

        var message: String {
            switch self {
            case .notSupported:
                "This device does not have Apple Health."
            case .notRequested:
                "Connect Apple Health to bring in your steps and the workouts your Watch records."
            case .noData:
                "No Health data came back. Check Repbase under Settings › Health › Data Access if you expected some."
            }
        }
    }

    private let store = HKHealthStore()

    private(set) var isRequestingAuthorization = false
    private(set) var hasRequestedAuthorization = false
    private(set) var stepsToday: Int?
    private(set) var errorMessage: String?

    /// Whether the device can do this at all. False on the simulator only if
    /// the runtime is missing Health, which iOS simulators are not.
    var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    /// What to tell the user, or nil when there is data to show instead.
    var unavailable: Unavailable? {
        if !isSupported { return .notSupported }
        if !hasRequestedAuthorization { return .notRequested }
        if stepsToday == nil { return .noData }
        return nil
    }

    /// The types Repbase asks to read. Nothing is requested to write.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let distance = HKQuantityType.quantityType(
            forIdentifier: .distanceWalkingRunning
        ) {
            types.insert(distance)
        }
        if let swimming = HKQuantityType.quantityType(
            forIdentifier: .distanceSwimming
        ) {
            types.insert(swimming)
        }
        if let cycling = HKQuantityType.quantityType(
            forIdentifier: .distanceCycling
        ) {
            types.insert(cycling)
        }
        if let energy = HKQuantityType.quantityType(
            forIdentifier: .activeEnergyBurned
        ) {
            types.insert(energy)
        }
        return types
    }

    /// Asks for read access. The sheet is Apple's and appears once per type;
    /// asking again after a refusal shows nothing at all, which is why the
    /// button that calls this says "Connect" rather than promising a prompt.
    func requestAuthorization() async {
        guard isSupported else { return }
        isRequestingAuthorization = true
        errorMessage = nil
        defer { isRequestingAuthorization = false }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            hasRequestedAuthorization = true
            await refreshStepsToday()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Today's steps, summed across every source Health holds.
    ///
    /// Health records the same steps from a phone and a watch separately, so
    /// a plain sum over samples double-counts a day spent wearing both.
    /// `HKStatisticsQuery` with `.cumulativeSum` is the query that already
    /// knows this and de-duplicates by source.
    func refreshStepsToday() async {
        guard isSupported,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: Date(),
            options: .strictStartDate
        )

        let sum: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(
                    returning: statistics?.sumQuantity()?.doubleValue(for: .count())
                )
            }
            store.execute(query)
        }

        guard let sum else { return }
        stepsToday = Int(sum.rounded())
    }

    /// Finished workouts Health holds since a date, newest first.
    ///
    /// Only the four kinds Repbase understands. A tennis match in Health is
    /// not something this app can draw, and inventing a workout type for it
    /// would put a row in the training history that no screen can explain.
    func workouts(since: Date) async -> [HealthWorkout] {
        guard isSupported else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: since,
            end: Date(),
            options: .strictStartDate
        )
        let newestFirst = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [newestFirst]
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }

        return samples.compactMap { sample in
            guard let workout = sample as? HKWorkout,
                  let activity = Self.workoutType(from: workout.workoutActivityType)
            else { return nil }

            return HealthWorkout(
                externalID: workout.uuid.uuidString,
                activity: activity,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                distanceKilometres: Self.distance(of: workout, activity: activity),
                energyKilocalories: workout.statistics(
                    for: HKQuantityType(.activeEnergyBurned)
                )?.sumQuantity()?.doubleValue(for: .kilocalorie())
            )
        }
    }

    /// Maps Health's activity types onto the four Repbase records. Anything
    /// else returns nil and is left in Health.
    private static func workoutType(
        from activity: HKWorkoutActivityType
    ) -> WorkoutType? {
        switch activity {
        case .running: .running
        case .cycling: .biking
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: .lifting
        default: nil
        }
    }

    /// Distance in kilometres, read from whichever quantity matches the sport.
    private static func distance(
        of workout: HKWorkout,
        activity: WorkoutType
    ) -> Double? {
        let identifier: HKQuantityTypeIdentifier
        switch activity {
        case .running: identifier = .distanceWalkingRunning
        case .biking: identifier = .distanceCycling
        case .swimming: identifier = .distanceSwimming
        // Lifting records no distance, and asking for one returns nothing
        // rather than zero, which would read as "measured, and it was zero".
        case .lifting: return nil
        }

        return workout
            .statistics(for: HKQuantityType(identifier))?
            .sumQuantity()?
            .doubleValue(for: .meterUnit(with: .kilo))
    }
}
