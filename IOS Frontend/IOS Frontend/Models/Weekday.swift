//
//  Weekday.swift
//  IOS Frontend
//
//  Lifted out of Workout.swift, which needs ImperialUnits and so cannot be
//  compiled on its own. This enum needs nothing but Foundation, and the
//  navigation routing tests reach it by copying single files into a package
//  -- which only works for files that stand up by themselves.
//

import Foundation

/// The seven days of the week, ordered Monday-first to match the weekly widget.
nonisolated enum Weekday: Int, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    /// Full display name, e.g. "Monday".
    var fullName: String { Self.symbols(\.weekdaySymbols)[symbolIndex] }

    /// Short display name, e.g. "Mon".
    var shortName: String { Self.symbols(\.shortWeekdaySymbols)[symbolIndex] }

    /// Where this day sits in `Calendar`'s symbol lists, which start on
    /// Sunday where this enum starts on Monday.
    private var symbolIndex: Int { rawValue % 7 }

    /// Day names in the language chosen in Settings, read from the calendar
    /// rather than translated here, so every language gets its own spelling
    /// and abbreviations.
    private static func symbols(_ list: KeyPath<Calendar, [String]>) -> [String] {
        var calendar = Calendar.current
        calendar.locale = .app
        return calendar[keyPath: list]
    }

    /// The API's weekday number, which counts from Monday as zero to match
    /// Python's `date.weekday()`. This enum counts from one.
    var apiValue: Int { rawValue - 1 }

    /// Reads back a weekday sent by the API.
    init?(apiValue: Int) {
        self.init(rawValue: apiValue + 1)
    }

    /// Maps a `Calendar` weekday component (1 = Sunday … 7 = Saturday) to a `Weekday`.
    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}
