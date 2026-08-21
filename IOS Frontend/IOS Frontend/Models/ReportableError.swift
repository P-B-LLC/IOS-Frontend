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

extension Error {
    /// Whether this is the app cancelling its own work rather than a failure.
    ///
    /// Checked at every depth: the generated client wraps what URLSession
    /// threw inside its own error, so the -999 is usually somewhere under a
    /// ClientError rather than at the top.
    var isCancellation: Bool {
        if self is CancellationError { return true }

        let nsError = self as NSError
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

    /// What to show, or nil when the failure is not the user's business.
    var userFacingMessage: String? {
        isCancellation ? nil : localizedDescription
    }
}
