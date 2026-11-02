import SwiftUI

/// A small entry point, not ten more widgets on the food dashboard.
struct FoodDailyNutrientsCard: View {
    let entries: [FoodEntry]
    let date: Date
    @Environment(\.dynamicTypeSize) private var textSize

    private var highlights: [FoodNutrientDefinition] {
        let keys = ["fiber_g", "calcium_mg", "iron_mg", "sodium_mg"]
        return keys.compactMap { key in FoodNutrientDefinition.all.first { $0.id == key } }
    }

    var body: some View {
        NavigationLink { FoodNutrientsDetailView(date: date) } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "leaf").font(.community(.title3))
                        .foregroundStyle(RytivoSunriseDesign.sage)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily nutrients").font(.community(.headline))
                        Text("Vitamins, minerals & more").font(.community(.caption))
                            .foregroundStyle(RytivoSunriseDesign.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.community(.caption, weight: .semibold))
                }
                if entries.isEmpty {
                    Text("Log a food with nutrition details to see your daily progress.")
                        .font(.community(.subheadline)).foregroundStyle(RytivoSunriseDesign.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                             count: textSize.isAccessibilitySize ? 1 : 2),
                              alignment: .leading, spacing: 16) {
                        ForEach(highlights) { definition in
                            FoodNutrientProgressRow(progress: DailyNutrientProgress(entries: entries, definition: definition),
                                                    compact: true, showsCoverage: true)
                        }
                    }
                }
                Text("Known intake from logged foods").font(.community(.caption2))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            .foregroundStyle(RytivoSunriseDesign.ink)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .sunriseCard(tint: RytivoSunriseDesign.sageTint)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
        .accessibilityHint("View daily nutrient amounts and data coverage")
    }
}

struct FoodNutrientsDetailView: View {
    let date: Date
    @Environment(FoodTrackingStore.self) private var store
    private var entries: [FoodEntry] { store.meals(on: date).flatMap(\.entries) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(.app)))
                    .font(.community(.subheadline)).foregroundStyle(.secondary)
                Text("Known intake").font(.community(.largeTitle, weight: .bold))
                Text("Missing nutrient data is not counted as zero. Percentages reflect known intake.")
                    .font(.community(.subheadline)).foregroundStyle(.secondary)
                FoodNutrientsList(entries: entries)
                FoodDailyValueFootnote()
            }
            .padding(RepbaseDesign.pageInset)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .navigationTitle("Daily nutrients").navigationBarTitleDisplayMode(.inline)
        .background(HomeSunriseStyle.backdropGradient.ignoresSafeArea())
        .task { store.ensureDay(date) }
    }
}

/// Shared by the selected day's totals and a selected product's actual portion.
/// No server request per row; all amounts come from the saved food snapshot.
struct FoodNutrientsList: View {
    let entries: [FoodEntry]
    var showsCoverage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            group(.target, title: "Reference targets")
            group(.limit, title: "Daily limits")
            group(.amount, title: "Other nutrients")
        }
    }

    private func group(_ direction: FoodNutrientDefinition.Direction, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.community(.headline)).accessibilityAddTraits(.isHeader)
            ForEach(FoodNutrientDefinition.all.filter { $0.direction == direction }) { definition in
                FoodNutrientProgressRow(progress: DailyNutrientProgress(entries: entries, definition: definition),
                                        compact: false, showsCoverage: showsCoverage)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .sunriseCard(tint: direction == .limit ? HomeSunriseStyle.heroTint : RytivoSunriseDesign.sageTint,
                     radius: 20)
    }
}

private struct FoodNutrientProgressRow: View {
    let progress: DailyNutrientProgress
    let compact: Bool
    let showsCoverage: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var definition: FoodNutrientDefinition { progress.definition }
    private var tint: Color {
        if definition.direction == .limit {
            return (progress.ratio ?? 0) > 1 ? RepbaseTactileDesign.accentText : RytivoSunriseDesign.secondary
        }
        return RytivoSunriseDesign.sage
    }
    private var barValue: Double { min(1, max(0, (progress.ratio ?? 0).nutritionDouble)) }
    private func number(_ value: Decimal) -> String {
        value.formatted(.number.locale(.app).precision(.fractionLength(0...2)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(definition.title).font(.community(compact ? .caption : .subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !compact, let ratio = progress.ratio {
                    Text("\(ratio.nutritionDouble.formatted(.percent.locale(.app).precision(.fractionLength(0...1)))) DV")
                        .font(.community(.caption, weight: .semibold)).foregroundStyle(tint)
                }
            }
            if let amount = progress.knownAmount {
                if compact, let reference = definition.dailyValue {
                Text(verbatim: "\(number(amount)) / \(number(reference)) \(definition.unit)")
                    .font(.community(.subheadline, weight: .semibold)).monospacedDigit()
                } else {
                Text(verbatim: "\(number(amount)) \(definition.unit)")
                    .font(.community(compact ? .subheadline : .body, weight: .semibold)).monospacedDigit()
                }
                if progress.ratio != nil {
                    ProgressView(value: barValue).tint(tint).accessibilityHidden(true)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress.ratio)
                }
            } else {
                Text("Not available").font(.community(.caption)).foregroundStyle(.secondary)
            }
            if let reference = definition.dailyValue {
                if definition.direction == .limit {
                    Text("Limit: \(number(reference)) \(definition.unit)")
                        .font(.community(.caption2)).foregroundStyle(.secondary)
                } else if !compact {
                    Text("Reference: \(number(reference)) \(definition.unit)")
                        .font(.community(.caption2)).foregroundStyle(.secondary)
                }
            } else if !compact {
                Text("No Daily Value established").font(.community(.caption2)).foregroundStyle(.secondary)
            }
            if showsCoverage && progress.totalFoodCount > 0 && !progress.isComplete {
                Text("Food data coverage: \(progress.knownFoodCount) / \(progress.totalFoodCount)")
                    .font(.community(.caption2)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(RytivoSunriseDesign.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct FoodDailyValueFootnote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Values are nutrition-label references for adults and children aged 4 and older, not personal medical targets.")
                .font(.community(.caption)).foregroundStyle(.secondary)
            Link("About Daily Values", destination: URL(string: "https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels")!)
                .font(.community(.caption, weight: .semibold))
        }
    }
}
