//
//  HomeCalendarCards.swift
//  IOS Frontend
//
//  The calendar pair on the home page: what is on today, and where today sits
//  in the month.
//

import SwiftUI

/// The two cards side by side, sized so the square one keeps its shape.
struct HomeCalendarRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            TodaysEventsCard()
                .frame(width: 132)
            HomeMonthCard()
        }
    }
}

/// Today's events. Events only: a task belongs in `TodaysActivityCard`, where
/// it can be ticked off, and an event is not something to finish.
struct TodaysEventsCard: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        NavigationLink {
            PlannerView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today's")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText)
                Text("Events")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.primaryText)

                Spacer(minLength: 10)

                if events.isEmpty {
                    Text("Nothing on")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(timeOfDay.secondaryText)
                } else {
                    Text("\(events.count)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(timeOfDay.primaryText)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(events.prefix(2)) { event in
                            eventRow(event)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
            .shadow(color: timeOfDay.shadow, radius: 12, x: 5, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the planner")
    }

    private func eventRow(_ event: PlannerEntry) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(event.category.tint)
                .frame(width: 5, height: 5)
            Text(event.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(timeOfDay.secondaryText)
                .lineLimit(1)
        }
    }

    private var events: [PlannerEntry] {
        store.entries(on: Date()).filter { $0.kind == .event }
    }
}

/// The month, the week today sits in, and the next thing due.
struct HomeMonthCard: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    private let calendar = Calendar.current

    var body: some View {
        NavigationLink {
            PlannerView()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 10)
                week
                Spacer(minLength: 10)
                Divider().overlay(timeOfDay.border)
                nextUp
                    .padding(.top, 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
            .shadow(color: timeOfDay.shadow, radius: 12, x: 5, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the planner")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date().formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(timeOfDay.primaryText)
            Spacer(minLength: 4)
            Text(Date().formatted(.dateTime.year()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    /// Monday first, matching every other week in the app.
    private var week: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.timeIntervalSince1970) { date in
                VStack(spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 12, weight: calendar.isDateInToday(date) ? .bold : .medium))
                        .foregroundStyle(
                            calendar.isDateInToday(date)
                                ? Color(hex: 0xFFFFFF)
                                : timeOfDay.primaryText
                        )
                        .frame(width: 22, height: 22)
                        .background {
                            if calendar.isDateInToday(date) {
                                Circle().fill(timeOfDay.accent)
                            }
                        }
                    Circle()
                        .fill(store.hasEntries(on: date) ? timeOfDay.accent : .clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var nextUp: some View {
        HStack(spacing: 5) {
            if let entry = nextEntry {
                Circle()
                    .fill(entry.category.tint)
                    .frame(width: 5, height: 5)
                Text(entry.displayTime.map { "Today, \($0)" } ?? "Today")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText)
                Text(entry.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)
            } else {
                Text("Nothing planned today")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    /// The next thing still to come today, or the first thing on it once the
    /// day's timed entries have passed. Finished tasks are left out: they are
    /// not what is next.
    private var nextEntry: PlannerEntry? {
        let now = Self.currentTimeString()
        let remaining = store.entries(on: Date()).filter { !$0.isComplete }
        let upcoming = remaining.filter { ($0.time ?? "") >= now && $0.time != nil }
        return upcoming.min { ($0.time ?? "") < ($1.time ?? "") } ?? remaining.first
    }

    private var weekDays: [Date] {
        let start = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: start)
        else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private static func currentTimeString() -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d:00", parts.hour ?? 0, parts.minute ?? 0)
    }
}
