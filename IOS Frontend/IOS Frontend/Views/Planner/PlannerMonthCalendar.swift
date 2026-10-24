//
//  PlannerMonthCalendar.swift
//  IOS Frontend
//
//  The month grid at the top of the planner.
//

import SwiftUI

struct PlannerMonthCalendar: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var clearedDate: String?
    var completionPulse = false

    init(
        clearedDate: String? = nil,
        completionPulse: Bool = false
    ) {
        self.clearedDate = clearedDate
        self.completionPulse = completionPulse
    }

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 18) {
            monthControls
            weekdayLabels
            grid
            legend
        }
        // A week is seven days, so this is seven columns at every text size.
        // At the accessibility sizes the headings came apart into stacked
        // single letters -- M, O, N -- and the dates themselves turned into
        // ellipses, which is a calendar that has stopped saying which day
        // anything is on. Capped because picking a day here opens that day's
        // own screen, and that one grows the whole way.
        .typeSizeCeiling()
        .background {
            if clearedDate != nil {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [RepbasePalette.sage.opacity(0.13), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(completionPulse ? 1.01 : 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.48, dampingFraction: 0.72),
            value: completionPulse
        )
    }

    // MARK: - Header

    private var monthControls: some View {
        HStack(spacing: 10) {
            stepper(systemImage: "chevron.left", label: "Previous month", months: -1)
            Spacer(minLength: 0)
            Button("Today") { store.showToday() }
                .font(.community(.footnote, weight: .semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(PlannerStyle.accentText)
                .frame(minHeight: 44)
            Spacer(minLength: 0)
            stepper(systemImage: "chevron.right", label: "Next month", months: 1)

        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem("Items planned", color: PlannerStyle.accentText)
            legendItem("Tasks complete", color: PlannerStyle.success)
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.community(.caption)).foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private func stepper(systemImage: String, label: String, months: Int) -> some View {
        Button {
            store.showMonth(offsetBy: months)
        } label: {
            Image(systemName: systemImage)
                .font(.community(.footnote, weight: .bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(timeOfDay.secondaryText)
        .accessibilityLabel(label)
    }

    // MARK: - Grid

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.allCases) { day in
                Text(day.shortName.uppercased())
                    .font(.community(size: 10, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.timeIntervalSince1970) { date in
                        dayCell(date)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let inMonth = PlannerStore.isSameMonth(date, store.visibleMonth)
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let counts = store.taskCounts(on: date)
        let isCleared = inMonth && counts.total > 0 && counts.done == counts.total

        return Button {
            store.select(date)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.community(size: 14, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(isCleared ? PlannerStyle.success : foreground(inMonth: inMonth, isSelected: isSelected))
                    .frame(width: 30, height: 30)
                    .background(background(isSelected: isSelected, isToday: isToday, isCleared: isCleared))
                    .overlay {
                        if isCleared {
                            Circle()
                                .stroke(RepbasePalette.sage.opacity(0.28), lineWidth: 7)
                                .scaleEffect(!reduceMotion && completionPulse ? 1.18 : 0.92)
                                .opacity(!reduceMotion && completionPulse ? 0 : 1)
                        }
                    }
                    .scaleEffect(isCleared && completionPulse && !reduceMotion ? 1.08 : 1)
                markers(for: date, inMonth: inMonth)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One planned-item dot. The legend describes this meaning, not categories
    /// that may not actually be present on a given day.
    private func markers(for date: Date, inMonth: Bool) -> some View {
        HStack(spacing: 2) {
            if inMonth {
                if store.hasEntries(on: date) {
                    Circle()
                        .fill(PlannerStyle.accentText)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private func background(isSelected: Bool, isToday: Bool, isCleared: Bool) -> some View {
        if isCleared {
            Circle().fill(PlannerStyle.success.opacity(0.14))
                .overlay { Circle().strokeBorder(PlannerStyle.success, lineWidth: isSelected ? 2 : 0) }
        } else if isSelected {
            Circle().fill(timeOfDay.primaryActionSurface)
        } else if isToday {
            Circle().strokeBorder(timeOfDay.accent, lineWidth: 1.5)
        }
    }

    private func foreground(inMonth: Bool, isSelected: Bool) -> Color {
        if isSelected { return timeOfDay.onPrimaryAction }
        return inMonth ? timeOfDay.primaryText : timeOfDay.secondaryText.opacity(0.4)
    }

    // MARK: - Dates

    /// Six rows always, so the page does not jump height when a month starts on
    /// a Sunday or runs to 31 days.
    private var weeks: [[Date]] {
        guard let month = calendar.dateInterval(of: .month, for: store.visibleMonth)
        else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let daysSinceMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: month.start
        ) else { return [] }

        let days = (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    private func accessibilityLabel(for date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let counts = store.taskCounts(on: date)
        guard counts.total > 0 else { return day }
        return "\(day), \(counts.done) of \(counts.total) tasks done"
    }
}
