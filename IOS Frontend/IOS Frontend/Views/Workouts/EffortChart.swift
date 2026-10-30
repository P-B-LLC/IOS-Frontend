//
//  EffortChart.swift
//  IOS Frontend
//
//  "How hard was it?" -- a 0 to 100 rating drawn as a rising row of bars.
//

import SwiftUI

/// The perceived-effort rating: twenty rounded bars climbing from left to
/// right, lit in caramel up to the value chosen.
///
/// The shape is the scale. A ramp says "more is harder" before any label is
/// read, and the lit bars grow with the effort, so a glance at a saved session
/// shows roughly how hard it was. The bars come in five groups of four, one
/// per `EffortLevel` band. Drag or tap anywhere on the chart to set a value: a
/// bubble with the number follows the finger, and every bar that lights or
/// empties taps back (`EffortHaptics` decides when, and how firmly).
///
/// Nil is a real answer: "I didn't rate it". The rating is the person's own
/// judgement and is optional everywhere it is asked.
struct EffortChart: View {
    @Binding var value: Int?
    var phase: WorkoutVisualPhase = .prepare
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var axisHeight: CGFloat = 14
    @State private var scrubbing = false
    @State private var appeared = false
    @State private var haptics = EffortHaptics()
    @State private var tick: EffortHaptics.Tick?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let layout = Layout(size: proxy.size, mirrored: mirrored)
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<EffortScale.barCount, id: \.self) { index in
                            bar(index, layout: layout)
                        }
                        if scrubbing, let value {
                            callout(value, layout: layout)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(scrub(layout))
                }
                .frame(height: chartHeight)
                axis
            }
            // Drawn left to right and mirrored by hand, so the ramp, the
            // finger and the numbers under it turn round together in Arabic.
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel("Perceived effort")
            .accessibilityIdentifier("effort-chart")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Swipe up or down to change it by 5.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(min((value ?? 45) + 5, 100), at: .now)
                case .decrement: select(max((value ?? 55) - 5, 0), at: .now)
                @unknown default: break
                }
            }
            .sensoryFeedback(trigger: tick) { _, tick in
                tick.map { .impact(flexibility: $0.firmness.flexibility, intensity: $0.intensity) }
            }
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let value {
                let level = EffortLevel(score: value)
                Text("\(value)")
                    .font(.community(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(phase.accent)
                    .contentTransition(.numericText(value: Double(value)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.community(.headline))
                        .foregroundStyle(phase.primaryText)
                        .contentTransition(.opacity)
                    Text(level.detail)
                        .font(.community(.caption))
                        .foregroundStyle(phase.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 4)
                Button("Clear") {
                    haptics.end()
                    self.value = nil
                }
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(phase.secondaryText)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Clear effort rating")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not rated")
                        .font(.community(.headline))
                        .foregroundStyle(phase.primaryText)
                    Text("Tap or drag across the chart. 0 is no effort, 100 is everything you had.")
                        .font(.community(.caption))
                        .foregroundStyle(phase.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(.snappy(duration: 0.18), value: value)
    }

    /// The band edges, 0 to 100, under the gaps between the groups of bars.
    /// The two around the current value are picked out.
    private var axis: some View {
        GeometryReader { proxy in
            let layout = Layout(size: proxy.size, mirrored: mirrored)
            let band = value.map { EffortLevel(score: $0).rawValue }
            ForEach(0...EffortLevel.allCases.count, id: \.self) { mark in
                let label = layout.axisLabel(mark)
                // Formatted, so the digits match the number above in a
                // language that writes its own (٢٠ in Arabic).
                Text(mark * 20, format: .number)
                    .font(.community(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(band == mark || band == mark - 1 ? phase.accent : phase.secondaryText)
                    .lineLimit(1)
                    .frame(width: Layout.axisLabelWidth, alignment: label.alignment)
                    .position(x: label.x, y: proxy.size.height / 2)
            }
            .animation(.smooth(duration: 0.2), value: band)
        }
        .frame(height: axisHeight)
        .accessibilityHidden(true)
    }

    private var mirrored: Bool { layoutDirection == .rightToLeft }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 208 : 176
    }

    private var litBars: Int {
        value.map(EffortScale.litBars(for:)) ?? 0
    }

    private var accessibilityValue: String {
        guard let value else {
            return String(localized: "Not rated", bundle: .app, locale: .app)
        }
        return String(
            localized: "\(value) out of 100, \(EffortLevel(score: value).title)",
            bundle: .app,
            locale: .app,
            comment: "Perceived effort read by VoiceOver, such as “72 out of 100, Hard”"
        )
    }

    private func scrub(_ layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if !scrubbing {
                    withAnimation(.snappy(duration: 0.18)) { scrubbing = true }
                }
                select(layout.value(at: drag.location.x), at: drag.time)
            }
            .onEnded { _ in
                withAnimation(.smooth(duration: 0.25)) { scrubbing = false }
                haptics.end()
            }
    }

    private func select(_ newValue: Int, at time: Date) {
        if value != newValue { value = newValue }
        if let next = haptics.move(to: newValue, at: time.timeIntervalSinceReferenceDate) {
            tick = next
        }
    }

    /// One bar: a quiet track until lit, then caramel that deepens up the
    /// ramp. The one under the finger lifts a little.
    private func bar(_ index: Int, layout: Layout) -> some View {
        let lit = index < litBars
        let lifted = scrubbing && index == litBars - 1
        let height = layout.barHeight(index)
        let depth = 0.55 + 0.45 * Double(index + 1) / Double(EffortScale.barCount)
        return RoundedRectangle(cornerRadius: layout.barWidth / 2, style: .continuous)
            .fill(lit ? phase.accent.opacity(depth) : phase.primaryText.opacity(0.08))
            .frame(width: layout.barWidth, height: height)
            .scaleEffect(x: 1, y: lifted ? 1.06 : (appeared || reduceMotion ? 1 : 0.08), anchor: .bottom)
            .position(x: layout.midX(index), y: layout.size.height - height / 2)
            .animation(.smooth(duration: 0.16), value: lit)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.62), value: lifted)
            .animation(
                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.014),
                value: appeared
            )
    }

    /// The number under the finger, floating above the last lit bar.
    private func callout(_ value: Int, layout: Layout) -> some View {
        let lit = EffortScale.litBars(for: value)
        let x = lit == 0 ? layout.leadingEdge : layout.midX(lit - 1)
        let top = layout.size.height - layout.barHeight(max(lit - 1, 0)) * 1.06
        return Text("\(value)")
            .font(.community(.subheadline, weight: .bold).monospacedDigit())
            .foregroundStyle(phase.surfaceStart)
            .contentTransition(.numericText(value: Double(value)))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(phase.primaryText))
            .fixedSize()
            .position(x: min(max(x, 24), layout.size.width - 24), y: max(top - 20, 14))
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: value)
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
            .accessibilityHidden(true)
    }

    /// Where everything is drawn, worked out left to right and flipped at the
    /// end for a right-to-left language.
    private struct Layout {
        let size: CGSize
        let mirrored: Bool

        /// Room above the tallest bar for the bubble that follows a finger.
        static let calloutRoom: CGFloat = 34
        /// Wide enough for "100" at the largest caption size the axis shows.
        static let axisLabelWidth: CGFloat = 44

        var innerGap: CGFloat { max(2, size.width * 0.009) }
        var bandGap: CGFloat { max(6, size.width * 0.03) }

        var barWidth: CGFloat {
            let bands = EffortLevel.allCases.count
            let gaps = innerGap * CGFloat(EffortScale.barCount - bands) + bandGap * CGFloat(bands - 1)
            return max((size.width - gaps) / CGFloat(EffortScale.barCount), 2)
        }

        /// Left edge of a bar, before mirroring.
        private func start(_ index: Int) -> CGFloat {
            let band = index / EffortScale.barsPerBand
            return CGFloat(index) * barWidth + CGFloat(index - band) * innerGap + CGFloat(band) * bandGap
        }

        private func onScreen(_ x: CGFloat) -> CGFloat { mirrored ? size.width - x : x }

        var leadingEdge: CGFloat { onScreen(0) }

        func midX(_ index: Int) -> CGFloat { onScreen(start(index) + barWidth / 2) }

        /// The ramp rises evenly from a stub to the full height.
        func barHeight(_ index: Int) -> CGFloat {
            let usable = max(size.height - Self.calloutRoom, 1)
            let lowest = usable * 0.16
            return lowest + (usable - lowest) * CGFloat(index) / CGFloat(EffortScale.barCount - 1)
        }

        /// The value under a finger. A touch in a gap belongs to the bar
        /// before it: the gap is the top of that bar's five points. Only the
        /// leading edge itself, or past it, is 0.
        func value(at x: CGFloat) -> Int {
            let x = mirrored ? size.width - x : x
            guard x > 0 else { return 0 }
            for index in 0..<EffortScale.barCount {
                let start = start(index)
                if x <= start + barWidth {
                    return EffortScale.value(bar: index, fraction: Double((x - start) / barWidth))
                }
                if index + 1 < EffortScale.barCount, x < self.start(index + 1) {
                    return (index + 1) * EffortScale.pointsPerBar
                }
            }
            return 100
        }

        /// Where the number for band edge `mark` (0 to 5) sits: centred in the
        /// gap between two groups, or flush with either end of the chart.
        func axisLabel(_ mark: Int) -> (x: CGFloat, alignment: Alignment) {
            let last = EffortLevel.allCases.count
            guard mark == 0 || mark == last else {
                return (onScreen(start(mark * EffortScale.barsPerBand) - bandGap / 2), .center)
            }
            let atLeft = (mark == 0) != mirrored
            return atLeft
                ? (Self.axisLabelWidth / 2, .leading)
                : (size.width - Self.axisLabelWidth / 2, .trailing)
        }
    }
}

private extension EffortHaptics.Firmness {
    var flexibility: SensoryFeedback.Flexibility {
        switch self {
        case .soft: .soft
        case .solid: .solid
        case .rigid: .rigid
        }
    }
}

#Preview {
    @Previewable @State var value: Int? = 64
    EffortChart(value: $value)
        .padding()
}
