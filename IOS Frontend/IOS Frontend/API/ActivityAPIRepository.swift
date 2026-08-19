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
    @discardableResult
    func record(_ days: [DailyStepCount]) async throws -> [DailyStepCount] {
        guard days.isEmpty == false else { return [] }

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
        case .ok(let response):
            return try response.body.json.compactMap(Self.day(from:))
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

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
