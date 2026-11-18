import SwiftUI

/// A visible entry point to the existing selected-day meal planner.
struct FoodMealPlannerCard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .subheadline) private var calendarSize: CGFloat = 18
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Meal planner")
                    .font(.community(size: 18, weight: .bold))
                    .foregroundStyle(RytivoSunriseDesign.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a day, add recipes, and preview your macros.")
                    .font(.community(.footnote, weight: .semibold))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onPlan) {
                HStack(spacing: 8) {
                    Text("Plan meals")
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "calendar")
                        .font(.system(size: calendarSize))
                        .accessibilityHidden(true)
                }
                .font(.community(.subheadline))
                .foregroundStyle(Color.repbaseDynamic(light: .white, dark: RepbasePalette.ink))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    Capsule().fill(RytivoSunriseDesign.ink)
                        .shadow(color: RepbasePalette.ink.opacity(scheme == .dark ? 0.14 : 0.05),
                                radius: 2, y: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(RepbaseTactilePressStyle())
            .accessibilityHint("Choose a day, add recipes, and preview your macros.")
            .accessibilityIdentifier("food.meal-planner")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: RepbaseTactileDesign.cardRadius, style: .continuous)
                .fill(RepbaseTactileDesign.cardTint)
                .overlay {
                    RoundedRectangle(cornerRadius: RepbaseTactileDesign.cardRadius, style: .continuous)
                        .strokeBorder(contrast == .increased ? RytivoSunriseDesign.secondary
                                      : RytivoSunriseDesign.border, lineWidth: 0.75)
                }
                .shadow(color: RepbasePalette.ink.opacity(scheme == .dark ? 0.14 : 0.05),
                        radius: 5, y: 3)
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
/// Exercises the real card without an account, network, or save operation.
struct FoodMealPlannerCardPreview: View {
    let scenario: String

    var body: some View {
        ScrollView {
            FoodMealPlannerCard(onPlan: {})
                .padding(RepbaseDesign.pageInset)
        }
        .background(RytivoSunriseDesign.surface.ignoresSafeArea())
        .dynamicTypeSize(scenario == "meal-planner-accessibility" ? .accessibility3 : .large)
    }
}
#endif
