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
//  This type only reads Health. What is kept, and what is shown, is the
//  server's business: see `ActivityStore`.
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
@MainActor
final class HealthKitService {
    /// Whether the user has ever been shown Apple's permission sheet.
    ///
    /// HealthKit will not say whether a read was allowed. That would leak the
    /// fact that someone declined, which is itself health information, so
    /// there is nothing to query and this has to be remembered. It records
    /// having asked, not the answer.
    private static let hasAskedKey = "repbase.health.hasAsked"

    private let store = HKHealthStore()
    private let defaults: UserDefaults

    private(set) var isRequestingAuthorization = false
    private(set) var errorMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the device can do this at all.
    var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Whether the sheet has been shown before. False means the user has never
    /// had the chance to say yes, which is a different thing from having said
    /// no.
    var hasAsked: Bool { defaults.bool(forKey: Self.hasAskedKey) }

    /// The types Repbase asks to read. Nothing is requested to write.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier: HKQuantityTypeIdentifier in [
            .stepCount,
            .distanceWalkingRunning,
            .distanceSwimming,
            .distanceCycling,
            .activeEnergyBurned,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Asks for read access. The sheet appears once per type; asking again
    /// after a refusal shows nothing at all, which is why the button that
    /// calls this says "Connect" rather than promising a prompt.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isSupported else { return false }
        isRequestingAuthorization = true
        errorMessage = nil
        defer { isRequestingAuthorization = false }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            defaults.set(true, forKey: Self.hasAskedKey)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Steps per day from `start` to now, one entry per day Health knows of.
    ///
    /// Health records the same steps from a phone and a watch separately, so a
    /// plain sum over samples double-counts every day spent wearing both.
    /// `HKStatisticsCollectionQuery` with `.cumulativeSum` is the query that
    /// already knows this and de-duplicates by source, and it buckets by day
    /// in one pass rather than being asked once per day.
    func dailySteps(since start: Date) async -> [DailyStepCount] {
        guard isSupported,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return [] }

        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let now = Date()
        guard anchor < now else { return [] }

        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: HKQuery.predicateForSamples(
                withStart: anchor,
                end: now,
                options: .strictStartDate
            ),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )

        let collection: HKStatisticsCollection? = await withCheckedContinuation { continuation in
            query.initialResultsHandler = { _, results, _ in
                continuation.resume(returning: results)
            }
            store.execute(query)
        }

        guard let collection else { return [] }

        var days: [DailyStepCount] = []
        collection.enumerateStatistics(from: anchor, to: now) { statistics, _ in
            // A day with no samples is a day Health was not asked about, not a
            // day nobody walked. Sending a zero would be a claim.
            guard let sum = statistics.sumQuantity()?.doubleValue(for: .count()),
                  sum > 0
            else { return }
            days.append(
                DailyStepCount(
                    day: calendar.startOfDay(for: statistics.startDate),
                    steps: Int(sum.rounded())
                )
            )
        }
        return days
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

#if DEBUG
extension HealthKitService {
    /// A service that reports having already shown the permission sheet.
    ///
    /// Lives here rather than in the preview itself so the key stays private:
    /// nothing outside this type should be writing that flag.
    /// A service that has never shown the sheet, whatever this simulator has
    /// done before. Without it the "never asked" wording cannot be seen at all
    /// after the first run on a given device.
    static func previewNeverAsked() -> HealthKitService {
        let defaults = UserDefaults(suiteName: "repbase.health.preview.fresh") ?? .standard
        defaults.removeObject(forKey: hasAskedKey)
        return HealthKitService(defaults: defaults)
    }

    static func previewAlreadyAsked() -> HealthKitService {
        let defaults = UserDefaults(suiteName: "repbase.health.preview") ?? .standard
        defaults.set(true, forKey: hasAskedKey)
        return HealthKitService(defaults: defaults)
    }
}
#endif
