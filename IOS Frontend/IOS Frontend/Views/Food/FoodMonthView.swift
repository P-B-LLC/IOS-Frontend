//
//  FoodMonthView.swift
//  IOS Frontend
//
//  A month of eating at once, reached from the week strip.
//

import SwiftUI

struct FoodMonthView: View {
    /// The day the food page is showing, changed by picking one here.
    @Binding var selectedDate: Date

    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.homeTimeOfDay) private var timeOfDay

    @State private var month: Date = Date()

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                weekdayHeadings
                grid
                legend
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.vertical, 14)
        }
        .repbaseScreen(.prepare)
        .navigationTitle("Food by month")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            month = calendar.startOfDay(for: selectedDate)
            await store.ensureMonth(month)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Text(monthSummary)
                    .font(.caption)
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 30)
            }
            .accessibilityLabel("Next month")
        }
        .overlay(alignment: .trailing) {
            if store.isLoadingMonth {
                ProgressView().controlSize(.small).offset(x: 26)
            }
        }
    }

    /// Says what the month actually holds, rather than leaving the grid to be
    /// counted by eye.
    private var monthSummary: String {
        let logged = daysInMonth.filter { store.hasLoggedFood(on: $0) }.count
        guard logged > 0 else { return "Nothing logged yet" }
        // Spelled out rather than using ^[...](inflect:), which only works on
        // a LocalizedStringKey literal. Handed a String it prints the markup
        // verbatim, which is what it did here.
        return "\(logged) \(logged == 1 ? "day" : "days") logged"
    }

    private var weekdayHeadings: some View {
        HStack(spacing: 4) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            // Blanks so the first of the month lands under the right weekday.
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 54)
            }

            ForEach(daysInMonth, id: \.self) { day in
                Button {
                    selectedDate = day
                    dismiss()
                } label: {
                    dayCell(day)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calories = store.total(on: day).calories
        let logged = store.hasLoggedFood(on: day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)

        return VStack(spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(
                    isSelected ? RepbasePalette.cream : timeOfDay.primaryText
                )

            // The number, not a dot. The point of a month view is comparing
            // days, and "2,140" against "900" says something a dot cannot.
            if logged {
                Text(calories.nutritionText)
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(
                        isSelected ? RepbasePalette.cream : timeOfDay.secondaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
            isSelected
                ? timeOfDay.accent
                : (logged ? timeOfDay.accent.opacity(0.12) : Color.primary.opacity(0.03)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if calendar.isDateInToday(day), !isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(timeOfDay.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel(day, logged: logged, calories: calories))
    }

    private func accessibilityLabel(
        _ day: Date,
        logged: Bool,
        calories: Decimal
    ) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard logged else { return "\(date), nothing logged" }
        return "\(date), \(calories.nutritionText) calories"
    }

    private var legend: some View {
        Text("Calories per day. Tap a day to open it.")
            .font(.caption)
            .foregroundStyle(timeOfDay.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Dates

    private var daysInMonth: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        var days: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return days
    }

    /// How far into the first row the first of the month sits, in the user's
    /// own first-weekday setting rather than an assumed Sunday.
    private var leadingBlanks: Int {
        guard let first = daysInMonth.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func changeMonth(by amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: month) else {
            return
        }
        month = next
        Task { await store.ensureMonth(next) }
    }
}
