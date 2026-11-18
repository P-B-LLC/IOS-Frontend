import SwiftUI

/// The approved compact summary. The Figma SVG arcs are examples of this
/// dynamic chart, not static illustrations to reuse for unrelated foods.
struct FoodPortionMacroSummary: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let nutrition: NutritionAmount

    var body: some View {
        let mix = PortionMacroMix(nutrition)
        VStack(alignment: .leading, spacing: 10) {
            Text("For your portion")
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(RytivoSunriseDesign.secondary)
            summary(mix)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RytivoSunriseDesign.surface,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(contrast == .increased ? RytivoSunriseDesign.secondary
                                      : RytivoSunriseDesign.border, lineWidth: 0.75)
                }
            Text("Energy split between carbs, fat and protein.")
                .font(.community(.caption2, weight: .semibold))
                .foregroundStyle(RytivoSunriseDesign.secondary)
        }
    }

    @ViewBuilder
    private func summary(_ mix: PortionMacroMix) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(nutrition.calories.nutritionText) kcal")
                    .font(.community(.title2, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                legend(mix, vertically: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    calorieRing(mix)
                    legend(mix).frame(minWidth: 180)
                }
                VStack(spacing: 16) {
                    calorieRing(mix)
                    legend(mix)
                }
            }
        }
    }

    private func calorieRing(_ mix: PortionMacroMix) -> some View {
        ZStack {
            Circle().strokeBorder(RytivoSunriseDesign.border, lineWidth: 7)
            ForEach(0..<3, id: \.self) { index in
                let share = mix.shares[index]
                if share > 0 {
                    let gap = share == 1 ? 0 : min(0.002, share / 4)
                    Circle()
                        .trim(from: CGFloat(mix.start(at: index) + gap),
                              to: CGFloat(min(1, mix.start(at: index) + share - gap)))
                        .stroke(PortionMacroAppearance.color(at: index), lineWidth: 7)
                        .rotationEffect(.degrees(-90))
                        .padding(3.5)
                }
            }
            VStack(spacing: 0) {
                Text(nutrition.calories.nutritionText)
                    .font(.community(size: 24, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text("kcal")
                    .font(.community(.caption2, weight: .bold))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            .padding(10)
        }
        .frame(width: typeSize.isAccessibilitySize ? 120 : 96,
               height: typeSize.isAccessibilitySize ? 120 : 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(nutrition.calories.nutritionText) kcal"))
    }

    private func legend(_ mix: PortionMacroMix, vertically: Bool = false) -> some View {
        let layout = vertically
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            ForEach(Array(PortionMacroAppearance.order.enumerated()), id: \.element) { index, macro in
                macroValue(macro, index: index, mix: mix)
            }
        }
    }

    private func macroValue(_ macro: Macro, index: Int, mix: PortionMacroMix) -> some View {
        let grams = macro.grams(in: nutrition).nutritionText
        let percent = mix.displayedShares[index]
            .formatted(.percent.locale(.app).precision(.fractionLength(0...1)))
        return VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: mix.hasEnergy ? percent : "—")
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(PortionMacroAppearance.percentageColor(at: index))
            Text("\(grams)g")
                .font(.community(size: 20, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(macro.title)
                .font(.community(.caption))
                .foregroundStyle(RytivoSunriseDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(macro.title))
        .accessibilityValue(mix.hasEnergy
                            ? Text("\(grams) grams, \(percent) of macro calories")
                            : Text("\(grams) g"))
    }
}

/// Scoped to the reviewed ring; other food charts retain their existing palette.
private enum PortionMacroAppearance {
    static let order: [Macro] = [.carbs, .fat, .protein]

    static func color(at index: Int) -> Color {
        switch index {
        case 0: Color(hex: 0x188D8B)
        case 1: Color(hex: 0x8B58B4)
        default: Color(hex: 0xD96930)
        }
    }

    static func percentageColor(at index: Int) -> Color {
        switch index {
        case 0: Color.repbaseDynamic(light: Color(hex: 0x1C7371), dark: Color(hex: 0x5DADAA))
        case 1: Color.repbaseDynamic(light: Color(hex: 0x724B8F), dark: Color(hex: 0xAE88C7))
        default: Color.repbaseDynamic(light: Color(hex: 0xAD582C), dark: Color(hex: 0xE4946A))
        }
    }
}
