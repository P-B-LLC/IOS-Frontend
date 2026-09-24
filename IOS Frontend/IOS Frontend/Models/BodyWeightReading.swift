//
//  BodyWeightReading.swift
//  IOS Frontend
//
//  One weigh-in.
//

import Foundation

nonisolated struct BodyWeightReading: Identifiable, Hashable, Sendable {
    /// The server's id. Every reading here came from the server, so unlike a
    /// planner draft there is no local-only state to represent.
    let id: Int
    let kilograms: Double
    let recordedAt: Date
    let notes: String

    init(id: Int, kilograms: Double, recordedAt: Date, notes: String = "") {
        self.id = id
        self.kilograms = kilograms
        self.recordedAt = recordedAt
        self.notes = notes
    }
}

extension Array where Element == BodyWeightReading {
    /// Oldest first, which is the order a chart reads in.
    var oldestFirst: [BodyWeightReading] {
        sorted { $0.recordedAt < $1.recordedAt }
    }

    /// The mean of the last `count` readings, or nil when there are none.
    ///
    /// Weight is noisy -- water, salt, the time of day -- and a single
    /// reading against a single earlier reading can say "up 1.4 kg" about a
    /// fortnight that went down. Averaging the ends is the cheapest honest
    /// way to answer "which way is this going".
    func average(last count: Int) -> Double? {
        let recent = oldestFirst.suffix(count)
        guard !recent.isEmpty else { return nil }
        return recent.map(\.kilograms).reduce(0, +) / Double(recent.count)
    }

    func average(first count: Int) -> Double? {
        let earliest = oldestFirst.prefix(count)
        guard !earliest.isEmpty else { return nil }
        return earliest.map(\.kilograms).reduce(0, +) / Double(earliest.count)
    }
}
