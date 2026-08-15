//
//  HomeCalendarCards.swift
//  IOS Frontend
//
//  One card on the home page: what is on today, and where today sits in the
//  month.
//

import SwiftUI

/// Today's events and the month, split by a rule down the middle.
///
/// One card rather than two, so the pair reads as a single widget the way the
/// design it came from does.
struct HomeCalendarCard: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    private let calendar = Calendar.current

    var body: some View {
        NavigationLink {
            PlannerView()
        } label: {
            HStack(spacing: 0) {
                eventsPane
                    .frame(width: 104)
                Rectangle()
                    .fill(timeOfDay.border)
                    .frame(width: 1)
                calendarPane
            }
            .frame(minHeight: 162)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: timeOfDay.shadow, radius: 12, x: 5, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the planner")
    }

    // MARK: - Events

    private var eventsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today's")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(timeOfDay.secondaryText)
            Text("Events")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(timeOfDay.primaryText)

            Spacer(minLength: 6)

            if events.isEmpty {
                Text("Nothing on")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            } else {
                Text("\(events.count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.primaryText)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events.prefix(2)) { event in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(event.category.tint)
                                .frame(width: 4, height: 4)
                            Text(event.title)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(timeOfDay.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(13)
    }

    private var events: [PlannerEntry] {
        store.entries(on: Date()).filter { $0.kind == .event }
    }

    // MARK: - Calendar

    private var calendarPane: some View {
        HStack(spacing: 7) {
            monthSpine
            VStack(alignment: .leading, spacing: 0) {
                Text(Date().formatted(.dateTime.year()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer(minLength: 6)
                week
                Spacer(minLength: 6)

                Rectangle()
                    .fill(timeOfDay.border)
                    .frame(height: 1)
                nextUp
                    .padding(.top, 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(13)
    }

    /// The month name set on its side, as in the design this came from. The
    /// stripe beside it carries the category colours the rest of the planner
    /// uses.
    private var monthSpine: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            PlannerCategory.birthday.tint,
                            PlannerCategory.workout.tint,
                            PlannerCategory.holiday.tint,
                            PlannerCategory.travel.tint,
                            PlannerCategory.study.tint,
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 3)

            Text(Date().formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 13, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(timeOfDay.primaryText)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 16)
        }
        // Sized to the word rather than the card, as in the design. Long
        // enough for SEPTEMBER, the longest of them.
        .frame(height: 96)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Monday first, matching every other week in the app rather than the
    /// Sunday-first reference.
    private var week: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.timeIntervalSince1970) { date in
                VStack(spacing: 3) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 11, weight: calendar.isDateInToday(date) ? .bold : .medium))
                        .foregroundStyle(
                            calendar.isDateInToday(date)
                                ? Color(hex: 0xFFFFFF)
                                : timeOfDay.primaryText
                        )
                        .frame(width: 20, height: 20)
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
        HStack(spacing: 4) {
            if let entry = nextEntry {
                Circle()
                    .fill(entry.category.tint)
                    .frame(width: 4, height: 4)
                Text(entry.displayTime.map { "Today, \($0)" } ?? "Today")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText)
                Text(entry.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)
            } else {
                Text("No events today")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    /// The next event still to come today, or the first one on it once the
    /// day's timed events have passed.
    ///
    /// Events only, like the pane beside it. Drawing a task here made the card
    /// say "Nothing on" and then name a chore underneath it.
    private var nextEntry: PlannerEntry? {
        let now = Self.currentTimeString()
        let upcoming = events.filter { $0.time != nil && ($0.time ?? "") >= now }
        return upcoming.min { ($0.time ?? "") < ($1.time ?? "") } ?? events.first
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
