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

    @State private var positionedDate: String?

    private struct Focus: Hashable {
        let date: String
        let isLoading: Bool
    }

    var body: some View {
        let grouped = PlannerHourAgenda.grouped(entries, time: { $0.time })
        let date = PlannerStore.dateString(store.selectedDate)

        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(PlannerHourAgenda.hours, id: \.self) { hour in
                        hourRow(hour, entries: grouped[hour] ?? [])
                            .id(hour)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("planner.hourlySchedule")
            .task(id: Focus(date: date, isLoading: store.isLoading)) {
                // Wait for the selected day's data, and position only once.
                // Completing a task or refreshing must not jump the scroll.
                guard !store.isLoading, positionedDate != date else { return }
                let hour = PlannerHourAgenda.initialHour(
                    scheduledHours: Array(grouped.keys),
                    isToday: Calendar.current.isDateInToday(store.selectedDate),
                    currentHour: Calendar.current.component(.hour, from: Date())
                )
                reader.scrollTo(hour, anchor: .top)
                positionedDate = date
            }
        }
        .background(timeOfDay.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(timeOfDay.canvasBorder)
        }
        .overlay {
            if store.isLoading {
                ProgressView("Loading your day…")
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
    }

    private func hourRow(_ hour: Int, entries: [PlannerEntry]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.label(for: hour))
                .font(.community(.caption2, weight: .medium))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .typeSizeCeiling()
                .frame(width: 48, alignment: .trailing)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(timeOfDay.canvasBorder).frame(height: 1)
                    .accessibilityHidden(true)
                ForEach(entries) { entry in
                    PlannerEntryRow(entry: entry, onEdit: { onSelect(entry) },
                                    onOpenWorkout: onOpenWorkout)
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
