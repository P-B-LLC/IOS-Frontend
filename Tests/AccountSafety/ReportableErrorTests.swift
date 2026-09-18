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
