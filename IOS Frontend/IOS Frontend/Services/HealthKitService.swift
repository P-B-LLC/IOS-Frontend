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
@preconcurrency import HealthKit
import Observation

@Observable
@MainActor
final class HealthKitService: HealthDataReading {
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
            .heartRate,
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
    func dailySteps(since start: Date) async throws -> [DailyStepCount] {
        try Task.checkCancellation()
        guard isSupported,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { throw HealthIntegrationFailure.unsupportedDevice }

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

        let collection: HKStatisticsCollection? = try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results) }
            }
            store.execute(query)
        }
        try Task.checkCancellation()

        guard let collection else { return [] }

        var days: [DailyStepCount] = []
        collection.enumerateStatistics(from: anchor, to: now) { statistics, _ in
            // A day with no samples is a day Health was not asked about, not a
            // day nobody walked. Sending a zero would be a claim.
            guard let sum = statistics.sumQuantity()?.doubleValue(for: .count()),
                  sum.isFinite, sum > 0, sum < Double(Int.max)
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

    /// Bounded anchored pages from a fixed window. Anchors are opaque, local,
    /// and never sent to the server. Replaying the window safely backfills
    /// late Watch syncs and corrections using the server's external identity.
    func workoutPage(since: Date, until: Date, cursor: Data?) async throws -> HealthWorkoutPage {
        try Task.checkCancellation()
        guard isSupported else { throw HealthIntegrationFailure.unsupportedDevice }
        let predicate = HKQuery.predicateForSamples(
            withStart: since,
            end: until,
            options: .strictStartDate
        )
        let anchor: HKQueryAnchor?
        if let cursor {
            anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: cursor)
        } else { anchor = nil }
        if cursor != nil && anchor == nil { throw HealthIntegrationFailure.malformedPage }
        let result: ([HKSample], Int, HKQueryAnchor?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: HKObjectType.workoutType(), predicate: predicate,
                                            anchor: anchor, limit: HealthSyncPolicy.batchSize) {
                _, samples, deleted, nextAnchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], deleted?.count ?? 0, nextAnchor)) }
            }
            store.execute(query)
        }
        try Task.checkCancellation()
        let hasMore = result.0.count + result.1 >= HealthSyncPolicy.batchSize
        let next: Data?
        if hasMore, let nextAnchor = result.2 {
            next = try NSKeyedArchiver.archivedData(withRootObject: nextAnchor, requiringSecureCoding: true)
        } else { next = nil }
        if hasMore && (next == nil || next == cursor) { throw HealthIntegrationFailure.malformedPage }
        let workouts = result.0.compactMap { sample -> HealthWorkout? in
            guard let workout = sample as? HKWorkout,
                  workout.endDate > workout.startDate,
                  workout.endDate <= until,
                  workout.duration.isFinite, workout.duration > 0 else { return nil }
            let activity = Self.workoutActivity(from: workout.workoutActivityType)
            let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
            let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
            return HealthWorkout(
                externalID: workout.uuid.uuidString,
                activity: activity.family,
                workoutActivity: activity,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                distanceKilometres: Self.distance(of: workout, activity: activity.family),
                energyKilocalories: workout.statistics(
                    for: HKQuantityType(.activeEnergyBurned)
                )?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                durationSeconds: workout.duration,
                averageHeartRateBPM: heartRate?.averageQuantity()?.doubleValue(for: beatsPerMinute),
                maxHeartRateBPM: heartRate?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
                sourceName: workout.sourceRevision.source.name,
                sourceBundleID: workout.sourceRevision.source.bundleIdentifier,
                deviceName: workout.device?.name
            )
        }
        return HealthWorkoutPage(workouts: workouts, nextCursor: next)
    }

    /// Specific sport, not a guessed lifting session. Unknown future types are
    /// still usable summaries under Other, with their measured time and data.
    private static func workoutActivity(
        from activity: HKWorkoutActivityType
    ) -> WorkoutActivity {
        switch activity {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling: .cycling
        case .swimming: .swimming
        case .traditionalStrengthTraining: .weightlifting
        case .functionalStrengthTraining: .functionalTraining
        case .crossTraining: .functionalTraining
        case .highIntensityIntervalTraining: .hiit
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairClimbing, .stairs: .stairClimbing
        case .jumpRope: .jumpRope
        case .tennis: .tennis
        case .badminton: .badminton
        case .tableTennis: .tableTennis
        case .squash: .squash
        case .pickleball: .pickleball
        case .soccer: .soccer
        case .americanFootball: .americanFootball
        case .basketball: .basketball
        case .volleyball: .volleyball
        case .rugby: .rugby
        case .hockey: .hockey
        case .baseball: .baseball
        case .handball: .handball
        case .cricket: .cricket
        case .boxing: .boxing
        case .kickboxing: .kickboxing
        case .martialArts, .wrestling: .martialArts
        case .yoga: .yoga
        case .pilates: .pilates
        case .flexibility: .stretching
        case .dance, .danceInspiredTraining, .socialDance, .cardioDance: .dance
        case .climbing: .climbing
        case .downhillSkiing, .crossCountrySkiing: .skiing
        case .snowboarding: .snowboarding
        case .surfingSports: .surfing
        case .paddleSports: .paddling
        case .golf: .golf
        default: .other
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
