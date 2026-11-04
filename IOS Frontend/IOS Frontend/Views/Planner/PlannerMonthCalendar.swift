import Foundation
import SwiftUI

/// One aligned grid. Days are the controls; title bars are bounded previews,
/// never completion controls or joined recurrence spans.
struct PlannerMonthCalendar: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.self) private var environment
    @Environment(\.homeTimeOfDay) private var timeOfDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var clearedDate: String? = nil
    var completionPulse = false
    var showsOwn = true
    var additionalItems: [CalendarMonthItem] = []
    var additionalCounts: [String: Int] = [:]
    var onSelectDate: ((Date) -> Void)? = nil
    var visibilityControls: AnyView? = nil

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 10) {
            monthControls.padding(.horizontal, 12)
            if let visibilityControls { visibilityControls.padding(.horizontal, 12) }
            weekdayLabels
            VStack(spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(week, id: \.timeIntervalSince1970) { date in
                            dayCell(date).frame(maxWidth: .infinity)
                        }
                    }
                    if index < weeks.count - 1 {
                        Rectangle().fill(CalendarMonthStyle.border).frame(height: 0.75)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .typeSizeCeiling()
        .accessibilityIdentifier("planner.monthGrid")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.selectedDate)
    }

    private var monthControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                monthTitle
                Spacer(minLength: 4)
                todayButton
                stepper("chevron.left", label: "Previous month", offset: -1)
                stepper("chevron.right", label: "Next month", offset: 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                monthTitle
                HStack(spacing: 0) {
                    todayButton
                    Spacer(minLength: 0)
                    stepper("chevron.left", label: "Previous month", offset: -1)
                    stepper("chevron.right", label: "Next month", offset: 1)
                }
            }
        }
    }

    private var monthTitle: some View {
        Text(store.visibleMonth.formatted(.dateTime.month(.wide).year().locale(.app)))
            .font(.community(size: 18, weight: .bold)).foregroundStyle(CalendarMonthStyle.ink)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var todayButton: some View {
        Button { store.showToday() } label: {
            Label("Today", systemImage: "calendar")
                .font(.community(.footnote))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(CalendarMonthStyle.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(CalendarMonthStyle.border, lineWidth: 0.75) }
                .frame(minHeight: 44)
        }
        .buttonStyle(RepbaseTactilePressStyle())
        .foregroundStyle(CalendarMonthStyle.ink)
        .accessibilityIdentifier("planner.showToday")
    }

    private func stepper(_ symbol: String, label: LocalizedStringKey, offset: Int) -> some View {
        Button { store.showMonth(offsetBy: offset) } label: {
            Image(systemName: symbol).font(.community(.footnote))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(RepbaseTactilePressStyle()).foregroundStyle(CalendarMonthStyle.ink)
        .accessibilityLabel(label)
    }

    private var weekdayLabels: some View {
        HStack(spacing: 0) {
            ForEach(CalendarMonthPresentation.weekdayOrder(firstWeekday: calendar.firstWeekday), id: \.self) { weekday in
                Text(weekdaySymbols[weekday - 1])
                    .font(.community(size: 10, weight: .semibold)).foregroundStyle(CalendarMonthStyle.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = PlannerStore.dateString(date)
        let own = showsOwn ? store.entries(on: date) : []
        let shared = additionalItems.filter { $0.date == key }
        let previews = CalendarMonthPresentation.previews(own.map(CalendarMonthItem.own) + shared, time: { $0.time })
        let overflow = CalendarMonthPresentation.overflow(ownCount: own.count,
            sharedTotal: additionalCounts[key] ?? shared.count, shown: previews.count)
        let inMonth = PlannerStore.isSameMonth(date, store.visibleMonth)
        let selected = calendar.isDate(date, inSameDayAs: store.selectedDate)

        return Button {
            if let onSelectDate { onSelectDate(date) } else { store.select(date) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text(calendar.component(.day, from: date), format: .number.grouping(.never).locale(.app))
                        .font(.community(size: 11, weight: .bold))
                        .foregroundStyle(selected ? timeOfDay.onPrimaryAction : CalendarMonthStyle.ink)
                        .frame(width: 18, height: 18)
                        .background {
                            if selected { Circle().fill(PlannerStyle.accentText) }
                            else if calendar.isDateInToday(date) { Circle().strokeBorder(PlannerStyle.accentText, lineWidth: 1) }
                        }
                    if overflow > 0 {
                        Text(verbatim: "+" + overflow.formatted(.number.grouping(.never).locale(.app)))
                            .font(.community(size: 9, weight: .bold))
                            .foregroundStyle(CalendarMonthStyle.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                ForEach(previews) { item in titleBar(item) }
                Spacer(minLength: 0)
            }
            .padding(2)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .opacity(inMonth ? 1 : 0.42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(date, own: own, shared: shared,
            sharedTotal: additionalCounts[key] ?? shared.count))
        .accessibilityHint("Show this day’s tasks and events")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("planner.date.\(key)")
    }

    private func titleBar(_ item: CalendarMonthItem) -> some View {
        Text((item.isComplete ? "✓ " : "") + item.compactTitle)
            .font(.community(size: 11, weight: .semibold))
            .foregroundStyle(CalendarMonthStyle.foreground(on: item.color, environment: environment))
            .lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            .background(item.color, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }

    private var weeks: [[Date]] {
        let days = CalendarMonthPresentation.days(in: store.visibleMonth, calendar: calendar)
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.calendar = calendar
        return formatter.shortStandaloneWeekdaySymbols
    }

    private func accessibilityLabel(_ date: Date, own: [PlannerEntry], shared: [CalendarMonthItem], sharedTotal: Int) -> String {
        var labels = [date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.app))]
        labels += own.map { $0.title + ($0.isComplete ? " · " + String(localized: "Complete", bundle: .app, locale: .app) : "") }
        labels += shared.map(\.accessibilityTitle)
        let remaining = max(0, sharedTotal - shared.count)
        if remaining > 0 {
            labels.append(String(localized: "\(remaining) more shared items", bundle: .app, locale: .app))
        }
        return labels.joined(separator: ". ")
    }
}
