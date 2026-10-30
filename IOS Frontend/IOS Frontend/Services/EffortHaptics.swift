//
//  EffortHaptics.swift
//  IOS Frontend
//
//  The effort chart's bars as numbers, and what a finger feels crossing them.
//

import Foundation

/// The effort chart's twenty bars: which value lights which bar.
///
/// Each bar holds five points. The first lights at 1 and the last at 96; 0
/// lights none. Four bars make one `EffortLevel` band, so the five groups the
/// eye sees are the five bands the words describe.
nonisolated enum EffortScale {
    static let barCount = 20
    static let barsPerBand = 4
    static let pointsPerBar = 5

    /// How many bars a value lights: none for 0, all twenty from 96.
    static func litBars(for value: Int) -> Int {
        (min(max(value, 0), 100) + pointsPerBar - 1) / pointsPerBar
    }

    /// The band the last lit bar belongs to, the same one `EffortLevel(score:)`
    /// gives for the value.
    static func band(litBars: Int) -> Int {
        max(litBars - 1, 0) / barsPerBand
    }

    /// The value a finger means `fraction` (0 to 1) of the way across a bar:
    /// 1 to 5 points into it, so touching a bar always lights that bar.
    static func value(bar: Int, fraction: Double) -> Int {
        let bar = min(max(bar, 0), barCount - 1)
        let step = Int((min(max(fraction, 0), 1) * Double(pointsPerBar)).rounded(.up))
        return bar * pointsPerBar + min(max(step, 1), pointsPerBar)
    }
}

/// When the effort chart taps back, and how hard.
///
/// One tick each time the number of lit bars changes, so what the finger feels
/// is what the eye sees. Ticks firm up as the effort rises -- the scale can be
/// felt as well as read -- with a stronger one entering each band and a solid
/// stop at the top. A fast swipe crosses a bar every few milliseconds, and
/// ticks that close blur into a buzz, so ordinary steps nearer together than
/// `minimumInterval` are skipped. Band changes and the ends never are: there
/// are few of them, and they are the ones worth feeling.
///
/// Only decides; the view plays the tick through SwiftUI's sensory feedback,
/// which follows the System Haptics setting and does nothing on a device with
/// no Taptic Engine.
nonisolated struct EffortHaptics: Sendable {
    enum Kind: Sendable, Equatable {
        /// One more bar lit, or one fewer.
        case step
        /// Into a different `EffortLevel` band.
        case band
        /// The last bar lit, or every bar emptied.
        case limit
    }

    /// How the tap feels, from a cushioned thud to a crisp click.
    enum Firmness: Sendable, Equatable {
        case soft, solid, rigid
    }

    struct Tick: Sendable, Equatable {
        /// Tells two otherwise identical ticks apart, so both play.
        let serial: Int
        let kind: Kind
        let litBars: Int

        /// 0 to 1.
        var intensity: Double {
            let progress = Double(litBars) / Double(EffortScale.barCount)
            switch kind {
            case .step: return 0.35 + 0.45 * progress
            case .band: return min(0.6 + 0.4 * progress, 1)
            case .limit: return litBars == 0 ? 0.5 : 1
            }
        }

        var firmness: Firmness {
            switch kind {
            case .limit: return litBars == 0 ? .soft : .rigid
            case .step, .band:
                let band = EffortScale.band(litBars: litBars)
                return band < 2 ? .soft : band < 4 ? .solid : .rigid
            }
        }
    }

    static let minimumInterval: TimeInterval = 0.035

    private var litBars: Int?
    private var lastTick: TimeInterval?
    private var serial = 0

    /// The tick to play now that the rating is `value`, if any. `time` is in
    /// seconds on any steady clock.
    mutating func move(to value: Int, at time: TimeInterval) -> Tick? {
        let lit = EffortScale.litBars(for: value)
        guard lit != litBars else { return nil }
        let previous = litBars
        litBars = lit

        let kind: Kind
        if lit == 0 || lit == EffortScale.barCount {
            kind = .limit
        } else if let previous, EffortScale.band(litBars: previous) != EffortScale.band(litBars: lit) {
            kind = .band
        } else {
            kind = .step
        }
        if kind == .step, let lastTick, time - lastTick < Self.minimumInterval {
            return nil
        }
        lastTick = time
        serial += 1
        return Tick(serial: serial, kind: kind, litBars: lit)
    }

    /// The finger lifted or the rating was cleared, so the next touch ticks
    /// even if it lands on the same bar.
    mutating func end() {
        litBars = nil
    }
}
