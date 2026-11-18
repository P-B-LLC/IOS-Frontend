import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepbaseAPI
import XCTest
@testable import AccountSafety

/// No network, credentials, private planner DTOs or timing-dependent sleeps.
/// Each response passes through the real generated client and app repository.
private actor CalendarSharingTransport: ClientTransport {
    struct Reply: Sendable {
        var status = 200
        let json: String
    }

    struct Sent: Sendable {
        let method: HTTPRequest.Method
        let path: String?
        let operation: String
        let body: Data
    }

    private var replies: [Reply]
    private(set) var sent: [Sent] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let bytes: Data
        if let body { bytes = try await Data(collecting: body, upTo: 1_048_576) }
        else { bytes = Data() }
        sent.append(.init(method: request.method, path: request.path, operation: operationID, body: bytes))
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        var response = HTTPResponse(status: .init(code: reply.status))
        response.headerFields[.contentType] = "application/json"
        return (response, reply.status == 204 ? nil : HTTPBody(Data(reply.json.utf8)))
    }
}

final class CalendarSharingTests: XCTestCase {
    private static let origin = URL(string: "https://calendar-tests.invalid")!
    private static let ownerJSON = #"{"id":7,"username":"maya","display_name":"Maya","profile_photo_url":"https://profiles.invalid/avatar.png"}"#
    private static let recipientJSON = #"{"id":9,"username":"lee","display_name":"","profile_photo_url":null}"#

    private static var itemJSON: String {
        #"{"id":"7:series:example:2026-11-04","share_id":12,"owner":\#(ownerJSON),"kind":"task","title":"Study together","category":"study","color":"teal","scheduling_timezone":"America/Chicago","scheduled_date":"2026-11-04","scheduled_time":"18:30:00","duration_minutes":45,"is_recurring":true,"is_complete":true}"#
    }

    private static var invitationJSON: String {
        #"{"id":12,"owner":\#(ownerJSON),"recipient":\#(recipientJSON),"scope":"series","status":"pending","starts_on":"2026-11-04","created_at":"2026-11-04T12:00:00Z","responded_at":null,"item":\#(itemJSON)}"#
    }

    private static func page(_ rows: [String], next: String? = nil) -> String {
        let nextJSON = next.map { "\"\($0)\"" } ?? "null"
        return #"{"count":\#(rows.count),"next":\#(nextJSON),"previous":null,"results":[\#(rows.joined(separator: ","))]}"#
    }

    private func repository(_ transport: CalendarSharingTransport) -> CalendarSharingAPIRepository {
        CalendarSharingAPIRepository(
            configuration: APIConfiguration(serverURL: Self.origin, allowsInsecureLocalhost: false),
            client: Client(serverURL: Self.origin, transport: transport)
        )
    }

    private func body(_ request: CalendarSharingTransport.Sent) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private func query(_ request: CalendarSharingTransport.Sent) throws -> [String: String] {
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(request.path), relativeTo: Self.origin))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: true))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testFollowerSearchUsesDedicatedEligibilityEndpointAndReturnsMinimalPeople() async throws {
        let transport = CalendarSharingTransport([.init(json: Self.page([Self.recipientJSON],
            next: "https://calendar-tests.invalid/api/v1/calendar/share-recipients/?page=3&search=Lee"))])
        let page = try await repository(transport).followers(search: "Lee", page: 2)
        XCTAssertEqual(page.nextPage, 3)
        let person = try XCTUnwrap(page.people.first)
        XCTAssertEqual(person.id, 9)
        XCTAssertEqual(person.name, "lee", "Closed or unnamed profiles must not invent a display name")
        XCTAssertNil(person.profilePhotoURL)
        let requests = await transport.sent
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.operation, "calendar_share_recipients_list")
        XCTAssertTrue(try XCTUnwrap(request.path).hasPrefix("/api/v1/calendar/share-recipients/?"))
        XCTAssertEqual(try query(request), ["page": "2", "search": "Lee"])
        XCTAssertEqual(Set(Mirror(reflecting: person).children.compactMap(\.label)),
                       ["id", "username", "displayName", "profilePhotoURL"])
    }

    func testOrdinaryInviteSendsOnlySourceRecipientsExplicitScopeAndNoReinvite() async throws {
        for scope in CalendarShareScope.allCases {
            let transport = CalendarSharingTransport([.init(status: 201, json: #"{"shares":[]}"#)])
            try await repository(transport).invite(entryID: 41, recipients: [9, 10], scope: scope)
            let requests = await transport.sent
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.method, .post)
            XCTAssertEqual(request.path, "/api/v1/calendar/shares/")
            XCTAssertEqual(request.operation, "calendar_shares_create")
            let sent = try body(request)
            XCTAssertEqual(Set(sent.keys), ["source_entry_id", "recipient_ids", "scope", "reinvite"])
            XCTAssertEqual(sent["source_entry_id"] as? Int, 41)
            XCTAssertEqual(sent["recipient_ids"] as? [Int], [9, 10])
            XCTAssertEqual(sent["scope"] as? String, scope.rawValue)
            XCTAssertEqual(sent["reinvite"] as? Bool, false)
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testConflictDoesNotSilentlyRetryOrReactivateDeclinedInvitation() async throws {
        let transport = CalendarSharingTransport([.init(status: 409,
            json: #"{"code":"reinvite_required","detail":"This follower needs a new invitation."}"#)])
        do {
            try await repository(transport).invite(entryID: 41, recipients: [9], scope: .series)
            XCTFail("Reinviting requires an explicit user action")
        } catch CalendarShareRequestFailure.requiresExplicitReinvite { }
        let requests = await transport.sent
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try body(try XCTUnwrap(requests.first))["reinvite"] as? Bool, false)
    }

    func testScopeConflictCannotBecomePermissionToReinviteOrWidenAccess() async throws {
        let transport = CalendarSharingTransport([.init(status: 409,
            json: #"{"code":"scope_conflict","detail":"The existing invitation begins on a later occurrence."}"#)])
        do {
            try await repository(transport).invite(entryID: 41, recipients: [9], scope: .series)
            XCTFail("A scope conflict is not consent to widen an existing share")
        } catch CalendarShareRequestFailure.scopeConflict { }
        let requests = await transport.sent
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try body(try XCTUnwrap(requests.first))["reinvite"] as? Bool, false)
    }

    func testExplicitReinviteChangesOnlyTheReinviteFlag() async throws {
        let transport = CalendarSharingTransport([.init(status: 201, json: #"{"shares":[]}"#)])
        try await repository(transport).invite(entryID: 41, recipients: [9], scope: .occurrence, reinvite: true)
        let requests = await transport.sent
        let sent = try body(try XCTUnwrap(requests.first))
        XCTAssertEqual(sent["reinvite"] as? Bool, true)
        XCTAssertEqual(sent["scope"] as? String, "occurrence")
        XCTAssertEqual(Set(sent.keys), ["source_entry_id", "recipient_ids", "scope", "reinvite"])
    }

    func testUnknownTypedConflictCannotAssumeConsentToReinvite() async throws {
        let transport = CalendarSharingTransport([.init(status: 409,
            json: #"{"code":"future_state_conflict","detail":"Refresh the invitation."}"#)])
        do {
            try await repository(transport).invite(entryID: 41, recipients: [9], scope: .series)
            XCTFail("An unknown conflict must remain a conflict")
        } catch CalendarShareRequestFailure.stateConflict { }
        let requests = await transport.sent
        XCTAssertEqual(requests.count, 1)
    }

    func testSharedDayDecodesReadOnlyProjectionNotEditablePlannerEntry() async throws {
        let transport = CalendarSharingTransport([.init(json: Self.page([Self.itemJSON]))])
        let plans = try await repository(transport).day(date: "2026-11-04", ownerIDs: [7])
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.owner.name, "Maya")
        XCTAssertEqual(plan.owner.profilePhotoURL?.absoluteString, "https://profiles.invalid/avatar.png")
        XCTAssertEqual(plan.date, "2026-11-04")
        XCTAssertEqual(plan.time, "18:30:00")
        XCTAssertEqual(plan.schedulingTimezone, "America/Chicago")
        XCTAssertEqual(plan.color, .teal)
        XCTAssertTrue(plan.isComplete)
        XCTAssertTrue(plan.isRecurring)
        XCTAssertTrue(plan.id.hasPrefix("7:series:"), "Shared identity must not masquerade as an editable integer planner ID")
        let labels = Set(Mirror(reflecting: plan).children.compactMap(\.label))
        XCTAssertEqual(labels, ["id", "shareID", "owner", "kind", "title", "category", "color", "schedulingTimezone",
                               "date", "time", "durationMinutes", "isComplete", "isRecurring"])
        XCTAssertTrue(labels.isDisjoint(with: ["notes", "subtasks", "workout", "workoutID", "serverID", "completedAt"]))
    }

    func testGeneratedSharedSchemaCannotRetainUnknownPrivatePayloadFields() async throws {
        let polluted = String(Self.itemJSON.dropLast()) + #", "notes":"PRIVATE NOTE", "subtasks":[{"title":"PRIVATE STEP"}], "workout_logs":[{"weight":999}]}"#
        let transport = CalendarSharingTransport([.init(json: Self.page([polluted]))])
        let client = Client(serverURL: Self.origin, transport: transport)
        let output = try await client.calendarSharedDayList(query: .init(date: "2026-11-04"))
        guard case .ok(let response) = output else { return XCTFail("Expected shared day") }
        let item = try XCTUnwrap(response.body.json.results.first)
        let encoded = try JSONEncoder().encode(item)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys
        XCTAssertTrue(Set(keys).isDisjoint(with: ["notes", "subtasks", "workout_logs", "workout", "completed_at"]))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("PRIVATE"))
    }

    func testInvitationDecodesOptionalWrappedItemAndCanSafelyHaveNoPreview() async throws {
        let withoutPreview = Self.invitationJSON.replacingOccurrences(of: Self.itemJSON, with: "null")
        let transport = CalendarSharingTransport([.init(json: Self.page([Self.invitationJSON, withoutPreview]))])
        let invitations = try await repository(transport).invitations()
        XCTAssertEqual(invitations.count, 2)
        XCTAssertEqual(invitations.first?.item?.title, "Study together")
        XCTAssertNil(invitations.last?.item)
        XCTAssertEqual(invitations.first?.scope, "series")
        XCTAssertTrue(try XCTUnwrap(invitations.first).isPending)
        XCTAssertNil(invitations.first?.appliesToSelectedOccurrence, "Older backend responses may omit this addition")
    }

    func testManagementCanReportExcludedOccurrenceWithoutAnItemPreview() async throws {
        let noPreview = Self.invitationJSON.replacingOccurrences(of: Self.itemJSON, with: "null")
        let privateOccurrence = String(noPreview.dropLast()) + #", "applies_to_selected_occurrence":false}"#
        let includedOccurrence = String(Self.invitationJSON.dropLast()) + #", "applies_to_selected_occurrence":true}"#
        let transport = CalendarSharingTransport([.init(json: Self.page([privateOccurrence, includedOccurrence]))])
        let invitations = try await repository(transport).sent(entryID: 41)
        XCTAssertEqual(invitations.first?.appliesToSelectedOccurrence, false)
        XCTAssertNil(invitations.first?.item)
        XCTAssertEqual(invitations.last?.appliesToSelectedOccurrence, true)
        XCTAssertEqual(invitations.last?.item?.title, "Study together")
    }

    func testDayPaginationKeepsOwnerAndDateFiltersAcrossEveryPage() async throws {
        let secondItem = Self.itemJSON.replacingOccurrences(of: "example:2026-11-04", with: "second:2026-11-04")
        let transport = CalendarSharingTransport([
            .init(json: Self.page([Self.itemJSON], next: "?page=2")),
            .init(json: Self.page([secondItem])),
        ])
        let result = try await repository(transport).day(date: "2026-11-04", ownerIDs: [7, 11])
        XCTAssertEqual(result.count, 2)
        let requests = await transport.sent
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try query(requests[0]), ["date": "2026-11-04", "owner_ids": "7,11"])
        XCTAssertEqual(try query(requests[1]), ["date": "2026-11-04", "owner_ids": "7,11", "page": "2"])
        XCTAssertEqual(Set(requests.map(\.operation)), ["calendar_shared_day_list"])
    }

    func testPeopleAndSentManagementFollowPagesWithoutUsingPrivatePlannerEndpoints() async throws {
        let people = CalendarSharingTransport([
            .init(json: Self.page([Self.ownerJSON], next: "https://calendar-tests.invalid:443/api/v1/calendar/shared/people/?page=2")),
            .init(json: Self.page([Self.recipientJSON])),
        ])
        let owners = try await repository(people).people()
        XCTAssertEqual(owners.map(\.id), [7, 9])
        let management = CalendarSharingTransport([
            .init(json: Self.page([Self.invitationJSON], next: "?page=2")),
            .init(json: Self.page([])),
        ])
        let grants = try await repository(management).sent(entryID: 41)
        XCTAssertEqual(grants.count, 1)
        let requests = await management.sent
        XCTAssertEqual(try query(requests[1]), ["page": "2", "source_entry_id": "41"])
        XCTAssertTrue(requests.allSatisfy { $0.operation == "calendar_shares_list" })
        XCTAssertTrue(requests.allSatisfy { !($0.path ?? "").contains("/planner/") })
    }

    func testHidingAllSharedOwnersSendsExplicitEmptyFilterBeforeMonthCounts() async throws {
        let transport = CalendarSharingTransport([.init(json: #"{"days":[]}"#)])
        let days = try await repository(transport).month(start: "2026-11-01", end: "2026-12-12", ownerIDs: [])
        XCTAssertTrue(days.isEmpty)
        let requests = await transport.sent
        XCTAssertEqual(try query(try XCTUnwrap(requests.first)),
                       ["start": "2026-11-01", "end": "2026-12-12", "owner_ids": ""])
    }

    func testUntrustedPaginationNeverTriggersAnotherRequest() async throws {
        for next in [
            "https://other.invalid/api/v1/calendar/shared/people/?page=2",
            "http://calendar-tests.invalid/api/v1/calendar/shared/people/?page=2",
            "https://calendar-tests.invalid:444/api/v1/calendar/shared/people/?page=2",
            "?page=0", "?page=-1", "?page=2.5", "?page=invalid", "?cursor=2",
        ] {
            let transport = CalendarSharingTransport([.init(json: Self.page([], next: next))])
            do {
                _ = try await repository(transport).people()
                XCTFail("Expected an untrusted pagination error for \(next)")
            } catch APIServiceError.untrustedPaginationURL { }
            let requests = await transport.sent
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testRepeatedPaginationPageStopsInsteadOfLooping() async throws {
        let transport = CalendarSharingTransport([
            .init(json: Self.page([], next: "?page=2")),
            .init(json: Self.page([], next: "?page=2")),
        ])
        do {
            _ = try await repository(transport).invitations()
            XCTFail("A repeated page must terminate the read")
        } catch APIServiceError.untrustedPaginationURL { }
        let requests = await transport.sent
        XCTAssertEqual(requests.count, 2)
    }

    func testAcceptDeclineRevokeAndPrivacyUseOnlyScopedSharingOperations() async throws {
        let transport = CalendarSharingTransport([
            .init(json: Self.invitationJSON), .init(json: Self.invitationJSON),
            .init(json: Self.invitationJSON), .init(status: 204, json: ""),
        ])
        let repository = repository(transport)
        try await repository.respond(id: 12, accept: true)
        try await repository.respond(id: 12, accept: false)
        try await repository.revoke(id: 12)
        try await repository.makePrivate(entryID: 41, scope: .occurrence)
        let requests = await transport.sent
        XCTAssertEqual(requests.map(\.path), [
            "/api/v1/calendar/invitations/12/accept/", "/api/v1/calendar/invitations/12/decline/",
            "/api/v1/calendar/shares/12/revoke/", "/api/v1/calendar/shares/privacy/",
        ])
        XCTAssertTrue(requests.allSatisfy { $0.method == .post })
        XCTAssertTrue(requests.prefix(3).allSatisfy { $0.body.isEmpty })
        let privacy = try body(requests[3])
        XCTAssertEqual(privacy["scope"] as? String, "occurrence")
        XCTAssertEqual(privacy["source_entry_id"] as? Int, 41)
        XCTAssertEqual(Set(privacy.keys), ["source_entry_id", "scope"])
    }

    func testPermissionFailureDoesNotFallBackToTheOwnerPlanner() async throws {
        for status in [401, 403, 404, 429, 500] {
            let transport = CalendarSharingTransport([.init(status: status, json: #"{"detail":"Not available."}"#)])
            do {
                _ = try await repository(transport).day(date: "2026-11-04", ownerIDs: [7])
                XCTFail("Expected failure for \(status)")
            } catch { XCTAssertEqual((error as? RepbaseAPIHTTPError)?.statusCode, status) }
            let requests = await transport.sent
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.operation, "calendar_shared_day_list")
        }
    }

    // Source-level boundary checks keep the SwiftUI PlannerStore out of this
    // Foundation target while covering account/request-generation isolation.
    private func source(_ relative: String) throws -> String {
        let repository = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: repository).appendingPathComponent(relative), encoding: .utf8)
    }

    func testDisplayOnlyStoreDropsOldAccountAndOvertakenReadResults() throws {
        let store = try source("IOS Frontend/IOS Frontend/Stores/CalendarSharingStore.swift")
        XCTAssertTrue(store.contains("generation = UUID(); readID = UUID(); repository = nil"))
        XCTAssertTrue(store.contains("monthDays = []; dayItems = []; invitations = []; people = []"))
        XCTAssertTrue(store.contains("hiddenOwnerIDs = []; showsOwn = true"))
        XCTAssertTrue(store.contains("lastLoadedDay = nil"))
        XCTAssertTrue(store.contains("guard account == generation, request == readID, !Task.isCancelled else { return }"))
        XCTAssertTrue(store.contains("guard account == generation, !Task.isCancelled else { throw CancellationError() }"))
        XCTAssertFalse(store.contains("PlannerStore()"))
        XCTAssertFalse(store.contains("NotificationScheduler"))
        XCTAssertFalse(store.contains("planner.save("))
        XCTAssertFalse(store.contains("planner.setCompletion("))
    }

    func testSharedDomainCannotBeWrittenAsAnOwnPlannerDraft() throws {
        let models = try source("IOS Frontend/IOS Frontend/Models/CalendarSharing.swift")
        XCTAssertTrue(models.contains("struct SharedCalendarPlan"))
        XCTAssertFalse(models.contains("PlannerEntry("))
        XCTAssertFalse(models.contains("FoodEntry("))
        XCTAssertFalse(models.contains("var notes"))
        XCTAssertFalse(models.contains("var subtasks"))
        let api = try source("IOS Frontend/IOS Frontend/API/CalendarSharingAPIRepository.swift")
        XCTAssertFalse(api.contains("client.planner"), "A read grant must never enter owner-only create/update/completion methods")
        XCTAssertFalse(api.contains("URLSession.shared"), "Calendar transport must stay on generated authenticated operations")
    }
}
