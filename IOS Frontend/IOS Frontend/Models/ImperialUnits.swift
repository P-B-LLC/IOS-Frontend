//
//  ImperialUnits.swift
//  IOS Frontend
//
//  Kilometres in, miles out.
//
//  The server stores and computes everything in kilometres and metres, and it
//  stays that way: a unit is a display choice, and moving it into the database
//  would mean every stored number had to be read alongside the preference that
//  was in force when it was written. Conversion happens here, once, at the
//  edge where a number becomes a string.
//

import Foundation

nonisolated enum ImperialUnits {
    /// Exact by definition: a mile is 1609.344 metres.
    static let metersPerMile: Double = 1609.344
    static let metersPerFoot: Double = 0.3048

    static func miles(fromKilometers kilometers: Double) -> Double {
        kilometers * 1000 / metersPerMile
    }

    static func feet(fromMeters meters: Double) -> Double {
        meters / metersPerFoot
    }

    /// Pace inverts: a mile is longer than a kilometre, so seconds per mile is
    /// the larger number. Getting this backwards turns a 5:00/km run into a
    /// 3:07/mi one, which is a world record rather than a Tuesday.
    static func paceSecondsPerMile(fromPerKilometer seconds: Double) -> Double {
        seconds * metersPerMile / 1000
    }

    static func milesPerHour(fromKilometersPerHour kilometersPerHour: Double) -> Double {
        miles(fromKilometers: kilometersPerHour)
    }

    // MARK: - Strings

    static func distanceText(kilometers: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f mi", miles(fromKilometers: kilometers))
    }

    static func elevationText(meters: Double) -> String {
        String(format: "%.0f ft", feet(fromMeters: meters))
    }

    static func speedText(kilometersPerHour: Double) -> String {
        String(format: "%.1f mph", milesPerHour(fromKilometersPerHour: kilometersPerHour))
    }

    /// "8:51 /mi" from seconds per kilometre.
    static func paceText(secondsPerKilometer seconds: Double) -> String {
        let perMile = Int(paceSecondsPerMile(fromPerKilometer: seconds).rounded())
        return String(format: "%d:%02d /mi", perMile / 60, perMile % 60)
    }
}
