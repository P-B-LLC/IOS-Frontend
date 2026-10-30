//
//  PlannerWeekStrip.swift
//  IOS Frontend
//
//  Date navigation only. The day's filters and progress belong to its agenda.
//

import Foundation
import SwiftUI

struct PlannerWeekStrip: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

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
        }
        .plannerSurface(padding: 12)
    }

    // MARK: - Opening the month

    private var monthButton: some View {
        HStack(spacing: 8) {
            Button {
                onToggleMonth?()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selectedDate.formatted(.dateTime.month(.wide).year().locale(.app)))
                        .font(.community(.subheadline, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Label("View month", systemImage: "chevron.down")
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("planner.viewMonth")
            .accessibilityLabel("Open the month, \(store.selectedDate.formatted(.dateTime.month(.wide).year().locale(.app)))")
            .accessibilityHint("Open the full month calendar")
            Spacer(minLength: 0)
            Button("Today") { store.showToday() }
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(PlannerStyle.accentText)
                .frame(minWidth: 44, minHeight: 44)
            weekButton("chevron.backward", label: "Previous week", offset: -1)
            weekButton("chevron.forward", label: "Next week", offset: 1)
        }
        .padding(.horizontal, 2)
        .buttonStyle(.plain)
        .foregroundStyle(timeOfDay.canvasPrimaryText)
    }

    private func weekButton(_ symbol: String, label: LocalizedStringKey, offset: Int) -> some View {
        Button {
            guard let date = PlannerCalendarPolicy.movingWeeks(offset, from: store.selectedDate) else { return }
            store.select(date)
        } label: {
            Image(systemName: symbol)
                .font(.community(.footnote, weight: .semibold))
                .frame(width: 44, height: 44)
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
        // columns. The agenda and its controls still use the full text size.
        .typeSizeCeiling()
    }

    private func dayTab(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let counts = store.taskCounts(on: date)
        let isComplete = counts.total > 0 && counts.done == counts.total
        let hasEntries = store.hasEntries(on: date)
        let tint = isComplete ? PlannerStyle.success : PlannerStyle.accentText

        return Button {
            store.select(date)
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(.app)))
                    .font(.community(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? tint : timeOfDay.canvasSecondaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(calendar.component(.day, from: date))")
                    .font(.community(size: 18, weight: .bold))
                    .foregroundStyle(isSelected || isComplete ? tint : timeOfDay.canvasPrimaryText)
                ZStack {
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.community(size: 9, weight: .bold))
                            .foregroundStyle(PlannerStyle.success)
                    } else if hasEntries {
                        Circle().fill(PlannerStyle.accentText).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(hasEntries || isSelected ? tint.opacity(0.09) : timeOfDay.selectorSurface.opacity(0.5))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? tint : (isToday ? timeOfDay.canvasBorder : .clear),
                                  lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.app)))
        .accessibilityValue(isComplete ? "Tasks complete" : (hasEntries ? "Items planned" : "Nothing planned"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Dates

    /// The week the selected day sits in, Monday first, matching the rest of
    /// the app rather than the device's locale.
    private var weekDays: [Date] {
        PlannerCalendarPolicy.week(containing: store.selectedDate)
    }
}
