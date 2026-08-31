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

    /// Closes the month, leaving the week strip. Absent when the calendar is
    /// not something the user opened.
    var onClose: (() -> Void)?
    var clearedDate: String?
    var completionPulse = false

    init(
        clearedDate: String? = nil,
        completionPulse: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.clearedDate = clearedDate
        self.completionPulse = completionPulse
        self.onClose = onClose
    }

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 18) {
            monthControls
            weekdayLabels
            grid
            legend
        }
        .repbaseCard(contentPadding: 18, cornerRadius: 24)
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
            Spacer(minLength: 0)

            if !isShowingCurrentMonth {
                Button("Today") { store.showToday() }
                    .font(.community(.caption, weight: .semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(timeOfDay.accent)
            }

            stepper(systemImage: "chevron.left", label: "Previous month", months: -1)
            stepper(systemImage: "chevron.right", label: "Next month", months: 1)

            if let onClose { Button("Week", action: onClose).font(.community(.caption, weight: .semibold)) }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem("Workout", color: Color(hex: 0xB96F4C))
            legendItem("Meals", color: Color(hex: 0x4AAFB3))
            legendItem("Complete", color: Color(hex: 0x356B5B))
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.community(size: 9, weight: .medium)).foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private func stepper(systemImage: String, label: String, months: Int) -> some View {
        Button {
            store.showMonth(offsetBy: months)
        } label: {
            Image(systemName: systemImage)
                .font(.community(.footnote, weight: .bold))
                .frame(width: 32, height: 32)
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
        let isCleared = clearedDate == PlannerStore.dateString(date)

        return Button {
            store.select(date)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.community(size: 14, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(foreground(inMonth: inMonth, isSelected: isSelected || isCleared))
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
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date))
    }

    /// A dot per category planned that day, up to three. Days outside the month
    /// stay bare: marking them would make the grid read as denser than it is.
    private func markers(for date: Date, inMonth: Bool) -> some View {
        HStack(spacing: 2) {
            if inMonth {
                ForEach(store.categories(on: date).prefix(3), id: \.self) { category in
                    Circle()
                        .fill(category.tint)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private func background(isSelected: Bool, isToday: Bool, isCleared: Bool) -> some View {
        if isCleared {
            Circle().fill(RepbasePalette.sage)
        } else if isSelected {
            Circle().fill(timeOfDay.accent)
        } else if isToday {
            Circle().strokeBorder(timeOfDay.accent, lineWidth: 1.5)
        }
    }

    private func foreground(inMonth: Bool, isSelected: Bool) -> Color {
        if isSelected { return Color(hex: 0xFFFFFF) }
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

    private var isShowingCurrentMonth: Bool {
        PlannerStore.isSameMonth(store.visibleMonth, Date())
    }

    private var monthName: String {
        store.visibleMonth.formatted(.dateTime.month(.wide))
    }

    private var yearName: String {
        store.visibleMonth.formatted(.dateTime.year())
    }

    private func accessibilityLabel(for date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let counts = store.taskCounts(on: date)
        guard counts.total > 0 else { return day }
        return "\(day), \(counts.done) of \(counts.total) tasks done"
    }
}
