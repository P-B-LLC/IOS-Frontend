import Foundation
import XCTest
@testable import AccountSafety

/// The effort chart's twenty bars, and the ticks a finger feels crossing them.
final class EffortHapticsTests: XCTestCase {
    // MARK: - The scale

    func testEachValueLightsTheBarsOfItsOwnBand() {
        XCTAssertEqual(EffortScale.litBars(for: 0), 0, "0 lights nothing")
        XCTAssertEqual(EffortScale.litBars(for: 1), 1)
        XCTAssertEqual(EffortScale.litBars(for: 5), 1)
        XCTAssertEqual(EffortScale.litBars(for: 6), 2)
        XCTAssertEqual(EffortScale.litBars(for: 96), 20)
        XCTAssertEqual(EffortScale.litBars(for: 100), 20)
        XCTAssertEqual(EffortScale.litBars(for: -4), 0)
        XCTAssertEqual(EffortScale.litBars(for: 140), 20)
        // The groups of four the eye sees are the bands the words name.
        for score in 0...100 {
            XCTAssertEqual(EffortScale.band(litBars: EffortScale.litBars(for: score)),
                           EffortLevel(score: score).rawValue, "\(score)")
        }
    }

    func testTouchingABarAlwaysLightsThatBar() {
        for bar in 0..<EffortScale.barCount {
            for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
                let value = EffortScale.value(bar: bar, fraction: fraction)
                XCTAssertEqual(EffortScale.litBars(for: value), bar + 1, "bar \(bar) at \(fraction)")
            }
        }
        XCTAssertEqual(EffortScale.value(bar: 0, fraction: 0), 1)
        XCTAssertEqual(EffortScale.value(bar: 19, fraction: 1), 100)
        XCTAssertEqual(EffortScale.value(bar: 40, fraction: 2), 100, "out of range is clamped, never past 100")
    }

    // MARK: - Ticks

    /// A drag across the chart, `pointsPerSecond` fast, from 0 to 100.
    private func swipe(pointsPerSecond: Double, through values: [Int] = Array(0...100)) -> [EffortHaptics.Tick] {
        var haptics = EffortHaptics()
        return values.enumerated().compactMap { index, value in
            haptics.move(to: value, at: Double(index) / pointsPerSecond)
        }
    }

    func testASlowDragTicksOncePerBarAndNeverWithinOne() {
        let ticks = swipe(pointsPerSecond: 10)
        XCTAssertEqual(ticks.map(\.litBars), Array(0...20), "the touch at 0, then one per bar")
        XCTAssertEqual(ticks.filter { $0.kind == .band }.map(\.litBars), [5, 9, 13, 17], "entering each band after the first")
        XCTAssertEqual(ticks.first?.kind, .limit)
        XCTAssertEqual(ticks.last?.kind, .limit, "the last bar is a solid stop")
        XCTAssertEqual(Set(ticks.map(\.serial)).count, ticks.count, "every tick plays, even two alike")
    }

    func testAFastSwipeSkipsStepsButNeverABandOrAnEnd() {
        // The whole chart in a tenth of a second.
        let ticks = swipe(pointsPerSecond: 1000)
        XCTAssertEqual(ticks.filter { $0.kind == .band }.count, 4)
        XCTAssertEqual(ticks.filter { $0.kind == .limit }.map(\.litBars), [0, 20])
        XCTAssertLessThan(ticks.count, 10, "steps a millisecond apart would blur into a buzz")
    }

    func testStepsAreNeverCloserThanTheMinimumInterval() {
        var haptics = EffortHaptics()
        var last: TimeInterval?
        // 60 points a second: a bar every 83 ms, with jitter on the frames.
        for frame in 0..<200 {
            let time = Double(frame) / 60 + (frame.isMultiple(of: 3) ? 0.004 : 0)
            let value = min(frame / 2 + 1, 100)
            guard let tick = haptics.move(to: value, at: time) else { continue }
            if tick.kind == .step, let last {
                XCTAssertGreaterThanOrEqual(time - last, EffortHaptics.minimumInterval, "frame \(frame)")
            }
            last = time
        }
    }

    func testGoingBackDownTicksToo() {
        let ticks = swipe(pointsPerSecond: 10, through: Array((40...60).reversed()) + Array((0...39).reversed()))
        XCTAssertEqual(ticks.first?.litBars, 12)
        XCTAssertEqual(ticks.filter { $0.kind == .band }.map(\.litBars), [8, 4], "leaving a band is felt as well")
        XCTAssertEqual(ticks.last?.kind, .limit, "emptying the chart is the other stop")
        XCTAssertEqual(ticks.last?.litBars, 0)
    }

    func testStayingOnABarIsSilentUntilTheFingerLifts() {
        var haptics = EffortHaptics()
        XCTAssertNotNil(haptics.move(to: 42, at: 0))
        XCTAssertNil(haptics.move(to: 43, at: 1), "same bar")
        XCTAssertNil(haptics.move(to: 45, at: 2), "still the same bar")
        haptics.end()
        XCTAssertNotNil(haptics.move(to: 44, at: 3), "a new touch on the same bar confirms it")
    }

    func testTicksFirmUpAsTheEffortRises() {
        let ticks = swipe(pointsPerSecond: 10)
        let steps = ticks.filter { $0.kind == .step }
        XCTAssertEqual(steps.map(\.intensity), steps.map(\.intensity).sorted(), "each step at least as strong as the last")
        for tick in ticks {
            XCTAssertTrue((0...1).contains(tick.intensity), "\(tick)")
        }
        for band in ticks.filter({ $0.kind == .band }) {
            let before = steps.last { $0.litBars < band.litBars }
            XCTAssertGreaterThan(band.intensity, before?.intensity ?? 0, "a band is felt above the steps before it")
        }
        XCTAssertEqual(ticks.last?.intensity, 1)
        XCTAssertEqual(ticks.last?.firmness, .rigid)
        XCTAssertEqual(ticks.first?.firmness, .soft, "the empty end is a cushioned stop")
        XCTAssertEqual(steps.first?.firmness, .soft)
        XCTAssertEqual(steps.last?.firmness, .rigid)
        XCTAssertTrue(steps.contains { $0.firmness == .solid }, "the middle of the scale")
    }
}
