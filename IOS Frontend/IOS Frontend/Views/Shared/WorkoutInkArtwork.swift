import SwiftUI

/// Compact geometric activity symbols designed to stay clear at selector size.
struct WorkoutInkArtwork: View {
    let type: WorkoutType
    var size: CGFloat = 48
    var color: Color = RepbaseDesign.ink

    var body: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width, canvas.height) / 56
            var strokes = Path()
            let point: (CGFloat, CGFloat) -> CGPoint = { CGPoint(x: $0 * scale, y: $1 * scale) }

            func segment(_ coordinates: [(CGFloat, CGFloat)]) {
                guard let first = coordinates.first else { return }
                strokes.move(to: point(first.0, first.1))
                for coordinate in coordinates.dropFirst() {
                    strokes.addLine(to: point(coordinate.0, coordinate.1))
                }
            }

            switch type {
            case .lifting:
                segment([(20, 24), (28, 18), (36, 24)])
                segment([(28, 19), (28, 34), (19, 45), (15, 45)])
                segment([(28, 34), (37, 45), (41, 45)])
                segment([(20, 24), (13, 20)])
                segment([(36, 24), (43, 20)])
                segment([(12, 16), (12, 24)])
                segment([(44, 16), (44, 24)])
                segment([(8, 16), (16, 16)])
                segment([(40, 16), (48, 16)])
            case .running:
                segment([(27, 19), (20, 29), (30, 34), (19, 40), (12, 47)])
                segment([(30, 34), (40, 42), (48, 42)])
                segment([(22, 26), (13, 21)])
                segment([(36, 21), (44, 26)])
                segment([(27, 19), (36, 21), (30, 34)])
            case .biking:
                strokes.addEllipse(in: CGRect(x: 5 * scale, y: 31 * scale, width: 18 * scale, height: 18 * scale))
                strokes.addEllipse(in: CGRect(x: 34 * scale, y: 31 * scale, width: 18 * scale, height: 18 * scale))
                segment([(27, 17), (19, 26), (30, 32), (43, 40)])
                segment([(19, 26), (14, 40), (30, 32), (28, 40)])
                segment([(37, 22), (45, 18)])
            case .swimming:
                segment([(29, 23), (20, 31), (33, 35), (46, 30)])
                segment([(20, 31), (11, 25)])
                segment([(34, 34), (44, 23)])
                for y in [42, 49] as [CGFloat] {
                    strokes.move(to: point(8, y))
                    strokes.addCurve(to: point(21, y), control1: point(13, y - 5), control2: point(16, y + 5))
                    strokes.addCurve(to: point(34, y), control1: point(26, y - 5), control2: point(29, y + 5))
                    strokes.addCurve(to: point(47, y), control1: point(39, y - 5), control2: point(42, y + 5))
                }
            }

            let headCenter: CGPoint
            switch type {
            case .lifting: headCenter = point(28, 11)
            case .running: headCenter = point(33, 10)
            case .biking: headCenter = point(31, 9)
            case .swimming: headCenter = point(35, 18)
            }
            context.fill(
                Path(ellipseIn: CGRect(x: headCenter.x - 5 * scale, y: headCenter.y - 5 * scale, width: 10 * scale, height: 10 * scale)),
                with: .color(color)
            )
            context.stroke(
                strokes,
                with: .color(color),
                style: StrokeStyle(lineWidth: 3.6 * scale, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
