import Foundation
import RepbaseAPI

enum CalendarShareRequestFailure: Error { case requiresExplicitReinvite, scopeConflict, stateConflict }

/// Only generated operations from the calendar contract. No private planner
/// payload is ever decoded into an editable entry through this repository.
actor CalendarSharingAPIRepository {
    private let client: Client
    private let configuration: APIConfiguration

    init(configuration: APIConfiguration, client: Client) {
        self.configuration = configuration
        self.client = client
    }

    init(configuration: APIConfiguration, token: String) throws {
        self.configuration = configuration
        client = try RepbaseAPIClientFactory.makeAuthenticated(serverURL: configuration.serverURL,
            token: token, allowInsecureLocalhost: configuration.allowsInsecureLocalhost)
    }

    func followers(search: String, page: Int?) async throws -> CalendarFollowerPage {
        let output = try await client.calendarShareRecipientsList(query: .init(page: page, search: search))
        switch output {
        case .ok(let response):
            let result = try response.body.json
            return CalendarFollowerPage(people: result.results.map(Self.person), nextPage: try pageNumber(result.next))
        case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
        }
    }

    func people() async throws -> [CalendarSharePerson] {
        var page: Int?, visited: Set<Int> = [], values: [CalendarSharePerson] = []
        repeat {
            let output = try await client.calendarSharedPeopleList(query: .init(page: page))
            switch output {
            case .ok(let response):
                let result = try response.body.json
                values += result.results.map(Self.person)
                page = try nextPage(result.next, visited: &visited)
            case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
            }
        } while page != nil
        return values
    }

    func month(start: String, end: String, ownerIDs: [Int]) async throws -> [SharedCalendarMonthDay] {
        let output = try await client.calendarSharedMonthRetrieve(query: .init(
            end: end, ownerIds: ownerIDs.map(String.init).joined(separator: ","), start: start))
        switch output {
        case .ok(let response):
            return try response.body.json.days.map {
                SharedCalendarMonthDay(date: $0.date, total: $0.total, items: $0.items.map(Self.plan))
            }
        case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
        }
    }

    func day(date: String, ownerIDs: [Int]) async throws -> [SharedCalendarPlan] {
        var page: Int?, visited: Set<Int> = [], values: [SharedCalendarPlan] = []
        repeat {
            let output = try await client.calendarSharedDayList(query: .init(
                date: date, ownerIds: ownerIDs.map(String.init).joined(separator: ","), page: page))
            switch output {
            case .ok(let response):
                let result = try response.body.json
                values += result.results.map(Self.plan)
                page = try nextPage(result.next, visited: &visited)
            case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
            }
        } while page != nil
        return values
    }

    func invitations() async throws -> [CalendarShareInvitation] {
        var page: Int?, visited: Set<Int> = [], values: [CalendarShareInvitation] = []
        repeat {
            let output = try await client.calendarInvitationsList(query: .init(page: page))
            switch output {
            case .ok(let response):
                let result = try response.body.json
                values += result.results.map(Self.invitation)
                page = try nextPage(result.next, visited: &visited)
            case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
            }
        } while page != nil
        return values
    }

    func sent(entryID: Int) async throws -> [CalendarShareInvitation] {
        var page: Int?, visited: Set<Int> = [], values: [CalendarShareInvitation] = []
        repeat {
            let output = try await client.calendarSharesList(query: .init(page: page, sourceEntryId: entryID))
            switch output {
            case .ok(let response):
                let result = try response.body.json
                values += result.results.map(Self.invitation)
                page = try nextPage(result.next, visited: &visited)
            case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
            }
        } while page != nil
        return values
    }

    func invite(entryID: Int, recipients: [Int], scope: CalendarShareScope, reinvite: Bool = false) async throws {
        let output = try await client.calendarSharesCreate(body: .json(.init(
            sourceEntryId: entryID, recipientIds: recipients,
            scope: .init(value1: scope == .series ? .series : .occurrence), reinvite: reinvite)))
        switch output {
        case .ok, .created: return
        case .conflict(let response):
            let conflictCode = try response.body.json.code
            switch conflictCode {
            case "reinvite_required": throw CalendarShareRequestFailure.requiresExplicitReinvite
            case "scope_conflict": throw CalendarShareRequestFailure.scopeConflict
            default: throw CalendarShareRequestFailure.stateConflict
            }
        case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
        }
    }

    func respond(id: Int, accept: Bool) async throws {
        if accept {
            let output = try await client.calendarInvitationsAcceptCreate(path: .init(id: id))
            switch output {
            case .ok: return
            case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
            }
        } else {
            let output = try await client.calendarInvitationsDeclineCreate(path: .init(id: id))
            switch output {
            case .ok: return
            case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
            }
        }
    }

    func revoke(id: Int) async throws {
        let output = try await client.calendarSharesRevokeCreate(path: .init(id: id))
        switch output {
        case .ok: return
        case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
        }
    }

    func makePrivate(entryID: Int, scope: CalendarShareScope) async throws {
        let output = try await client.calendarSharesPrivacyCreate(body: .json(.init(
            sourceEntryId: entryID, scope: .init(value1: scope == .series ? .series : .occurrence))))
        switch output {
        case .noContent: return
        case .undocumented(let code, let payload): throw await RepbaseAPIHTTPError.decode(statusCode: code, payload: payload)
        }
    }

    private static func person(_ wire: Components.Schemas.CalendarPerson) -> CalendarSharePerson {
        CalendarSharePerson(id: wire.id, username: wire.username, displayName: wire.displayName,
                            profilePhotoURL: wire.profilePhotoUrl.flatMap(URL.init(string:)))
    }

    private static func plan(_ wire: Components.Schemas.SharedCalendarItem) -> SharedCalendarPlan {
        SharedCalendarPlan(id: wire.id, shareID: wire.shareId, owner: person(wire.owner), kind: wire.kind,
            title: wire.title, category: wire.category, color: PlannerItemColor(rawValue: wire.color),
            schedulingTimezone: wire.schedulingTimezone, date: wire.scheduledDate, time: wire.scheduledTime,
            durationMinutes: wire.durationMinutes, isComplete: wire.isComplete, isRecurring: wire.isRecurring)
    }

    private static func invitation(_ wire: Components.Schemas.CalendarShare) -> CalendarShareInvitation {
        CalendarShareInvitation(id: wire.id, owner: person(wire.owner), recipient: person(wire.recipient),
            scope: wire.scope, status: wire.status, startsOn: wire.startsOn,
            item: wire.item.map { plan($0.value1) }, appliesToSelectedOccurrence: wire.appliesToSelectedOccurrence)
    }

    private func pageNumber(_ next: String?) throws -> Int? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              url.scheme?.lowercased() == configuration.serverURL.scheme?.lowercased(),
              url.host?.lowercased() == configuration.serverURL.host?.lowercased(),
              (url.port ?? (url.scheme == "https" ? 443 : 80)) ==
                (configuration.serverURL.port ?? (configuration.serverURL.scheme == "https" ? 443 : 80)),
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "page" })?.value,
              let page = Int(raw), page > 0 else { throw APIServiceError.untrustedPaginationURL }
        return page
    }

    private func nextPage(_ next: String?, visited: inout Set<Int>) throws -> Int? {
        guard let page = try pageNumber(next) else { return nil }
        guard visited.count < 100, visited.insert(page).inserted else { throw APIServiceError.untrustedPaginationURL }
        return page
    }
}
