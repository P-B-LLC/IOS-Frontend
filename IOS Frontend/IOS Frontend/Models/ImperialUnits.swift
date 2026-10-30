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

    // MARK: - Figures
    //
    // The number alone, for a screen that prints the unit beside it. Kept
    // apart from the strings below rather than cut out of them: their unit is
    // translated, so it is not always " mi" to cut off.

    static func distanceFigure(kilometers: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", miles(fromKilometers: kilometers))
    }

    static func speedFigure(kilometersPerHour: Double) -> String {
        String(format: "%.1f", milesPerHour(fromKilometersPerHour: kilometersPerHour))
    }

    /// "8:51" from seconds per kilometre.
    static func paceFigure(secondsPerKilometer seconds: Double) -> String {
        let perMile = Int(paceSecondsPerMile(fromPerKilometer: seconds).rounded())
        return String(format: "%d:%02d", perMile / 60, perMile % 60)
    }

    // MARK: - Strings

    static func distanceText(kilometers: Double, decimals: Int = 2) -> String {
        String(
            localized: "\(distanceFigure(kilometers: kilometers, decimals: decimals)) mi",
            bundle: .app,
            locale: .app,
            comment: "A distance; mi is the abbreviation for miles"
        )
    }

    static func elevationText(meters: Double) -> String {
        let figure = String(format: "%.0f", feet(fromMeters: meters))
        return String(
            localized: "\(figure) ft",
            bundle: .app,
            locale: .app,
            comment: "A height climbed; ft is the abbreviation for feet"
        )
    }

    static func speedText(kilometersPerHour: Double) -> String {
        String(
            localized: "\(speedFigure(kilometersPerHour: kilometersPerHour)) mph",
            bundle: .app,
            locale: .app,
            comment: "A speed; mph is the abbreviation for miles per hour"
        )
    }

    /// "8:51 /mi" from seconds per kilometre.
    static func paceText(secondsPerKilometer seconds: Double) -> String {
        String(
            localized: "\(paceFigure(secondsPerKilometer: seconds)) /mi",
            bundle: .app,
            locale: .app,
            comment: "A pace in minutes and seconds; /mi means per mile"
        )
    }
}
