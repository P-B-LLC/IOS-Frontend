//
//  PlannerAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated planner operations.
//

import Foundation
import RepbaseAPI

actor PlannerAPIRepository {
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

    /// Every task and event between two dates, inclusive.
    ///
    /// One call serves the month grid, the week strip, and a day's list: they
    /// are the same data at three ranges, and asking three times would let them
    /// disagree with each other.
    func entries(from start: String, to end: String) async throws -> [PlannerEntry] {
        try await fetch(start: start, end: end)
    }

    /// Every task still unfinished before `day`, however old.
    ///
    /// Deliberately without a lower bound. Fetching a window and filtering on
    /// the device would mean a task older than the window was never reported,
    /// which is the one thing an overdue list must not do.
    /// Unfinished tasks between `since` and `day`, inclusive.
    ///
    /// Bounded at both ends now. Reading with no lower bound returned every
    /// task ever missed, which grows without limit and buries the ones still
    /// worth doing.
    func pastDueTasks(since: String, before day: String) async throws -> [PlannerEntry] {
        try await fetch(start: since, end: day, kind: .task, isComplete: false)
    }

    func upcomingEvents(from start: String, to end: String) async throws -> [PlannerEntry] {
        try await fetch(start: start, end: end, kind: .event)
    }

    private func fetch(
        start: String?,
        end: String?,
        kind: Operations.PlannerList.Input.Query.KindPayload? = nil,
        isComplete: Bool? = nil
    ) async throws -> [PlannerEntry] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [PlannerEntry] = []
        repeat {
            let output = try await client.plannerList(
                query: .init(
                    end: end,
                    isComplete: isComplete,
                    kind: kind,
                    page: page,
                    start: start
                )
            )
            let response: Components.Schemas.PaginatedPlannerEntryList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.map(Self.entry(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    // MARK: - Writing

    @discardableResult
    func create(_ draft: PlannerEntry) async throws -> PlannerEntry {
        let output = try await client.plannerCreate(
            body: .json(
                Components.Schemas.PlannerEntryRequest(
                    kind: Self.kindPayload(draft.kind),
                    title: draft.title,
                    category: Self.categoryPayload(draft.category),
                    scheduledDate: draft.date,
                    scheduledTime: draft.time,
                    isComplete: draft.isCompletable ? draft.isComplete : nil,
                    workout: draft.workoutID,
                    notes: draft.notes
                )
            )
        )
        switch output {
        case .created(let response):
            return Self.entry(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    @discardableResult
    func update(_ entry: PlannerEntry) async throws -> PlannerEntry {
        guard let serverID = entry.serverID else {
            throw APIServiceError.missingServerIdentifier("Planner entry")
        }

        let output = try await client.plannerPartialUpdate(
            path: .init(id: serverID),
            body: .json(
                Components.Schemas.PatchedPlannerEntryRequest(
                    kind: Self.kindPayload(entry.kind),
                    title: entry.title,
                    category: Self.categoryPayload(entry.category),
                    scheduledDate: entry.date,
                    scheduledTime: entry.time,
                    isComplete: entry.isCompletable ? entry.isComplete : nil,
                    workout: entry.workoutID,
                    notes: entry.notes
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.entry(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Ticks a task off, or puts it back. Sends only the completion so an edit
    /// in flight elsewhere cannot be overwritten by a stale copy of the row.
    @discardableResult
    func setComplete(_ entry: PlannerEntry, _ isComplete: Bool) async throws -> PlannerEntry {
        guard let serverID = entry.serverID else {
            throw APIServiceError.missingServerIdentifier("Planner entry")
        }

        let output = try await client.plannerPartialUpdate(
            path: .init(id: serverID),
            body: .json(
                Components.Schemas.PatchedPlannerEntryRequest(isComplete: isComplete)
            )
        )
        switch output {
        case .ok(let response):
            return Self.entry(from: try response.body.json)
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func delete(_ entry: PlannerEntry) async throws {
        guard let serverID = entry.serverID else {
            throw APIServiceError.missingServerIdentifier("Planner entry")
        }

        let output = try await client.plannerDestroy(path: .init(id: serverID))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Mapping

    private static func entry(
        from payload: Components.Schemas.PlannerEntry
    ) -> PlannerEntry {
        PlannerEntry(
            serverID: payload.id,
            kind: payload.kind.flatMap { PlannerKind(rawValue: $0.rawValue) } ?? .task,
            title: payload.title,
            category: payload.category
                .flatMap { PlannerCategory(rawValue: $0.rawValue) } ?? .other,
            date: payload.scheduledDate,
            time: payload.scheduledTime,
            isComplete: payload.isComplete ?? false,
            workoutID: payload.workout,
            workoutName: payload.workoutName,
            notes: payload.notes ?? ""
        )
    }

    private static func kindPayload(
        _ kind: PlannerKind
    ) -> Components.Schemas.PlannerEntryKindEnum {
        Components.Schemas.PlannerEntryKindEnum(rawValue: kind.rawValue) ?? .task
    }

    private static func categoryPayload(
        _ category: PlannerCategory
    ) -> Components.Schemas.CategoryEnum {
        Components.Schemas.CategoryEnum(rawValue: category.rawValue) ?? .other
    }

    // MARK: - Pagination

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
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}
