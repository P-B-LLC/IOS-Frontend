import Foundation
import OpenAPIRuntime
import XCTest

@testable import AccountSafety

/// Navigating away from a loading screen is not a failure worth reporting.
///
/// `isCancellation` existed for exactly this and still let one through. It
/// knew about `CancellationError` at the top level, and about
/// `NSURLErrorCancelled` buried in `NSUnderlyingErrorKey`, which covers what
/// URLSession reports. It did not cover the shape actually produced here: the
/// generated client wraps whatever the transport threw in a `ClientError`, and
/// a Swift `CancellationError` is not an `NSError`, so it never appears in the
/// userInfo chain the walk follows. The result reached the screen in full --
///
///     Client encountered an error invoking the operation "sessions_list",
///     caused by "Transport threw an error.", underlying error:
///     CancellationError().
///
/// -- next to a Retry button, on a screen whose data had loaded fine, because
/// somebody had changed tabs while a request was in flight.
///
/// These assert on the wrapper rather than on a bare error, because the bare
/// cases already passed while the app was showing this.
final class ReportableErrorTests: XCTestCase {
    private func clientError(wrapping underlying: any Error) -> ClientError {
        ClientError(
            operationID: "sessions_list",
            operationInput: "input",
            causeDescription: "Transport threw an error.",
            underlyingError: underlying
        )
    }

    func testAWrappedSwiftCancellationIsNotReported() {
        let error = clientError(wrapping: CancellationError())
        XCTAssertTrue(error.isCancellation)
        XCTAssertNil(error.userFacingMessage, "a cancelled task has nothing to say")
    }

    func testAWrappedURLSessionCancellationIsNotReported() {
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertTrue(clientError(wrapping: cancelled).isCancellation)
    }

    func testABareCancellationIsStillRecognised() {
        XCTAssertTrue(CancellationError().isCancellation)
        XCTAssertTrue(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled).isCancellation
        )
    }

    /// The point of the guard is that it stays narrow. A server that is down
    /// is reported, wrapped or not -- silencing this would hide an outage.
    func testARealFailureIsStillReported() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertFalse(offline.isCancellation)
        XCTAssertNotNil(offline.userFacingMessage)

        let wrapped = clientError(wrapping: offline)
        XCTAssertFalse(wrapped.isCancellation)
        XCTAssertNotNil(wrapped.userFacingMessage)
    }
}

/// What a failure says to somebody who is not us.
///
/// `userFacingMessage` returned `localizedDescription` for everything, and a
/// `ClientError`'s description is written for whoever is debugging it. A phone
/// with no signal produced, on screen, in the app itself:
///
///     Client encountered an error invoking the operation
///     "sessions_training_stats_retrieve", caused by "Transport threw an
///     error.", underlying error: Error Domain=NSURLErrorDomain Code=-999
///     … _NSURLErrorRelatedURLSessionTaskErrorKey=("LocalDataTask
///     <720DC09A-4549-4EA0-B3C5-A95E05EC2423>.<104>") …
///
/// -- the operation name, both URLs, and an internal task handle. Nobody can
/// act on any of it, and it reads as the app having crashed rather than the
/// network being down.
final class NetworkFailureWordingTests: XCTestCase {
    private func clientError(_ code: Int) -> ClientError {
        ClientError(
            operationID: "sessions_training_stats_retrieve",
            operationInput: "input",
            causeDescription: "Transport threw an error.",
            underlyingError: NSError(domain: NSURLErrorDomain, code: code)
        )
    }

    func testBeingOfflineSaysSo() {
        let message = clientError(NSURLErrorNotConnectedToInternet).userFacingMessage
        XCTAssertEqual(message, "You appear to be offline. Check your connection and try again.")
    }

    func testEveryNetworkFailureIsASentence() {
        // The specific codes matter less than the guarantee: nothing that
        // failed in transport may reach the screen as a client dump.
        for code in [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorBadServerResponse,
            NSURLErrorUnknown,
        ] {
            let message = clientError(code).userFacingMessage ?? ""
            XCTAssertFalse(message.isEmpty, "code \(code) said nothing")
            XCTAssertFalse(
                message.contains("Client encountered an error")
                    || message.contains("NSURLErrorDomain")
                    || message.contains("operationID")
                    || message.contains("LocalDataTask"),
                "code \(code) leaked the client's own description: \(message)"
            )
        }
    }

    /// The counterpart, and the more important one. Replacing what the server
    /// said with "check your connection" would be a lie about a request that
    /// arrived and was answered -- and would have hidden today's 400.
    func testAMessageFromTheServerIsLeftAlone() {
        struct ServerSaid: LocalizedError {
            var errorDescription: String? { "Give the task a name." }
        }
        XCTAssertEqual(ServerSaid().userFacingMessage, "Give the task a name.")
    }
}
