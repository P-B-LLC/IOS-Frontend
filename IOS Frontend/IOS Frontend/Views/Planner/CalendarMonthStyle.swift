import Foundation
import SwiftUI

/// A display projection, never an editable PlannerEntry. Shared rows cannot
/// enter own completion, reminders, workouts or planner writes.
struct CalendarMonthItem: Identifiable {
    let id: String
    var sharedID: String? = nil
    let title: String
    let date: String
    var time: String? = nil
    var isComplete = false
    let color: Color
    var ownerLabel: String? = nil
    var durationMinutes: Int? = nil
    var schedulingTimezone: String? = nil
    var category: PlannerCategory? = nil

    static func own(_ entry: PlannerEntry) -> CalendarMonthItem {
        CalendarMonthItem(id: "own:" + (entry.serverID.map(String.init) ?? entry.id.uuidString),
                          title: entry.title, date: entry.date, time: entry.time,
                          isComplete: entry.isComplete, color: entry.displayColor, category: entry.category)
    }

    var compactTitle: String {
        guard let ownerLabel, !ownerLabel.isEmpty else { return title }
        return String(ownerLabel.prefix(1)) + ": " + title
    }

    var accessibilityTitle: String {
        var parts = [title]
        if let ownerLabel, !ownerLabel.isEmpty { parts.insert(ownerLabel, at: 0) }
        if let schedulingTimezone, !schedulingTimezone.isEmpty { parts.append(schedulingTimezone) }
        return parts.joined(separator: " · ")
    }
}

enum CalendarMonthStyle {
    static let surface = RepbaseTactileDesign.surface
    static let ink = RepbaseTactileDesign.ink
    static let secondary = RepbaseTactileDesign.secondaryText
    static let border = RepbaseTactileDesign.border

    /// Approved colors invert to pastels after dark; legacy category tints
    /// also remain readable by resolving the actual fill before choosing ink.
    static func foreground(on color: Color, environment: EnvironmentValues) -> Color {
        let resolved = color.resolve(in: environment)
        func linear(_ channel: Float) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(resolved.red) + 0.7152 * linear(resolved.green) + 0.0722 * linear(resolved.blue)
        return luminance > 0.179 ? .black : .white
    }
}

/// No checkbox, steps, editing context menu, or another person's workout link.
struct CalendarSharedItemRow: View {
    let item: CalendarMonthItem
    var onSelect: ((CalendarMonthItem) -> Void)?

    var body: some View {
        Button { onSelect?(item) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 4)
                Image(systemName: "person.crop.circle")
                    .font(.community(.title3)).foregroundStyle(item.color)
                    .frame(width: 36, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.community(.subheadline, weight: .semibold))
                        .strikethrough(item.isComplete)
                        .foregroundStyle(item.isComplete ? CalendarMonthStyle.secondary : CalendarMonthStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.community(.footnote)).foregroundStyle(CalendarMonthStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.community(.caption))
                    .foregroundStyle(CalendarMonthStyle.secondary).accessibilityHidden(true)
            }
            .padding(.vertical, 10).padding(.trailing, 12)
            .frame(minHeight: 74)
            .background(CalendarMonthStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(CalendarMonthStyle.border, lineWidth: 0.75) }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RepbaseTactilePressStyle())
        .disabled(onSelect == nil)
        .accessibilityHint("View only")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let owner = item.ownerLabel { parts.append(owner) }
        if let minutes = PlannerDuration.minutesPastMidnight(item.time) {
            parts.append(PlannerDuration.clockText(minutesPastMidnight: minutes))
        } else { parts.append(String(localized: "Anytime", bundle: .app, locale: .app)) }
        if let timezone = item.schedulingTimezone, !timezone.isEmpty { parts.append(timezone) }
        parts.append(String(localized: "View only", bundle: .app, locale: .app))
        return parts.joined(separator: " · ")
    }
}
