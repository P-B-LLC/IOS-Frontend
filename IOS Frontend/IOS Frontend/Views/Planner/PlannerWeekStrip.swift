//
//  PlannerWeekStrip.swift
//  IOS Frontend
//
//  A compact index into the day's agenda. Selection, today, and completion
//  remain independent so browsing never disguises which day is finished.
//

import Foundation
import SwiftUI

struct PlannerWeekStrip: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    /// The month has its own button; tapping a day only selects that day.
    var onToggleMonth: (() -> Void)?

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if onToggleMonth != nil {
                navigationControls
            }
            dayTabs
            stateKey
        }
        .buttonStyle(PlannerWeekPressStyle())
        .sensoryFeedback(.selection, trigger: store.selectedDate)
    }

    // MARK: - Date navigation

    private var navigationControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                monthButton
                Spacer(minLength: 0)
                todayButton
                weekButton("chevron.backward", label: "Previous week", offset: -1)
                weekButton("chevron.forward", label: "Next week", offset: 1)
            }
            // Long month names, larger text, and narrow phones keep every
            // control reachable rather than squeezing the month to nothing.
            VStack(alignment: .leading, spacing: 8) {
                monthButton.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    todayButton
                    Spacer(minLength: 0)
                    weekButton("chevron.backward", label: "Previous week", offset: -1)
                    weekButton("chevron.forward", label: "Next week", offset: 1)
                }
            }
        }
        .foregroundStyle(timeOfDay.canvasPrimaryText)
    }

    private var monthButton: some View {
        Button {
            onToggleMonth?()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.selectedDate.formatted(.dateTime.month(.wide).year().locale(.app)))
                        .font(.community(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text("View month")
                        .font(.community(size: 11))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.community(size: 10, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 140, minHeight: 44, alignment: .leading)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: PlannerStyle.weekRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PlannerStyle.weekRadius)
                    .strokeBorder(timeOfDay.canvasBorder)
            }
            .contentShape(RoundedRectangle(cornerRadius: PlannerStyle.weekRadius))
        }
        .accessibilityIdentifier("planner.viewMonth")
        .accessibilityLabel("Open the month, \(store.selectedDate.formatted(.dateTime.month(.wide).year().locale(.app)))")
        .accessibilityHint("Open the full month calendar")
    }

    private var todayButton: some View {
        Button { store.showToday() } label: {
            Text("Today")
                .font(.community(size: 13, weight: .semibold))
                .foregroundStyle(PlannerStyle.accentText)
                .padding(.horizontal, 12)
                .frame(minWidth: 62, minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
                .background(timeOfDay.surfaceRaised, in: Capsule())
                .overlay { Capsule().strokeBorder(timeOfDay.canvasBorder) }
                .contentShape(Capsule())
        }
        .accessibilityIdentifier("planner.showToday")
    }

    private func weekButton(_ symbol: String, label: LocalizedStringKey, offset: Int) -> some View {
        Button {
            guard let date = PlannerCalendarPolicy.movingWeeks(offset, from: store.selectedDate) else { return }
            store.select(date)
        } label: {
            Image(systemName: symbol)
                .font(.community(size: 13, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(timeOfDay.surfaceRaised, in: Circle())
                .overlay { Circle().strokeBorder(timeOfDay.canvasBorder) }
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(offset < 0 ? "planner.previousWeek" : "planner.nextWeek")
    }

    // MARK: - Days

    private var dayTabs: some View {
        HStack(spacing: 6) {
            ForEach(PlannerCalendarPolicy.week(containing: store.selectedDate), id: \.timeIntervalSince1970) { date in
                dayTab(date)
            }
        }
        // This is a seven-column index into an agenda that supports full
        // Dynamic Type, matching the existing month and training calendars.
        .typeSizeCeiling()
    }

    private func dayTab(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let counts = store.taskCounts(on: date)
        let isComplete = counts.total > 0 && counts.done == counts.total
        let hasEntries = store.hasEntries(on: date)
        let dateLabel = date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.app))

        return Button {
            store.select(date)
        } label: {
            VStack(spacing: 3) {
                Group {
                    // A completed today uses its label above the date so the
                    // checkmark below never competes for the same small slot.
                    if isToday && isComplete {
                        Text("Today")
                    } else {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).locale(.app)))
                    }
                }
                    .font(.community(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? PlannerStyle.accentText : timeOfDay.canvasSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(calendar.component(.day, from: date), format: .number.grouping(.never).locale(.app))
                    .font(.community(size: 20, weight: .bold))
                    .foregroundStyle(isComplete ? PlannerStyle.success : (isSelected ? PlannerStyle.accentText : timeOfDay.canvasPrimaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                dayMarker(isToday: isToday, isComplete: isComplete, hasEntries: hasEntries)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background {
                RoundedRectangle(cornerRadius: PlannerStyle.weekRadius)
                    .fill(isComplete ? PlannerStyle.successSoft : (hasEntries || isSelected ? PlannerStyle.soft : .clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PlannerStyle.weekRadius)
                    .strokeBorder(isSelected ? PlannerStyle.accentText : .clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("planner.day.\(PlannerStore.dateString(date))")
        .accessibilityLabel(isToday ? Text("Today, \(dateLabel)") : Text(verbatim: dateLabel))
        .accessibilityValue(isComplete ? "Tasks complete" : (hasEntries ? "Items planned" : "Nothing planned"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func dayMarker(isToday: Bool, isComplete: Bool, hasEntries: Bool) -> some View {
        if isComplete {
            completionMark
        } else if isToday {
            Text("Today")
                .font(.community(size: 9, weight: .bold))
                .foregroundStyle(PlannerStyle.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if hasEntries {
            Circle().fill(PlannerStyle.accentText).frame(width: 4, height: 4)
        } else {
            Color.clear
        }
    }

    private var completionMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.community(size: 11, weight: .semibold))
            .foregroundStyle(PlannerStyle.success)
            .accessibilityHidden(true)
    }

    private var stateKey: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(PlannerStyle.accentText).frame(width: 4, height: 4)
                    .accessibilityHidden(true)
                Text("Planned")
            }
            HStack(spacing: 5) {
                completionMark
                Text("All done")
            }
        }
        .font(.community(size: 11))
        .foregroundStyle(timeOfDay.canvasSecondaryText)
    }
}

private struct PlannerWeekPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
