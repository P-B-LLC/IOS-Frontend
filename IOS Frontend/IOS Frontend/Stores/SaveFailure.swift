//
//  SaveFailure.swift
//  IOS Frontend
//
//  Why a save did not happen, in words worth showing someone.
//

import Foundation

/// The reasons a store refuses a save before it ever reaches the network.
///
/// Every store used to express these as one arm of a combined `guard`, and a
/// combined guard can only return a bare `false`. The editors turned that
/// false into "Couldn't save. Your changes are still here; please try again."
/// -- which reads as a transient server problem no matter which of these
/// actually happened, so retrying was the only advice on offer and it was
/// usually the wrong one. Worse, a real error the store had already captured
/// was thrown away to print it.
///
/// These live together because all three stores refuse for the same reasons
/// and should not each invent their own wording for them.
enum SaveFailure {
    static let notConnected = "Not connected to Rytivo, so this could not be saved. Check your connection and try again."
    static let alreadySaving = "Another save is still finishing. Try again in a moment."

    /// The last resort, for a save that failed with nothing saying why.
    ///
    /// Reaching this is a bug in whichever path returned failure without a
    /// reason, so it says the one thing that is certainly true -- the work is
    /// still on screen -- instead of guessing at a cause.
    static let unexplained = "Couldn't save, and the app didn't say why. Your changes are still here."
}
