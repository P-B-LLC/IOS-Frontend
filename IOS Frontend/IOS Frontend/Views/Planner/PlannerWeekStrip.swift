//
//  PlannerWeekStrip.swift
//  IOS Frontend
//
//  The week widget above the day's list: which day, what is on it, how far in.
//

import SwiftUI

struct PlannerWeekStrip: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    /// Nil means every category. Held by the page so the list below filters
    /// with the chips rather than keeping its own idea of what is selected.
    @Binding var categoryFilter: PlannerCategory?

    /// Whether the full month is open above this strip.
    var isMonthShown: Bool = false
    /// Opens the month. The day tabs cannot do this themselves: they already
    /// mean "choose this day".
    var onToggleMonth: (() -> Void)?

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if onToggleMonth != nil {
                monthButton
            }
            dayTabs
            if !categories.isEmpty {
                categoryTabs
            }
            progress
        }
        .repbaseCard(contentPadding: 14, cornerRadius: 20)
    }

    // MARK: - Opening the month

    private var monthButton: some View {
        Button {
            onToggleMonth?()
        } label: {
            HStack(spacing: 5) {
                Text(store.selectedDate.formatted(.dateTime.month(.wide).year()))
                    .font(.community(size: 14, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
                Image(systemName: isMonthShown ? "chevron.up" : "chevron.down")
                    .font(.community(size: 10, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMonthShown ? "Hide the month" : "Show the month")
    }

    // MARK: - Days

    private var dayTabs: some View {
        HStack(spacing: 5) {
            ForEach(weekDays, id: \.timeIntervalSince1970) { date in
                dayTab(date)
            }
        }
    }

    private func dayTab(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            store.select(date)
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.community(size: 9, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? Color(hex: 0xFFFFFF).opacity(0.85) : timeOfDay.secondaryText
                    )
                Text("\(calendar.component(.day, from: date))")
                    .font(.community(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? Color(hex: 0xFFFFFF) : timeOfDay.primaryText)
                marker(for: date, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(tabBackground(isSelected: isSelected, isToday: isToday))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A single dot saying "something is planned", rather than a count: the
    /// strip is for choosing a day, and the list below answers what is on it.
    private func marker(for date: Date, isSelected: Bool) -> some View {
        Circle()
            .fill(
                store.hasEntries(on: date)
                    ? (isSelected ? Color(hex: 0xFFFFFF) : timeOfDay.accent)
                    : Color.clear
            )
            .frame(width: 4, height: 4)
    }

    @ViewBuilder
    private func tabBackground(isSelected: Bool, isToday: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 13).fill(timeOfDay.accent)
        } else if isToday {
            RoundedRectangle(cornerRadius: 13).strokeBorder(timeOfDay.accent.opacity(0.5), lineWidth: 1)
        }
    }

    // MARK: - Categories

    /// Only categories actually planned that day. Offering the full list would
    /// mean most chips filter to nothing.
    private var categories: [PlannerCategory] {
        store.categories(on: store.selectedDate)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip(title: "All", tint: timeOfDay.accent, isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(categories) { category in
                    chip(
                        title: category.title,
                        tint: category.tint,
                        isSelected: categoryFilter == category
                    ) {
                        categoryFilter = categoryFilter == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(
        title: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.community(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: 0xFFFFFF) : timeOfDay.secondaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    isSelected ? tint : tint.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private var progress: some View {
        let counts = store.taskCounts(on: store.selectedDate)
        let fraction = store.progress(on: store.selectedDate)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("PROGRESS")
                    .font(.community(size: 9, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
                Spacer()
                Text(
                    counts.total == 0
                        ? "No tasks"
                        : "\(counts.done) of \(counts.total)"
                )
                .font(.community(size: 9, weight: .bold))
                .foregroundStyle(timeOfDay.secondaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(timeOfDay.secondaryText.opacity(0.15))
                    Capsule()
                        .fill(timeOfDay.accent)
                        .frame(width: max(0, proxy.size.width * fraction))
                }
            }
            .frame(height: 5)
            .animation(.easeOut(duration: 0.2), value: fraction)
        }
    }

    // MARK: - Dates

    /// The week the selected day sits in, Monday first, matching the rest of
    /// the app rather than the device's locale.
    private var weekDays: [Date] {
        let start = calendar.startOfDay(for: store.selectedDate)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: start)
        else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}
