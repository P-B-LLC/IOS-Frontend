import SwiftUI

/// Scoped to the approved Meal review; other Sunrise pages keep their own depth.
struct MealLiftSurface: View {
    enum Kind { case card, control, primary }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let fill: Color
    var kind: Kind = .card
    var radius: CGFloat = RepbaseTactileDesign.cardRadius

    private var cornerRadius: CGFloat { kind == .primary ? 100 : radius }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(fill)
            .overlay {
                shape.fill(MealLiftGloss(opacity: kind == .primary ? 0.42 : 0.22))
            }
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? RytivoSunriseDesign.secondary : RytivoSunriseDesign.border,
                    lineWidth: kind == .primary && contrast != .increased ? 0 : 0.75
                )
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(scheme == .dark ? 0.09 : 0.65), .clear],
                    startPoint: .top, endPoint: .center
                ), lineWidth: 1)
            }
            // Shadow the surface only, rather than the live labels and values.
            .shadow(color: edgeColor, radius: 0, y: kind == .primary ? 5 : 3)
            .shadow(color: RepbasePalette.ink.opacity(scheme == .dark ? 0.40 : 0.11),
                    radius: kind == .card ? 22 : 8, y: kind == .card ? 9 : 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var edgeColor: Color {
        guard kind != .card else { return .clear }
        if scheme == .dark { return RepbasePalette.ink.opacity(0.8) }
        return (kind == .primary ? RepbaseTactileDesign.accentText : RepbasePalette.ink)
            .opacity(kind == .primary ? 0.40 : 0.14)
    }
}

struct MealLiftGloss: ShapeStyle {
    let opacity: Double

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        LinearGradient(stops: [
            .init(color: .white.opacity(opacity * 0.8), location: 0),
            .init(color: .white.opacity(opacity * 0.1), location: 0.46),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// A visual label: its parent owns the existing edit, portion, or dismiss action.
struct MealCompactActionLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var isDone = false

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.community(.caption, weight: .semibold))
            .foregroundStyle(isDone ? RytivoSunriseDesign.surface : RepbaseTactileDesign.accentText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: isDone ? 108 : 0, minHeight: 44)
            .background(MealLiftSurface(
                fill: isDone ? RytivoSunriseDesign.ink : HomeSunriseStyle.heroTint,
                kind: .control, radius: 100
            ))
    }
}

struct MealPlateIllustration: View {
    var body: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 27))
            .foregroundStyle(RepbaseTactileDesign.accentText)
            .frame(width: 56, height: 56)
            .background(MealLiftSurface(fill: RytivoSunriseDesign.surface, kind: .control, radius: 100))
            .frame(width: 72, height: 72)
            .background(MealLiftSurface(fill: HomeSunriseStyle.heroTint, kind: .primary))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(RepbasePalette.ink)
                    .frame(width: 24, height: 24)
                    .background(MealLiftSurface(fill: RepbaseTactileDesign.accent, kind: .control, radius: 100))
                    .offset(x: 3, y: -4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
