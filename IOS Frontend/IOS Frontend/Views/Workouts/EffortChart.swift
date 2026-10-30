//
//  EffortChart.swift
//  IOS Frontend
//
//  "How hard was it?" -- a 0 to 100 rating drawn as a rising ramp.
//

import SwiftUI

/// The perceived-effort rating: five columns climbing from left to right,
/// one per band of twenty, filled in caramel up to the value chosen.
///
/// The shape is the scale. A ramp says "more is harder" before any label is
/// read, and the filled area grows with the effort, so a glance at a saved
/// session shows roughly how hard it was. Drag or tap anywhere on the chart to
/// set a value; the column under the finger fills to exactly that point.
///
/// Nil is a real answer: "I didn't rate it". The rating is the person's own
/// judgement and is optional everywhere it is asked.
struct EffortChart: View {
    @Binding var value: Int?
    var phase: WorkoutVisualPhase = .prepare
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let bands = EffortLevel.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GeometryReader { proxy in
                let layout = Layout(size: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(bands) { band in
                        column(band, layout: layout)
                    }
                    if let value {
                        knob(at: layout.point(for: value))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in value = layout.value(at: drag.location.x) }
                )
            }
            .frame(height: chartHeight)
            .accessibilityElement()
            .accessibilityLabel("Perceived effort")
            .accessibilityIdentifier("effort-chart")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Swipe up or down to change it by 5.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min((value ?? 45) + 5, 100)
                case .decrement: value = max((value ?? 55) - 5, 0)
                @unknown default: break
                }
            }
            .sensoryFeedback(.selection, trigger: value.map { EffortLevel(score: $0) })

            HStack(spacing: 0) {
                ForEach(bands) { band in
                    Text(verbatim: "\(band.range.lowerBound)–\(band.range.upperBound)")
                        .font(.community(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isSelected(band) ? phase.accent : phase.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
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
                    Text(level.detail)
                        .font(.community(.caption))
                        .foregroundStyle(phase.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button("Clear") { self.value = nil }
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

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 200 : 168
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

    private func isSelected(_ band: EffortLevel) -> Bool {
        value.map { EffortLevel(score: $0) == band } ?? false
    }

    /// One column: white with a dark outline, filled caramel up to the value.
    private func column(_ band: EffortLevel, layout: Layout) -> some View {
        let outline = layout.column(band.rawValue)
        let fillWidth = value.map { layout.filledWidth(of: band.rawValue, value: $0) } ?? 0
        return ZStack(alignment: .topLeading) {
            outline.fill(phase.surfaceStart)
            outline
                .fill(phase.accent)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: max(fillWidth, 0), height: layout.size.height)
                        .offset(x: layout.columnStart(band.rawValue))
                }
            outline.stroke(phase.primaryText, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .animation(.snappy(duration: 0.12), value: value)
    }

    private func knob(at point: CGPoint) -> some View {
        Circle()
            .fill(phase.accent)
            .overlay { Circle().strokeBorder(phase.surfaceStart, lineWidth: 3) }
            .frame(width: 22, height: 22)
            .shadow(color: phase.shadow, radius: 4, y: 2)
            .position(point)
            .animation(.snappy(duration: 0.12), value: point)
    }

    /// Where everything is drawn. The ramp rises at a constant slope through
    /// the gaps as well as the columns, so each column starts where the last
    /// would have continued, as in the reference drawing.
    private struct Layout {
        let size: CGSize

        var gap: CGFloat { max(8, size.width * 0.055) }
        var columnWidth: CGFloat { (size.width - gap * 4) / 5 }
        /// A little headroom so the knob never clips at 100.
        var rampTop: CGFloat { 12 }

        func columnStart(_ index: Int) -> CGFloat { CGFloat(index) * (columnWidth + gap) }

        /// Height of the ramp at a horizontal position.
        func height(at x: CGFloat) -> CGFloat {
            (size.height - rampTop) * min(max(x / size.width, 0), 1)
        }

        func column(_ index: Int) -> Path {
            let left = columnStart(index)
            let right = left + columnWidth
            let bottom = size.height
            var path = Path()
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: right, y: bottom - height(at: right)))
            path.addLine(to: CGPoint(x: left, y: bottom - height(at: left)))
            path.closeSubpath()
            return path
        }

        /// The x the value sits at: each column holds twenty points.
        func x(for value: Int) -> CGFloat {
            let clamped = min(max(value, 0), 100)
            let index = clamped == 0 ? 0 : min((clamped - 1) / 20, 4)
            let fraction = CGFloat(clamped - index * 20) / 20
            return columnStart(index) + fraction * columnWidth
        }

        func point(for value: Int) -> CGPoint {
            let x = x(for: value)
            return CGPoint(x: x, y: size.height - height(at: x))
        }

        /// How much of a column is filled at this value.
        func filledWidth(of index: Int, value: Int) -> CGFloat {
            let x = x(for: value)
            return min(max(x - columnStart(index), 0), columnWidth)
        }

        /// The value under a finger. A touch in a gap belongs to the column
        /// before it: the gap is the top of that band.
        func value(at x: CGFloat) -> Int {
            for index in 0..<5 {
                let start = columnStart(index)
                let end = start + columnWidth
                if x < start { return index * 20 }
                if x <= end {
                    let fraction = (x - start) / columnWidth
                    return min(max(Int((CGFloat(index * 20) + fraction * 20).rounded()), 0), 100)
                }
                if x < end + gap { return (index + 1) * 20 }
            }
            return 100
        }
    }
}

#Preview {
    @Previewable @State var value: Int? = 64
    EffortChart(value: $value)
        .padding()
}
