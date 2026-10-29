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
            if categories.count > 1 || categoryFilter != nil {
                categoryTabs
            }
            progress
        }
    }

    // MARK: - Opening the month

    private var monthButton: some View {
        HStack(spacing: 8) {
            Button {
                onToggleMonth?()
            } label: {
                Label("View month", systemImage: "chevron.down")
                    .font(.community(.footnote, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(timeOfDay.surfaceRaised, in: Capsule())
                    .overlay { Capsule().strokeBorder(timeOfDay.canvasBorder) }
            }
            .accessibilityIdentifier("planner.viewMonth")
            .accessibilityHint("Open the full month calendar")
            Spacer(minLength: 0)
            if !calendar.isDateInToday(store.selectedDate) {
                Button("Today") { store.showToday() }
                    .font(.community(.footnote, weight: .semibold))
                    .frame(minHeight: 44)
            }
            weekButton("chevron.left", label: "Previous week", offset: -1)
            weekButton("chevron.right", label: "Next week", offset: 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(timeOfDay.canvasPrimaryText)
    }

    private func weekButton(_ symbol: String, label: String, offset: Int) -> some View {
        Button {
            guard let date = PlannerCalendarPolicy.movingWeeks(offset, from: store.selectedDate) else { return }
            store.select(date)
        } label: {
            Image(systemName: symbol)
                .font(.community(.footnote, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(timeOfDay.surfaceRaised, in: Circle())
                .overlay { Circle().strokeBorder(timeOfDay.canvasBorder) }
        }
        .accessibilityLabel(label)
    }

    // MARK: - Days

    private var dayTabs: some View {
        HStack(spacing: 5) {
            ForEach(weekDays, id: \.timeIntervalSince1970) { date in
                dayTab(date)
            }
        }
        // Seven tabs across, for the same reason the month grid has seven
        // columns. Capped here rather than on the whole card, so the
        // categories and the progress line underneath still grow.
        .typeSizeCeiling()
    }

    private func dayTab(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            store.select(date)
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.community(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? timeOfDay.onPrimaryAction : timeOfDay.canvasSecondaryText
                    )
                Text("\(calendar.component(.day, from: date))")
                    .font(.community(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? timeOfDay.onPrimaryAction : timeOfDay.canvasPrimaryText)
                marker(for: date, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(tabBackground(isSelected: isSelected, isToday: isToday))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(store.hasEntries(on: date) ? "Items planned" : "Nothing planned")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A single dot saying "something is planned", rather than a count: the
    /// strip is for choosing a day, and the list below answers what is on it.
    private func marker(for date: Date, isSelected: Bool) -> some View {
        Circle()
            .fill(
                store.hasEntries(on: date)
                    ? (isSelected ? timeOfDay.onPrimaryAction : PlannerStyle.accentText)
                    : Color.clear
            )
            .frame(width: 4, height: 4)
    }

    @ViewBuilder
    private func tabBackground(isSelected: Bool, isToday: Bool) -> some View {
        if isSelected {
            Capsule().fill(timeOfDay.primaryActionSurface)
        } else if isToday {
            Capsule().strokeBorder(PlannerStyle.accentText.opacity(0.5), lineWidth: 1)
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
                .foregroundStyle(isSelected ? timeOfDay.onPrimaryAction : timeOfDay.canvasPrimaryText)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(
                    isSelected ? timeOfDay.primaryActionSurface : tint.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private var progress: some View {
        let counts = store.taskCounts(on: store.selectedDate)
        let cleared = counts.total > 0 && counts.done == counts.total
        return HStack(spacing: 10) {
            Image(systemName: cleared ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.community(.title3))
                .foregroundStyle(cleared ? PlannerStyle.success : PlannerStyle.accentText)
            Text(store.isLoading ? "Loading your plan…" : (counts.total == 0 ? "A fresh start. Make it yours." : "\(counts.done) of \(counts.total) tasks done"))
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer(minLength: 0)
            if counts.total > 0, !store.isLoading {
                Text(cleared ? "Day cleared" : "Keep going")
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(cleared ? PlannerStyle.success : PlannerStyle.accentText)
            }
        }
        .plannerSurface(soft: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dates

    /// The week the selected day sits in, Monday first, matching the rest of
    /// the app rather than the device's locale.
    private var weekDays: [Date] {
        PlannerCalendarPolicy.week(containing: store.selectedDate)
    }
}
