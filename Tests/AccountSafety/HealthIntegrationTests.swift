import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepbaseAPI
import XCTest
@testable import AccountSafety

private actor HealthIntegrationTransport: ClientTransport {
    struct Reply: Sendable { var status = 200; let json: String }
    struct Sent: Sendable { let path: String?; let method: HTTPRequest.Method; let body: Data }
    var replies: [Reply]
    private(set) var sent: [Sent] = []
    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let bytes: Data
        if let body { bytes = try await Data(collecting: body, upTo: 1_048_576) }
        else { bytes = Data() }
        sent.append(.init(path: request.path, method: request.method, body: bytes))
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = replies.removeFirst()
        var response = HTTPResponse(status: .init(code: reply.status))
        response.headerFields[.contentType] = "application/json"
        return (response, reply.status == 204 ? nil : HTTPBody(Data(reply.json.utf8)))
    }
}

final class HealthIntegrationTests: XCTestCase {
    private static let origin = URL(string: "https://health-tests.invalid")!
    private static let status = #"{"enabled":true,"consent_version":"apple-health-v1","last_sync_at":null,"last_sync_imported_count":0,"last_sync_updated_count":0,"schema_version":1,"garmin_direct_available":false}"#
    private func repository(_ transport: HealthIntegrationTransport) -> ActivityAPIRepository {
        ActivityAPIRepository(configuration: .init(serverURL: Self.origin, allowsInsecureLocalhost: false),
                              client: Client(serverURL: Self.origin, transport: transport))
    }
    private func workout() -> HealthWorkout {
        HealthWorkout(externalID: "FC47E26E-4C8B-4CF2-B5C0-C02DA38E6557", activity: .running,
                      workoutActivity: .walking, startedAt: Date(timeIntervalSince1970: 1000),
                      endedAt: Date(timeIntervalSince1970: 2200), distanceKilometres: 1.625,
                      energyKilocalories: 112.25, durationSeconds: 900,
                      averageHeartRateBPM: nil, maxHeartRateBPM: nil,
                      sourceName: "Test source", sourceBundleID: "test.source", deviceName: nil)
    }

    func testConsentScopeSeparatesAccountsOriginsAndSchemes() {
        let first = HealthIntegrationScope(accountID: 7, serverURL: Self.origin)
        XCTAssertNotEqual(first.preferenceKey, HealthIntegrationScope(accountID: 8, serverURL: Self.origin).preferenceKey)
        XCTAssertNotEqual(first.preferenceKey, HealthIntegrationScope(accountID: 7, serverURL: URL(string: "https://another.invalid")!).preferenceKey)
        XCTAssertNotEqual(first.preferenceKey, HealthIntegrationScope(accountID: 7, serverURL: URL(string: "http://health-tests.invalid")!).preferenceKey)
        XCTAssertEqual(first.preferenceKey, HealthIntegrationScope(accountID: 7, serverURL: URL(string: "https://HEALTH-TESTS.invalid:443/")!).preferenceKey)
        XCTAssertFalse(first.preferenceKey.contains("token"))
    }

    func testEveryUploadRequiresCurrentAccountAndBothExplicitConsents() {
        let current = UUID()
        XCTAssertTrue(HealthSyncPolicy.canUpload(generation: current, currentGeneration: current,
                                                serverEnabled: true, deviceEnabled: true, schemaSupported: true, cancelled: false))
        for (server, device, supported, cancelled) in [(false,true,true,false),(true,false,true,false),
                                                       (true,true,false,false),(true,true,true,true)] {
            XCTAssertFalse(HealthSyncPolicy.canUpload(generation: current, currentGeneration: current,
                                                     serverEnabled: server, deviceEnabled: device,
                                                     schemaSupported: supported, cancelled: cancelled))
        }
        XCTAssertFalse(HealthSyncPolicy.canUpload(generation: UUID(), currentGeneration: current,
                                                 serverEnabled: true, deviceEnabled: true, schemaSupported: true, cancelled: false))
    }

    func testBoundedBatchesPreserveEveryIdentityAndOrder() {
        for count in [0, 1, 99, 100, 101, 200, 427] {
            let original = Array(0..<count)
            let batches = HealthSyncPolicy.batches(original)
            XCTAssertEqual(batches.flatMap { $0 }, original)
            XCTAssertTrue(batches.allSatisfy { !$0.isEmpty && $0.count <= 100 })
        }
    }

    func testMissingInvalidAndZeroMetricsRemainDifferent() {
        let invalid: [Double?] = [nil, Double.nan, Double.infinity, -Double.infinity, -1]
        for value in invalid {
            XCTAssertNil(HealthSyncPolicy.decimalString(value))
        }
        XCTAssertEqual(HealthSyncPolicy.decimalString(0), "0.00")
        XCTAssertEqual(HealthSyncPolicy.decimalString(112.25), "112.25")
        XCTAssertEqual(HealthSyncPolicy.decimalString(1.625, places: 3), "1.625")
    }

    func testInvalidOptionalHeartRatesDoNotRejectAnOtherwiseValidWorkout() {
        for value in [0.0, 19.99, 300.01, Double.nan, Double.infinity] {
            let rates = HealthSyncPolicy.heartRates(average: value, maximum: value)
            XCTAssertNil(rates.average)
            XCTAssertNil(rates.maximum)
        }
        let valid = HealthSyncPolicy.heartRates(average: 121.5, maximum: 175)
        XCTAssertEqual(valid.average, "121.50")
        XCTAssertEqual(valid.maximum, "175.00")
        let inconsistent = HealthSyncPolicy.heartRates(average: 180, maximum: 175)
        XCTAssertEqual(inconsistent.average, "180.00")
        XCTAssertNil(inconsistent.maximum)
        XCTAssertEqual(HealthSyncPolicy.boundedDecimalString(0, range: 0...100000), "0.00")
        XCTAssertNil(HealthSyncPolicy.boundedDecimalString(100001, range: 0...100000))
    }

    func testSourceLabelsStripControlCharactersAndBoundLength() {
        XCTAssertEqual(HealthSyncPolicy.label("  Test\nWatch\u{0}\u{7F}  ", maximum: 100), "TestWatch")
        XCTAssertNil(HealthSyncPolicy.label(" \n\u{0}", maximum: 100))
        XCTAssertNil(HealthSyncPolicy.label(nil, maximum: 100))
        XCTAssertEqual(HealthSyncPolicy.label("abcdefgh", maximum: 4), "abcd")
    }

    func testImportSummaryAddsEveryBatchNotOnlyTheLast() {
        let first = HealthImportSummary(imported: 2, skippedOverlapping: 1, alreadyImported: 3, updated: 4, linked: 1)
        let second = HealthImportSummary(imported: 5, skippedOverlapping: 0, alreadyImported: 2, updated: 1, linked: 3)
        XCTAssertEqual(first.adding(second), .init(imported: 7, skippedOverlapping: 1, alreadyImported: 5, updated: 5, linked: 4))
    }

    func testConnectionStatusUsesGeneratedOwnerEndpointWithoutAssumingReadPermission() async throws {
        let transport = HealthIntegrationTransport([.init(json: Self.status)])
        let status = try await repository(transport).integrationStatus()
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.schemaVersion, 1)
        XCTAssertFalse(status.garminDirectAvailable)
        XCTAssertNil(status.lastSyncedAt)
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/api/v1/integrations/apple-health/")
        XCTAssertEqual(sent.first?.method, .get)
    }

    func testEnableSendsVersionedConsentAndNoOwnerOrHealthData() async throws {
        let transport = HealthIntegrationTransport([.init(json: Self.status)])
        _ = try await repository(transport).setIntegrationEnabled(true)
        let sent = await transport.sent
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["enabled", "consent_version"])
        XCTAssertEqual(json["enabled"] as? Bool, true)
        XCTAssertEqual(json["consent_version"] as? String, "apple-health-v1")
    }

    func testPauseNeverSendsAnImplicitConsentVersion() async throws {
        let transport = HealthIntegrationTransport([.init(json: Self.status.replacingOccurrences(of: "true", with: "false"))])
        _ = try await repository(transport).setIntegrationEnabled(false)
        let sent = await transport.sent
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        XCTAssertEqual(json["enabled"] as? Bool, false)
        XCTAssertNil(json["consent_version"])
    }

    func testUnsupportedServerIsNotReportedAsHealthPermissionDenied() async throws {
        let transport = HealthIntegrationTransport([.init(status: 404, json: "{}")])
        do { _ = try await repository(transport).integrationStatus(); XCTFail("Must fail closed") }
        catch HealthIntegrationFailure.unsupportedServer { }
    }

    func testImportPreservesActiveDurationSpecificSportMetricsAndExternalIdentity() async throws {
        let transport = HealthIntegrationTransport([.init(json: #"{"imported":1,"already_imported":0,"skipped_overlapping":0,"updated":2,"linked":1}"#)])
        let result = try await repository(transport).importWorkouts([workout()])
        XCTAssertEqual(result.updated, 2)
        XCTAssertEqual(result.linked, 1)
        let sent = await transport.sent
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        let row = try XCTUnwrap((json["workouts"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["external_id"] as? String, workout().externalID)
        XCTAssertEqual(row["activity"] as? String, "running")
        XCTAssertEqual(row["workout_activity"] as? String, "walking")
        XCTAssertEqual(row["duration_seconds"] as? Double, 900)
        XCTAssertEqual(row["active_energy_kcal"] as? String, "112.25")
        XCTAssertEqual(row["distance_km"] as? String, "1.625")
        XCTAssertNil(row["average_heart_rate_bpm"])
        XCTAssertNil(row["device_name"])
        XCTAssertNil(row["owner"])
    }

    func testEmptyAndOversizedImportsNeverSendARequest() async throws {
        let transport = HealthIntegrationTransport([])
        let api = repository(transport)
        let empty = try await api.importWorkouts([])
        XCTAssertEqual(empty, .nothing)
        do { _ = try await api.importWorkouts(Array(repeating: workout(), count: 101)); XCTFail("Must be bounded") }
        catch HealthIntegrationFailure.malformedPage { }
        let sent = await transport.sent
        XCTAssertTrue(sent.isEmpty)
    }

    func testRevokedConsentIsSurfacedWithoutRetryingUpload() async throws {
        let transport = HealthIntegrationTransport([.init(status: 403, json: "{}")])
        do { _ = try await repository(transport).importWorkouts([workout()]); XCTFail("Consent must be checked") }
        catch HealthIntegrationFailure.consentRequired { }
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
    }

    func testSummaryPaginationRejectsCrossOriginDowngradeAndRepeatedPage() async throws {
        for next in ["https://attacker.invalid/?page=2", "http://health-tests.invalid/?page=2", "https://health-tests.invalid/?page=1"] {
            let json = #"{"count":0,"next":"\#(next)","previous":null,"results":[]}"#
            let transport = HealthIntegrationTransport([.init(json: json)])
            do { _ = try await repository(transport).workoutSummaries(page: nil); XCTFail("Untrusted paging") }
            catch APIServiceError.untrustedPaginationURL { }
        }
    }

    func testSummaryPaginationDoesNotDownloadAnUnboundedHistory() async throws {
        let transport = HealthIntegrationTransport([.init(json: #"{"count":200,"next":"https://health-tests.invalid/api/v1/integrations/workouts/?page=2","previous":null,"results":[]}"#)])
        let page = try await repository(transport).workoutSummaries(page: nil)
        XCTAssertEqual(page.nextPage, 2)
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
    }

    func testGarminDashboardUsesServerSourceFilterRatherThanReadingEveryAppleWorkout() async throws {
        let transport = HealthIntegrationTransport([.init(json: #"{"count":0,"next":null,"previous":null,"results":[]}"#)])
        _ = try await repository(transport).workoutSummaries(page: nil, garminOnly: true)
        let sent = await transport.sent
        XCTAssertTrue(try XCTUnwrap(sent.first?.path).contains("source=garmin"))
        XCTAssertEqual(sent.count, 1)
    }

    func testLoginDoesNotAskForHealthPermissionOrEnableAnAccount() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let source = try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("IOS Frontend/IOS Frontend/Stores/ActivityStore.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "func connect(configuration:"))
        let end = try XCTUnwrap(source.range(of: "func disconnect()", range: start.upperBound..<source.endIndex))
        let login = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(login.contains("requestAuthorization"))
        XCTAssertFalse(login.contains("setIntegrationEnabled(true)"))
        XCTAssertTrue(login.contains("healthSyncEnabled"))
        XCTAssertTrue(source.contains("try requireUploadPermission(generation)\n            try await repository.record(steps)"))
        XCTAssertTrue(source.contains("try requireUploadPermission(generation)\n                    summary = summary.adding"))
        XCTAssertTrue(source.contains("guard await reload(generation: generation, showsLoadingState: false) else { return }"))
        XCTAssertTrue(source.contains(".pendingPause"))
    }
}
