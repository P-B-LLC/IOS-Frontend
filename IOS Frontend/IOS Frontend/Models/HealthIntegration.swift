import Foundation

nonisolated struct DailyStepCount: Identifiable, Hashable, Sendable {
    let day: Date
    let steps: Int
    var id: Date { day }
}

/// A bounded device reading, not a published post. External identity is kept
/// stable across retries; the backend owns linking and duplicate decisions.
nonisolated struct HealthWorkout: Identifiable, Hashable, Sendable {
    let externalID: String
    let activity: WorkoutType
    let workoutActivity: WorkoutActivity
    let startedAt: Date
    let endedAt: Date
    let distanceKilometres: Double?
    let energyKilocalories: Double?
    let durationSeconds: Double
    let averageHeartRateBPM: Double?
    let maxHeartRateBPM: Double?
    let sourceName: String?
    let sourceBundleID: String?
    let deviceName: String?
    var id: String { externalID }
}

nonisolated struct HealthWorkoutPage: Sendable {
    let workouts: [HealthWorkout]
    let nextCursor: Data?
}

/// Completion of Apple's prompt is not proof that reading was allowed.
@MainActor
protocol HealthDataReading: AnyObject {
    var isSupported: Bool { get }
    var hasAsked: Bool { get }
    var isRequestingAuthorization: Bool { get }
    var errorMessage: String? { get }
    func requestAuthorization() async -> Bool
    func dailySteps(since start: Date) async throws -> [DailyStepCount]
    func workoutPage(since start: Date, until end: Date, cursor: Data?) async throws -> HealthWorkoutPage
}

/// Server-owned, private workout measurements. Missing metrics stay missing;
/// a watch does not measure exercise sets, repetitions or lifting weight.
nonisolated struct HealthWorkoutSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let sessionID: Int
    let externalID: String
    let provider: String
    let source: String
    let sourceName: String?
    let sourceBundleID: String?
    let deviceName: String?
    let activity: WorkoutActivity
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let distanceKilometers: Decimal?
    let activeEnergyKilocalories: Decimal?
    let averageHeartRateBPM: Decimal?
    let maxHeartRateBPM: Decimal?
    let updatedAt: Date

    var isGarminViaAppleHealth: Bool { provider == "apple_health" && source == "garmin" }
    var hasRecordedDuration: Bool { durationSeconds.isFinite && durationSeconds > 0 }
    var sourceDisplayName: String {
        if isGarminViaAppleHealth {
            return String(localized: "Garmin via Apple Health", bundle: .app, locale: .app)
        }
        return sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfHealthEmpty
            ?? String(localized: "Apple Health", bundle: .app, locale: .app)
    }
}

private extension String {
    nonisolated var nilIfHealthEmpty: String? { isEmpty ? nil : self }
}

nonisolated struct HealthIntegrationStatus: Equatable, Sendable {
    let enabled: Bool
    let consentVersion: String?
    let lastSyncedAt: Date?
    let importedCount: Int
    let updatedCount: Int
    let schemaVersion: Int
    let garminDirectAvailable: Bool
}

nonisolated struct HealthWorkoutSummaryPage: Sendable {
    let workouts: [HealthWorkoutSummary]
    let nextPage: Int?
}

nonisolated struct HealthImportSummary: Equatable, Sendable {
    let imported: Int
    let skippedOverlapping: Int
    let alreadyImported: Int
    var updated: Int = 0
    var linked: Int = 0

    static let nothing = HealthImportSummary(imported: 0, skippedOverlapping: 0, alreadyImported: 0)
    func adding(_ next: Self) -> Self {
        Self(imported: imported + next.imported,
             skippedOverlapping: skippedOverlapping + next.skippedOverlapping,
             alreadyImported: alreadyImported + next.alreadyImported,
             updated: updated + next.updated, linked: linked + next.linked)
    }
}

nonisolated enum HealthIntegrationFailure: Error {
    case unsupportedServer, malformedPage, consentRequired, unsupportedDevice
}

/// No token or health values are stored here. The opt-in belongs to this device,
/// this signed-in account and this API origin; another account must connect anew.
nonisolated struct HealthIntegrationScope: Hashable, Sendable {
    let accountID: Int
    let origin: String

    init(accountID: Int, serverURL: URL) {
        self.accountID = accountID
        let scheme = serverURL.scheme?.lowercased() ?? ""
        let host = serverURL.host?.lowercased() ?? ""
        let port = serverURL.port ?? (scheme == "https" ? 443 : 80)
        origin = "\(scheme)://\(host):\(port)"
    }

    var preferenceKey: String {
        let encoded = Data(origin.utf8).base64EncodedString()
        return "rytivo.health.connection.v1.\(encoded).\(accountID)"
    }
}

nonisolated enum HealthSyncPolicy {
    static let consentVersion = "apple-health-v1"
    static let batchSize = 100

    static func canUpload(generation: UUID, currentGeneration: UUID,
                          serverEnabled: Bool, deviceEnabled: Bool,
                          schemaSupported: Bool, cancelled: Bool) -> Bool {
        generation == currentGeneration && serverEnabled && deviceEnabled
            && schemaSupported && !cancelled
    }

    static func batches<Element>(_ elements: [Element]) -> [[Element]] {
        stride(from: 0, to: elements.count, by: batchSize).map {
            Array(elements[$0..<min($0 + batchSize, elements.count)])
        }
    }

    static func decimalString(_ value: Double?, places: Int = 2) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    }

    static func boundedDecimalString(_ value: Double?, range: ClosedRange<Double>, places: Int = 2) -> String? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return decimalString(value, places: places)
    }

    static func heartRates(average: Double?, maximum: Double?) -> (average: String?, maximum: String?) {
        let mean = boundedDecimalString(average, range: 20...300)
        let peak = boundedDecimalString(maximum, range: 20...300)
        // Conflicting statistics are not fixed by inventing a higher maximum.
        if mean != nil, peak != nil, let average, let maximum, average > maximum {
            return (mean, nil)
        }
        return (mean, peak)
    }

    static func label(_ value: String?, maximum: Int) -> String? {
        guard let value else { return nil }
        let filtered = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(maximum))
    }
}
