//
//  ActivityAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated step-count operations.
//
//  Health is where steps come from, but not where they are read back from.
//  The device sends what Health reported and then shows what the server
//  stored, so the number on screen is the same one every other client would
//  see rather than a local reading that happens to agree.
//

import Foundation
import RepbaseAPI

/// What an import did, counted.
///
/// Three numbers rather than one, because "nothing was added" has three very
/// different causes: nothing new to add, everything already added, or
/// everything skipped for clashing with a session Repbase recorded itself.
nonisolated struct HealthImportSummary: Equatable, Sendable {
    let imported: Int
    let skippedOverlapping: Int
    let alreadyImported: Int

    static let nothing = HealthImportSummary(
        imported: 0,
        skippedOverlapping: 0,
        alreadyImported: 0
    )
}

actor ActivityAPIRepository {
    private let configuration: APIConfiguration
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        self.configuration = configuration
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    // MARK: - Reading

    /// Every day the server holds on or after `start`, newest first.
    func steps(since start: Date) async throws -> [DailyStepCount] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [DailyStepCount] = []
        repeat {
            let output = try await client.stepCountsList(
                query: .init(page: page, since: Self.dayString(start))
            )
            let response: Components.Schemas.PaginatedDailyStepCountList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.compactMap(Self.day(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    // MARK: - Writing

    /// Stores a batch of days, replacing whatever was held for those days.
    ///
    /// Sent as one call rather than one per day because Health backfills: a
    /// watch that synced after a day offline changes yesterday's total as well
    /// as today's, and day-at-a-time writes would leave those corrections
    /// behind whenever the app was closed between them.
    /// Returns nothing. The server answers 204: it stores every day it was
    /// given in one go, so there is no page of results to hand back, and the
    /// caller reads the stored days through `steps(since:)` like any other
    /// reader rather than trusting an echo of what it just sent.
    func record(_ days: [DailyStepCount]) async throws {
        guard days.isEmpty == false else { return }

        let output = try await client.stepCountsRecordCreate(
            body: .json(
                Components.Schemas.DailyStepCountRecordRequest(
                    days: days.map {
                        Components.Schemas.DailyStepCountEntryRequest(
                            day: Self.dayString($0.day),
                            steps: $0.steps
                        )
                    }
                )
            )
        )

        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Offers Health's workouts to the server and reports what it did.
    ///
    /// Everything in the window is sent, including workouts already taken.
    /// Deciding here which are new would mean downloading the training history
    /// first, and the answer would still be the server's to give.
    func importWorkouts(_ workouts: [HealthWorkout]) async throws -> HealthImportSummary {
        guard workouts.isEmpty == false else { return .nothing }

        let output = try await client.sessionsImportHealthCreate(
            body: .json(
                Components.Schemas.HealthWorkoutImportRequest(
                    workouts: workouts.map {
                        Components.Schemas.HealthWorkoutRequest(
                            externalId: $0.externalID,
                            activity: Self.activity($0.activity),
                            startedAt: $0.startedAt,
                            endedAt: $0.endedAt,
                            distanceKm: Self.decimalString($0.distanceKilometres)
                        )
                    }
                )
            )
        )

        switch output {
        case .ok(let response):
            let result = try response.body.json
            return HealthImportSummary(
                imported: result.imported,
                skippedOverlapping: result.skippedOverlapping,
                alreadyImported: result.alreadyImported
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

    // MARK: - The step goal

    /// Steps a day the user is aiming for.
    ///
    /// Read from the profile rather than kept on the phone, so it follows
    /// the account the way target weight does.
    func stepGoal() async throws -> Int {
        switch try await client.meRetrieve() {
        case .ok(let response):
            return try response.body.json.dailyStepGoal ?? 8_000
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    @discardableResult
    func setStepGoal(_ steps: Int) async throws -> Int {
        let output = try await client.mePartialUpdate(
            body: .json(.init(dailyStepGoal: steps))
        )
        switch output {
        case .ok(let response):
            return try response.body.json.dailyStepGoal ?? steps
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private nonisolated static func activity(
        _ type: WorkoutType
    ) -> Components.Schemas.ActivityEnum {
        switch type {
        case .lifting: .lifting
        case .running: .running
        case .biking: .biking
        case .swimming: .swimming
        }
    }

    /// A decimal as a string, which is how the server sends and expects them.
    ///
    /// Putting a decimal through a JSON number gives away the exactness the
    /// type exists to keep, so the contract types it as a string at both ends.
    private nonisolated static func decimalString(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return String(format: "%.3f", value)
    }

    /// `YYYY-MM-DD` in the device's own calendar.
    ///
    /// A step count belongs to the day the user lived, not to a day computed
    /// in UTC: at 9pm in California an ISO-8601 UTC date is already tomorrow,
    /// and the evening walk would be filed under a day that has not happened.
    nonisolated static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    /// The reverse, in the same calendar. Returns nil for a day the device
    /// cannot place, rather than silently substituting today.
    nonisolated static func day(fromString value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    private nonisolated static func day(
        from payload: Components.Schemas.DailyStepCount
    ) -> DailyStepCount? {
        guard let day = day(fromString: payload.day) else { return nil }
        return DailyStepCount(day: day, steps: Int(payload.steps))
    }

    private func nextPage(
        _ next: String?,
        visited: inout Set<Int>
    ) throws -> Int? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              Self.sameOrigin(url, configuration.serverURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let pageValue = components.queryItems?
                .first(where: { $0.name == "page" })?.value,
              let page = Int(pageValue),
              page > 0,
              visited.insert(page).inserted else {
            throw APIServiceError.untrustedPaginationURL
        }
        return page
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
