import Foundation
import SwiftUI

/// A bounded window onto the day, not a 24-hour page. Cards are grouped by
/// their starting hour and show their actual time range. Concurrent entries
/// stack instead of obscuring each other, and expanding steps grows that hour.
struct PlannerDaySchedule: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay
    let entries: [PlannerEntry]
    let onSelect: (PlannerEntry) -> Void
    var onOpenWorkout: ((Weekday) -> Void)?
    var additionalItems: [CalendarMonthItem] = []
    var additionalIsLoading = false
    var onSelectShared: ((CalendarMonthItem) -> Void)? = nil

    @State private var positionedDate: String?

    private struct Focus: Hashable {
        let date: String
        let isLoading: Bool
    }

    var body: some View {
        let grouped = PlannerHourAgenda.grouped(entries, time: { $0.time })
        let date = PlannerStore.dateString(store.selectedDate)
        let shared = PlannerHourAgenda.grouped(additionalItems.filter { $0.date == date }, time: { $0.time })

        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(PlannerHourAgenda.hours, id: \.self) { hour in
                        hourRow(hour, entries: grouped[hour] ?? [], shared: shared[hour] ?? [])
                            .id(hour)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("planner.hourlySchedule")
            .task(id: Focus(date: date, isLoading: store.isLoading || additionalIsLoading)) {
                // Wait for the selected day's data, and position only once.
                // Completing a task or refreshing must not jump the scroll.
                guard !store.isLoading, !additionalIsLoading, positionedDate != date else { return }
                let hour = PlannerHourAgenda.initialHour(
                    scheduledHours: Array(Set(grouped.keys).union(shared.keys)),
                    isToday: Calendar.current.isDateInToday(store.selectedDate),
                    currentHour: Calendar.current.component(.hour, from: Date())
                )
                reader.scrollTo(hour, anchor: .top)
                positionedDate = date
            }
        }
        .background(CalendarMonthStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(CalendarMonthStyle.border, lineWidth: 0.75)
        }
        .overlay {
            if store.isLoading || additionalIsLoading {
                ProgressView("Loading your day…")
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
    }

    private struct Item: Identifiable {
        let id: String
        let time: String?
        let own: PlannerEntry?
        let shared: CalendarMonthItem?
    }

    private func hourRow(_ hour: Int, entries: [PlannerEntry], shared: [CalendarMonthItem]) -> some View {
        let items = entries.map { Item(id: "own:" + $0.id.uuidString, time: $0.time, own: $0, shared: nil) }
            + shared.map { Item(id: "shared:" + $0.id, time: $0.time, own: nil, shared: $0) }
        return HStack(alignment: .top, spacing: 8) {
            Text(Self.label(for: hour))
                .font(.community(.caption2, weight: .medium))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .typeSizeCeiling()
                .frame(width: 38, alignment: .leading)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Rectangle().fill(CalendarMonthStyle.border).frame(height: 0.75)
                        .accessibilityHidden(true)
                }
                ForEach(PlannerAgendaOrder.ordered(items, time: { $0.time })) { item in
                    if let entry = item.own {
                        PlannerEntryRow(entry: entry, onEdit: { onSelect(entry) },
                                        onOpenWorkout: onOpenWorkout)
                    } else if let shared = item.shared {
                        CalendarSharedItemRow(item: shared, onSelect: onSelectShared)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        }
        .padding(.bottom, 10)
    }

    private static func label(for hour: Int) -> String {
        // A fixed reference date keeps all 24 labels distinct on DST days.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: hour))!
        var format: Date.FormatStyle = .dateTime.hour().locale(.app)
        format.timeZone = calendar.timeZone
        return date.formatted(format)
    }
}
