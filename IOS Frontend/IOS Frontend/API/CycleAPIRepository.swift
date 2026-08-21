//
//  CycleAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated rotation operations.
//
//  Where the rotation is today, and what is next, are read from the server
//  rather than worked out here. Two devices disagreeing about which day of an
//  eight-day split it is would be worse than not showing the day at all.
//

import Foundation
import RepbaseAPI

actor CycleAPIRepository {
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

    /// Rotations in force. Closed ones are left out: they exist so the past
    /// still resolves, not so they can be listed.
    func cycles() async throws -> [WorkoutCycle] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [WorkoutCycle] = []
        repeat {
            let output = try await client.cyclesList(query: .init(page: page))
            let response: Components.Schemas.PaginatedWorkoutCycleList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.compactMap(Self.cycle(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    // MARK: - Writing

    @discardableResult
    func create(_ draft: WorkoutCycleDraft) async throws -> WorkoutCycle {
        let output = try await client.cyclesCreate(
            body: .json(
                Components.Schemas.WorkoutCycleRequest(
                    name: draft.name,
                    length: draft.length,
                    anchorDate: Self.dayString(draft.anchorDate),
                    slots: draft.slots.map(Self.slotPayload)
                )
            )
        )
        switch output {
        case .created(let response):
            guard let cycle = Self.cycle(from: try response.body.json) else {
                throw APIServiceError.malformedResponse
            }
            return cycle
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    @discardableResult
    func update(_ cycle: WorkoutCycle) async throws -> WorkoutCycle {
        let output = try await client.cyclesPartialUpdate(
            path: .init(id: cycle.id),
            body: .json(
                Components.Schemas.PatchedWorkoutCycleRequest(
                    name: cycle.name,
                    length: cycle.length,
                    anchorDate: Self.dayString(cycle.anchorDate),
                    slots: cycle.orderedSlots.map(Self.slotPayload)
                )
            )
        )
        switch output {
        case .ok(let response):
            guard let updated = Self.cycle(from: try response.body.json) else {
                throw APIServiceError.malformedResponse
            }
            return updated
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func delete(_ cycle: WorkoutCycle) async throws {
        let output = try await client.cyclesDestroy(path: .init(id: cycle.id))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Writes schedule rows for the rotation up to a date.
    @discardableResult
    func planAhead(_ cycle: WorkoutCycle, through: Date) async throws -> WorkoutCycle {
        let output = try await client.cyclesPlanAheadCreate(
            path: .init(id: cycle.id),
            body: .json(
                Components.Schemas.CyclePlanAheadRequest(
                    through: Self.dayString(through)
                )
            )
        )
        switch output {
        case .ok(let response):
            guard let planned = Self.cycle(from: try response.body.json) else {
                throw APIServiceError.malformedResponse
            }
            return planned
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Pushes the rest of the rotation back, after an unplanned rest day.
    func shift(_ cycle: WorkoutCycle, byDays days: Int) async throws -> (WorkoutCycle, CycleShiftOutcome) {
        let output = try await client.cyclesShiftCreate(
            path: .init(id: cycle.id),
            body: .json(Components.Schemas.CycleShiftRequest(days: days))
        )
        return try Self.shiftResult(from: output)
    }

    /// Re-anchors so the workout that is owed happens today.
    func resumeToday(_ cycle: WorkoutCycle) async throws -> (WorkoutCycle, CycleShiftOutcome) {
        let output = try await client.cyclesResumeTodayCreate(path: .init(id: cycle.id))
        return try Self.shiftResult(from: output)
    }

    // MARK: - Mapping

    private static func shiftResult(
        from output: Operations.CyclesShiftCreate.Output
    ) throws -> (WorkoutCycle, CycleShiftOutcome) {
        switch output {
        case .ok(let response):
            let result = try response.body.json
            guard let cycle = cycle(from: result.cycle) else {
                throw APIServiceError.malformedResponse
            }
            return (
                cycle,
                CycleShiftOutcome(
                    daysShifted: result.daysShifted,
                    removed: result.removed,
                    scheduled: result.scheduled,
                    kept: result.kept
                )
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private static func shiftResult(
        from output: Operations.CyclesResumeTodayCreate.Output
    ) throws -> (WorkoutCycle, CycleShiftOutcome) {
        switch output {
        case .ok(let response):
            let result = try response.body.json
            guard let cycle = cycle(from: result.cycle) else {
                throw APIServiceError.malformedResponse
            }
            return (
                cycle,
                CycleShiftOutcome(
                    daysShifted: result.daysShifted,
                    removed: result.removed,
                    scheduled: result.scheduled,
                    kept: result.kept
                )
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private nonisolated static func cycle(
        from payload: Components.Schemas.WorkoutCycle
    ) -> WorkoutCycle? {
        guard let anchor = day(fromString: payload.anchorDate) else { return nil }

        return WorkoutCycle(
            id: payload.id,
            name: payload.name ?? "",
            length: payload.length,
            anchorDate: anchor,
            slots: payload.slots.map { slot in
                WorkoutCycleSlot(
                    serverID: slot.id,
                    position: Int(slot.position),
                    workoutID: slot.workout,
                    workoutName: slot.workoutName
                )
            },
            endedOn: payload.effectiveUntil.flatMap(day(fromString:)),
            currentPosition: payload.currentPosition,
            currentWorkoutName: payload.currentWorkoutName,
            nextWorkoutName: payload.nextWorkoutName,
            // Empty when the rotation has no workouts left to offer, which is
            // a real state rather than a parse failure.
            nextWorkoutDate: day(fromString: payload.nextWorkoutDate)
        )
    }

    private nonisolated static func slotPayload(
        _ slot: WorkoutCycleSlot
    ) -> Components.Schemas.WorkoutCycleSlotRequest {
        Components.Schemas.WorkoutCycleSlotRequest(
            position: Int64(slot.position),
            workout: slot.workoutID
        )
    }

    /// `YYYY-MM-DD` in the device's own calendar, as every date this app sends.
    nonisolated static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    nonisolated static func day(fromString value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
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
