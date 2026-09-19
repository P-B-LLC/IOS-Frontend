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
    private let recoveryScope: EditorDraftRecovery.Scope?

    init(configuration: APIConfiguration, token: String, recoveryScope: EditorDraftRecovery.Scope? = nil) throws {
        self.configuration = configuration
        self.recoveryScope = recoveryScope
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    // Every `.undocumented` case below decodes the response rather than
    // throwing the bare status. The server names the field it refused and
    // says why; discarding that turned "the repeat has to end after the day
    // it starts" into "HTTP 400", which the one person who could act on it
    // could not see. `RepbaseAPIHTTPError.decode` reads 400, 409 and 422 and
    // falls back to the generic wording for everything else.

    // MARK: - Reading

    /// Every task and event between two dates, inclusive.
    ///
    /// One call serves the month grid, the week strip, and a day's list: they
    /// are the same data at three ranges, and asking three times would let them
    /// disagree with each other.
    func entries(from start: String, to end: String) async throws -> [PlannerEntry] {
        try await fetch(start: start, end: end)
    }

    /// Unfinished tasks between `since` and `day`, inclusive.
    ///
    /// Bounded at both ends. It used to have no lower bound, so that a task
    /// older than any window was still reported; in practice that returned
    /// every task ever missed, and the ones still worth doing were buried
    /// under them. Anything older stays on its own day.
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
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
            }
            values.append(contentsOf: response.results.map(Self.entry(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    // MARK: - Writing

    /// Asks the server to give every scheduled day in the range a planner task,
    /// and returns the ones it made.
    ///
    /// The app used to do this itself: read the planner, work out which
    /// scheduled workouts had no task, and create one for each. It could not
    /// tell a day the user had cleared from a day never offered, so a deleted
    /// task came back on the next launch. Only the server can tell those
    /// apart, because only the server remembers having asked.
    func syncScheduledWorkouts(
        from start: String,
        to end: String
    ) async throws -> [PlannerEntry] {
        let output = try await client.schedulesSyncPlannerCreate(
            body: .json(Components.Schemas.PlannerSyncRequest(start: start, end: end))
        )
        switch output {
        case .ok(let response):
            return try response.body.json.map(Self.entry(from:))
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    @discardableResult
    func create(_ draft: PlannerEntry) async throws -> PlannerEntry {
        let desired = draft
        let operationKey = "create-planner-\(draft.id)"
        var draft = draft
        if let recoveryScope {
            draft = try await EditorDraftRecovery.shared.capture(draft, key: operationKey, scope: recoveryScope)
        }
        let output = try await client.plannerCreate(
            headers: .init(idempotencyKey: draft.id.uuidString),
            body: .json(
                Components.Schemas.PlannerEntryRequest(
                    kind: Self.kindPayload(draft.kind),
                    title: draft.title,
                    category: Self.categoryPayload(draft.category),
                    priority: Self.priorityPayload(draft.priority),
                    scheduledDate: draft.date,
                    scheduledTime: draft.time,
                    durationMinutes: draft.durationMinutes,
                    isComplete: draft.isCompletable ? draft.isComplete : nil,
                    workout: draft.workoutID,
                    notes: draft.notes,
                    parent: draft.parentID,
                    repeatEveryDays: draft.repeatEveryDays,
                    repeatEndsOn: draft.repeatEndsOn
                )
            )
        )
        switch output {
        case .created(let response):
            var saved = Self.entry(from: try response.body.json)
            if desired != draft {
                var revision = desired
                revision.serverID = saved.serverID
                saved = try await update(revision)
            }
            if let recoveryScope { try await EditorDraftRecovery.shared.remove(key: operationKey, scope: recoveryScope) }
            return saved
        case .undocumented(let statusCode, let payload):
            if statusCode == 400, let recoveryScope { try await EditorDraftRecovery.shared.remove(key: operationKey, scope: recoveryScope) }
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    @discardableResult
    func update(_ entry: PlannerEntry) async throws -> PlannerEntry {
        guard let serverID = entry.serverID else {
            throw APIServiceError.missingServerIdentifier("Planner entry")
        }

        // PUT, not PATCH.
        //
        // A PATCH that omits a field means "leave that one alone", and the
        // generated request omits any nil rather than sending null -- so
        // through PATCH there was no way to take a time, or a length, back off
        // once it had been set. Turning "Set a time" off saved silently and
        // changed nothing.
        //
        // PUT replaces, which is what saving a whole editor full of fields
        // actually means. The server clears the schedule fields this leaves
        // out; `setComplete` below stays on PATCH, where omitting everything
        // else is exactly the point.
        let output = try await client.plannerUpdate(
            path: .init(id: serverID),
            body: .json(
                Components.Schemas.PlannerEntryRequest(
                    kind: Self.kindPayload(entry.kind),
                    title: entry.title,
                    category: Self.categoryPayload(entry.category),
                    priority: Self.priorityPayload(entry.priority),
                    scheduledDate: entry.date,
                    scheduledTime: entry.time,
                    durationMinutes: entry.durationMinutes,
                    isComplete: entry.isCompletable ? entry.isComplete : nil,
                    workout: entry.workoutID,
                    notes: entry.notes
                )
            )
        )
        switch output {
        case .ok(let response):
            return Self.entry(from: try response.body.json)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
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
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    // MARK: - Steps
    //
    // A step is an ordinary planner row with a parent, so these are the same
    // three calls by server id. They are separate because the day holds steps
    // as `PlannerSubtask` rather than as whole entries — the server nests them
    // and leaves them out of the list, so the app never has a full row for one.
    //
    // Each answers with the *parent*, because the parent's own completion is
    // derived from its steps and changing one can finish or reopen it. Taking
    // the server's copy is what keeps the heading honest.

    func addSubtask(toParent parentID: Int, title: String, on date: String) async throws -> PlannerEntry {
        let output = try await client.plannerCreate(
            headers: .init(idempotencyKey: UUID().uuidString),
            body: .json(
                Components.Schemas.PlannerEntryRequest(
                    kind: Self.kindPayload(.task),
                    title: title,
                    category: Self.categoryPayload(.other),
                    priority: Self.priorityPayload(.normal),
                    // The server overwrites this with the parent's day; the
                    // contract requires it regardless.
                    scheduledDate: date,
                    parent: parentID
                )
            )
        )
        switch output {
        case .created:
            return try await entry(withServerID: parentID)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    func setSubtaskComplete(
        _ subtask: PlannerSubtask,
        _ isComplete: Bool,
        parentID: Int
    ) async throws -> PlannerEntry {
        let output = try await client.plannerPartialUpdate(
            path: .init(id: subtask.serverID),
            body: .json(
                Components.Schemas.PatchedPlannerEntryRequest(isComplete: isComplete)
            )
        )
        switch output {
        case .ok:
            return try await entry(withServerID: parentID)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    func deleteSubtask(_ subtask: PlannerSubtask, parentID: Int) async throws -> PlannerEntry {
        let output = try await client.plannerDestroy(path: .init(id: subtask.serverID))
        switch output {
        case .noContent:
            return try await entry(withServerID: parentID)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    private func entry(withServerID serverID: Int) async throws -> PlannerEntry {
        let output = try await client.plannerRetrieve(path: .init(id: serverID))
        switch output {
        case .ok(let response):
            return Self.entry(from: try response.body.json)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    /// Remove one entry, or end the repeat it belongs to.
    ///
    /// `endsRepeat` is the wider act and is never the default: a delete that
    /// quietly took a year of tasks with it is the worst kind of surprise, so
    /// the caller has to ask for it.
    func delete(_ entry: PlannerEntry, endsRepeat: Bool = false) async throws {
        guard let serverID = entry.serverID else {
            throw APIServiceError.missingServerIdentifier("Planner entry")
        }

        let output = try await client.plannerDestroy(
            path: .init(id: serverID),
            query: .init(scope: endsRepeat ? .following : nil)
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
        }
    }

    // MARK: - Mapping

    private static func entry(
        from payload: Components.Schemas.PlannerEntry
    ) -> PlannerEntry {
        PlannerEntry(
            id: .stable(forServerID: payload.id),
            serverID: payload.id,
            kind: payload.kind.flatMap { PlannerKind(rawValue: $0.value1.rawValue) } ?? .task,
            title: payload.title,
            category: payload.category
                .flatMap { PlannerCategory(rawValue: $0.rawValue) } ?? .other,
            // Absent means the row predates the field, which is exactly what
            // "nobody chose one" looks like.
            priority: payload.priority
                .flatMap { PlannerPriority(rawValue: $0.rawValue) } ?? .normal,
            date: payload.scheduledDate,
            time: payload.scheduledTime,
            durationMinutes: payload.durationMinutes,
            isComplete: payload.isComplete ?? false,
            workoutID: payload.workout,
            workoutName: payload.workoutName,
            notes: payload.notes ?? "",
            parentID: payload.parent,
            subtasks: payload.subtasks.map(subtask(from:)),
            repeatIntervalDays: payload.repeatIntervalDays
        )
    }

    private static func subtask(
        from payload: Components.Schemas.PlannerSubtask
    ) -> PlannerSubtask {
        PlannerSubtask(
            id: .stable(forServerID: payload.id),
            serverID: payload.id,
            title: payload.title,
            isComplete: payload.isComplete
        )
    }

    /// Wrapped, because `kind` now carries a default in the contract and the
    /// generator emits a field with a default as a payload around the enum
    /// rather than the enum itself. The default appeared when the planner
    /// gained its uniqueness constraint: the condition names `kind`, so DRF
    /// began describing that field's default in the schema.
    /// One of them now: only the create and full-update requests carry a
    /// kind, and both use the same nested payload type.
    private static func kindEnum(
        _ kind: PlannerKind
    ) -> Components.Schemas.PlannerEntryKindEnum {
        Components.Schemas.PlannerEntryKindEnum(rawValue: kind.rawValue) ?? .task
    }

    private static func kindPayload(
        _ kind: PlannerKind
    ) -> Components.Schemas.PlannerEntryRequest.KindPayload {
        .init(value1: kindEnum(kind))
    }

    private static func categoryPayload(
        _ category: PlannerCategory
    ) -> Components.Schemas.CategoryEnum {
        Components.Schemas.CategoryEnum(rawValue: category.rawValue) ?? .other
    }

    /// One type for both requests, unlike `kind`: `priority` carries a default
    /// in the contract but no `allOf` around it, so the generator emitted the
    /// enum itself rather than a payload per request.
    private static func priorityPayload(
        _ priority: PlannerPriority
    ) -> Components.Schemas.PriorityEnum {
        Components.Schemas.PriorityEnum(rawValue: priority.rawValue) ?? .normal
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
