//
//  WorkoutPlanningWindow.swift
//  IOS Frontend
//
//  Which calendar days a workout can be planned on. Foundation only, so the
//  account-safety tests can check it in any time zone without a simulator.
//

import Foundation

/// Today and the seven days after it: how far ahead a workout can be planned.
///
/// The week strip is Monday to Sunday of this week. On a Friday that reaches
/// two days ahead and on a Sunday none at all, so planning a week ahead also
/// needs the days after this week's Sunday, and this says which those are.
///
/// Everything here moves in calendar days, never in seconds. A day is not
/// always 24 hours: the Sunday the clocks go back has 25, the one they go
/// forward has 23, and "a week from now" counted in seconds lands on the
/// wrong day near midnight on either side of one.
nonisolated enum WorkoutPlanningWindow {
    /// How many days after today a workout can be planned on.
    static let daysAhead = 7

    /// The Monday that starts the week holding `date`, at the start of that
    /// day. Always a Monday, whatever the calendar's own first weekday, as
    /// the strip and the server's weeks are.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: start) + 5) % 7
        return day(-daysSinceMonday, from: start, calendar: calendar)
    }

    /// The start of the day `offset` calendar days from the day holding `date`.
    static func day(_ offset: Int, from date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: start) ?? start)
    }

    /// The last day a workout can be planned on, at its start.
    static func lastDay(from now: Date, calendar: Calendar) -> Date {
        day(daysAhead, from: now, calendar: calendar)
    }

    /// Whether the day holding `date` is today or one of the days after it
    /// that can be planned on.
    static func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: date)
        return start >= calendar.startOfDay(for: now) && start <= lastDay(from: now, calendar: calendar)
    }

    /// Monday to Sunday of the week after this one, at the start of each day.
    static func nextWeek(from now: Date, calendar: Calendar) -> [Date] {
        let monday = day(7, from: weekStart(containing: now, calendar: calendar), calendar: calendar)
        return (0..<7).map { day($0, from: monday, calendar: calendar) }
    }

    /// The days past this week's Sunday that can be planned on, in order:
    /// one on a Monday, the whole of next week on a Sunday.
    static func daysAfterThisWeek(from now: Date, calendar: Calendar) -> [Date] {
        nextWeek(from: now, calendar: calendar).filter { contains($0, now: now, calendar: calendar) }
    }

    /// `YYYY-MM-DD` in `calendar`: the literal calendar date the API takes,
    /// which is the day as the person sees it, not as UTC sees it.
    static func dateString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
