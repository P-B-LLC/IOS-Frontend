import Foundation

/// A recurring wall-clock schedule is not a fixed UTC interval. Resolve every
/// date independently in its saved IANA zone, including DST transitions.
nonisolated enum PlannerScheduledMoment {
    static func resolve(day: String, time: String?, zoneIdentifier: String?,
                        fallbackZone: TimeZone = .current) -> Date? {
        guard day.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
              let time,
              time.range(of: #"^[0-9]{2}:[0-9]{2}(?::[0-9]{2})?$"#, options: .regularExpression) != nil else { return nil }
        let dateParts = day.split(separator: "-").compactMap { Int($0) }
        let timeParts = time.split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count >= 2,
              (0...23).contains(timeParts[0]), (0...59).contains(timeParts[1]),
              timeParts.count == 2 || (0...59).contains(timeParts[2]) else { return nil }
        let zone: TimeZone
        if let zoneIdentifier, !zoneIdentifier.isEmpty {
            guard let savedZone = TimeZone(identifier: zoneIdentifier) else { return nil }
            zone = savedZone
        } else { zone = fallbackZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = DateComponents(timeZone: zone, year: dateParts[0], month: dateParts[1], day: dateParts[2])
        guard let midnight = calendar.date(from: date),
              let before = calendar.date(byAdding: .second, value: -1, to: midnight),
              let moment = calendar.nextDate(after: before,
                  matching: DateComponents(hour: timeParts[0], minute: timeParts[1],
                                           second: timeParts.count == 3 ? timeParts[2] : 0),
                  matchingPolicy: .nextTimePreservingSmallerComponents,
                  repeatedTimePolicy: .first, direction: .forward) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: moment)
        guard actual.year == dateParts[0], actual.month == dateParts[1], actual.day == dateParts[2] else { return nil }
        return moment
    }
}
