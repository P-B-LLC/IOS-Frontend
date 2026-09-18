//
//  ReportableError.swift
//  IOS Frontend
//
//  Which failures are worth telling the user about.
//
//  A cancelled request is not one. SwiftUI cancels the task behind a `.task`
//  whenever the view goes away or its id changes, and URLSession reports that
//  as NSURLErrorCancelled — code -999. Nothing went wrong, nobody can act on
//  it, and there is nothing to retry, but it arrives at a `catch` looking
//  exactly like a server being down and was being shown as:
//
//      Client encountered an error invoking the operation "sessions_list" …
//      Code=-999 "cancelled"
//
//  So the stores ask an error whether it is worth reporting before they put
//  it on screen.
//

import Foundation
import OpenAPIRuntime
import RepbaseAPI

extension Error {
    /// Whether this is the app cancelling its own work rather than a failure.
    ///
    /// Checked at every depth: the generated client wraps what URLSession
    /// threw inside its own error, so the -999 is usually somewhere under a
    /// ClientError rather than at the top.
    var isCancellation: Bool {
        if self is CancellationError { return true }

        // Unwrap the generated client's own wrapper first.
        //
        // The walk below follows NSUnderlyingErrorKey, which only reaches
        // errors that are NSErrors. A Swift `CancellationError` is not one,
        // and swift-openapi-runtime puts it in `ClientError.underlyingError`
        // rather than in any userInfo, so cancelling a `.task` on a screen
        // that was still loading produced an error this could not recognise
        // and the person got the full
        //
        //     Client encountered an error invoking the operation
        //     "sessions_list" … underlying error: CancellationError()
        //
        // next to a Retry button, for having navigated away. Bounded for the
        // same reason as the loop below.
        var root: any Error = self
        var unwrapped = 0
        while let client = root as? ClientError, unwrapped < 8 {
            root = client.underlyingError
            unwrapped += 1
        }
        if root is CancellationError { return true }

        let nsError = root as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return true
        }
        // Walk down the wrapping. Bounded, because an underlying error that
        // pointed back at itself would otherwise spin here forever.
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        var depth = 0
        while let current = underlying, depth < 8 {
            if current.domain == NSURLErrorDomain,
               current.code == NSURLErrorCancelled {
                return true
            }
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    /// Whether the person declined something they were asked, rather than
    /// something failing.
    ///
    /// Pressing Cancel on the safety-review dialog used to produce an error
    /// alert, which states a decision back to the person who just made it, in
    /// the voice the app keeps for things going wrong.
    ///
    /// `ModerationConsent.CannotAsk` is deliberately *not* included. That one
    /// is a fault — the question could not be put at all — and silencing it
    /// would hide a submission that did not happen for a reason nobody chose.
    var isDeclinedByPerson: Bool {
        self is ModerationConsent.NotGranted
    }

    /// Whether offering a retry would be honest.
    ///
    /// Only an outage is. A refusal under community standards will refuse the
    /// same content again, and a retry button in front of one invites pressing
    /// it until it works — which it will not. The server distinguishes the two
    /// by code and `ModerationErrorMiddleware` turns that into `isRetryable`;
    /// this is where it stops being a property nobody reads.
    var isRetryableFailure: Bool {
        (self as? ModerationError)?.isRetryable ?? false
    }

    /// What to show, or nil when the failure is not the user's business.
    var userFacingMessage: String? {
        (isCancellation || isDeclinedByPerson) ? nil : localizedDescription
    }
}
