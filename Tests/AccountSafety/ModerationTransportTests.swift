import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest

@testable import RepbaseAPI

/// The two pieces of the moderation path that live in the transport, and that
/// nothing had ever exercised.
///
/// They matter more than their size suggests. The server refuses to send
/// anything for review without a disclosure version it recognises, so if the
/// header is not attached then every submission -- posting, commenting,
/// editing a profile, registering -- fails with 403 and the feature is not
/// merely degraded, it is off. And if the error middleware does not recognise
/// what the server said, the person is told "unexpected response" and given a
/// number, which is the failure the middleware exists to remove.
///
/// Both were shipped on the strength of reading them. This is the part that
/// asks.
final class ModerationTransportTests: XCTestCase {
    private func request() -> HTTPRequest {
        HTTPRequest(method: .post, scheme: "https", authority: "example.test", path: "/api/v1/social/posts/")
    }

    private func response(_ status: Int, body: String) -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .init(code: status)), HTTPBody(Data(body.utf8)))
    }

    // MARK: - The header

    func testTheDisclosureVersionIsAttached() async throws {
        var seen: HTTPRequest?
        _ = try await ModerationConsentMiddleware().intercept(
            request(), body: nil, baseURL: URL(string: "https://example.test")!,
            operationID: "socialPostsCreate"
        ) { forwarded, _, _ in
            seen = forwarded
            return (HTTPResponse(status: .created), nil)
        }
        let sent = seen?.headerFields[.init("X-Moderation-Consent")!]
        XCTAssertEqual(sent, ModerationDisclosure.version)
        XCTAssertFalse(ModerationDisclosure.version.isEmpty)
    }

    /// The server compares the header against its own constant, so the two
    /// have to be changed together. A mismatch refuses every submission, and
    /// it would look like a server fault from the app and a client fault from
    /// the server.
    func testTheVersionIsTheOneTheServerExpects() {
        XCTAssertEqual(ModerationDisclosure.version, "2026-09-15")
    }

    // MARK: - The refusals

    func testARejectionBecomesSomethingWorthShowing() async throws {
        do {
            _ = try await ModerationErrorMiddleware().intercept(
                request(), body: nil, baseURL: URL(string: "https://example.test")!,
                operationID: "socialPostsCreate"
            ) { _, _, _ in
                self.response(400, body: #"{"detail": "Not under our standards. Appeal to support@rytivo.app.", "code": "moderation_rejected"}"#)
            }
            XCTFail("a refusal must not reach the caller as a status code")
        } catch let error as ModerationError {
            XCTAssertEqual(error.code, "moderation_rejected")
            XCTAssertTrue(error.detail.contains("support@rytivo.app"))
            XCTAssertFalse(error.isRetryable, "offering a retry invites pressing it until it works")
        }
    }

    func testAnOutageIsTheOneWorthRetrying() async throws {
        do {
            _ = try await ModerationErrorMiddleware().intercept(
                request(), body: nil, baseURL: URL(string: "https://example.test")!,
                operationID: "socialPostsCreate"
            ) { _, _, _ in
                self.response(503, body: #"{"detail": "Safety checks are temporarily unavailable.", "code": "moderation_unavailable"}"#)
            }
            XCTFail("an outage must not reach the caller as a status code")
        } catch let error as ModerationError {
            XCTAssertEqual(error.code, "moderation_unavailable")
            XCTAssertTrue(error.isRetryable)
        }
    }

    func testAnOldBuildIsToldToUpdate() async throws {
        do {
            _ = try await ModerationErrorMiddleware().intercept(
                request(), body: nil, baseURL: URL(string: "https://example.test")!,
                operationID: "socialPostsCreate"
            ) { _, _, _ in
                self.response(403, body: #"{"detail": "Update the app, then try again.", "code": "moderation_consent_required"}"#)
            }
            XCTFail("a consent failure must not reach the caller as a status code")
        } catch let error as ModerationError {
            XCTAssertEqual(error.code, "moderation_consent_required")
            XCTAssertFalse(error.isRetryable, "retrying the same build cannot help")
        }
    }

    func testTheMessageIsWhatAPersonWouldRead() async throws {
        do {
            _ = try await ModerationErrorMiddleware().intercept(
                request(), body: nil, baseURL: URL(string: "https://example.test")!,
                operationID: "socialPostsCreate"
            ) { _, _, _ in
                self.response(400, body: #"{"detail": "Please revise it.", "code": "moderation_rejected"}"#)
            }
            XCTFail("expected a refusal")
        } catch let error as ModerationError {
            // localizedDescription is what a SwiftUI alert shows by default.
            XCTAssertEqual(error.localizedDescription, "Please revise it.")
        }
    }

    // MARK: - Everything else has to pass through untouched

    func testAnUnrelatedFailureIsLeftAlone() async throws {
        let body = #"{"source_id": ["No workout of yours with that id."]}"#
        let (response, returned) = try await ModerationErrorMiddleware().intercept(
            request(), body: nil, baseURL: URL(string: "https://example.test")!,
            operationID: "socialPostsCreate"
        ) { _, _, _ in
            self.response(400, body: body)
        }
        XCTAssertEqual(response.status.code, 400)
        let bytes = try await Data(collecting: returned!, upTo: 4096)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), body,
                       "the body has to survive being read, or the caller loses it")
    }

    func testAnUnknownCodeIsNotSwallowed() async throws {
        let body = #"{"detail": "Something else", "code": "some_other_thing"}"#
        let (_, returned) = try await ModerationErrorMiddleware().intercept(
            request(), body: nil, baseURL: URL(string: "https://example.test")!,
            operationID: "socialPostsCreate"
        ) { _, _, _ in
            self.response(400, body: body)
        }
        let bytes = try await Data(collecting: returned!, upTo: 4096)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), body)
    }

    func testASuccessIsNotTouched() async throws {
        let body = #"{"id": 7}"#
        let (response, returned) = try await ModerationErrorMiddleware().intercept(
            request(), body: nil, baseURL: URL(string: "https://example.test")!,
            operationID: "socialPostsCreate"
        ) { _, _, _ in
            self.response(201, body: body)
        }
        XCTAssertEqual(response.status.code, 201)
        let bytes = try await Data(collecting: returned!, upTo: 4096)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), body)
    }
}
