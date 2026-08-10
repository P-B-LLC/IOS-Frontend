//
//  Workout.swift
//  IOS Frontend
//
//  The core workout + weekday types used by the weekly schedule.
//

import Foundation

/// A workout the user can perform and assign to a day of the week
/// (e.g. "Upper Body", "Core & Mobility").
///
/// Intentionally minimal for now — it holds just enough to drive the weekly
/// schedule. Fields like exercises or duration can be added later without
/// changing how the schedule is stored or read.
struct Workout: Identifiable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// The seven days of the week, ordered Monday-first to match the weekly widget.
enum Weekday: Int, CaseIterable, Identifiable, Hashable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    /// Full display name, e.g. "Monday".
    var fullName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    /// Short display name, e.g. "Mon".
    var shortName: String { String(fullName.prefix(3)) }

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
