//
//  NutritionBreakdownView.swift
//  IOS Frontend
//
//  Visual breakdown of a day's logged nutrition: how calories split across
//  macros, which foods supply each macro, and how each meal contributes.
//

import SwiftUI

struct NutritionBreakdownView: View {
    /// Whether the breakdown covers a whole day or a single meal. A meal-scoped
    /// breakdown drops the per-meal comparison, which would only repeat itself.
    enum Scope {
        case day
        case meal
    }

    let meals: [FoodMeal]
    var scope: Scope = .day

    @State private var selectedMacro: Macro = .protein

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if entries.isEmpty {
                emptyCard
            } else {
                calorieSplitCard
                sourcesCard
                if scope == .day {
                    perMealCard
                }
            }

            micronutrientNote
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nutrition Breakdown")
                .font(.headline)
            Text(scope == .day
                 ? "See where this day's macros come from."
                 : "See where this meal's macros come from.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyCard: some View {
        Text("Log food to see how your macros break down.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foodCard()
    }

    // MARK: - Calorie split

    private var calorieSplitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calorie Split")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(macroCalories.rounded())) cal from macros")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            StackedMacroBar(shares: macroShares, height: 14)

            HStack(spacing: 8) {
                ForEach(Macro.allCases) { macro in
                    MacroLegendItem(
                        macro: macro,
                        grams: grams(of: macro, in: totals),
                        share: macroShares[macro] ?? 0
                    )
                }
            }
        }
        .foodCard()
    }

    // MARK: - Sources

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Where It's Coming From")
                .font(.subheadline.weight(.semibold))

            Picker("Macro", selection: $selectedMacro) {
                ForEach(Macro.allCases) { macro in
                    Text(macro.title).tag(macro)
                }
            }
            .pickerStyle(.segmented)

            let sources = sources(for: selectedMacro)
            if sources.isEmpty {
                Text("No \(selectedMacro.title.lowercased()) logged for this day yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 9) {
                    ForEach(sources) { source in
                        MacroSourceRow(source: source, color: selectedMacro.color)
                    }
                }
            }
        }
        .foodCard()
    }

    // MARK: - Per meal

    private var perMealCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("By Meal")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 10) {
                ForEach(mealsWithFood) { meal in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(meal.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text("\(meal.totalNutrition.calories.nutritionText) cal")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        StackedMacroBar(shares: shares(for: meal.totalNutrition), height: 7)

                        Text(macroSummary(for: meal.totalNutrition))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foodCard()
    }

    /// Micronutrients are not part of `NutritionAmount` and no food database is
    /// documented in the OAS, so vitamins are stated as unavailable rather than
    /// shown as an empty or invented chart.
    private var micronutrientNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "pills")
                .foregroundStyle(.secondary)
            Text("Vitamins and other micronutrients aren't tracked yet. They need a food database or extra label fields.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data

    private var entries: [FoodEntry] {
        meals.flatMap(\.entries)
    }

    private var mealsWithFood: [FoodMeal] {
        meals.filter { !$0.entries.isEmpty }
    }

    private var totals: NutritionAmount {
        entries.reduce(.zero) { $0 + $1.totalNutrition }
    }

    /// Calories represented by the logged macros. Derived (4/4/9) rather than
    /// taken from the calorie field so the split always sums to 100%.
    private var macroCalories: Double {
        Macro.allCases.reduce(0) { $0 + grams(of: $1, in: totals) * $1.caloriesPerGram }
    }

    private var macroShares: [Macro: Double] {
        shares(for: totals)
    }

    private func shares(for amount: NutritionAmount) -> [Macro: Double] {
        let total = Macro.allCases.reduce(0) {
            $0 + grams(of: $1, in: amount) * $1.caloriesPerGram
        }
        guard total > 0 else { return [:] }
        return Macro.allCases.reduce(into: [:]) { result, macro in
            result[macro] = grams(of: macro, in: amount) * macro.caloriesPerGram / total
        }
    }

    private func grams(of macro: Macro, in amount: NutritionAmount) -> Double {
        macro.grams(in: amount).nutritionDouble
    }

    private func macroSummary(for amount: NutritionAmount) -> String {
        Macro.allCases
            .map { "\($0.title) \(gramsText(grams(of: $0, in: amount)))g" }
            .joined(separator: " · ")
    }

    /// Foods supplying a macro on this day, largest first. Repeats of the same
    /// food are combined, and anything past the top few rolls into one row.
    private func sources(for macro: Macro) -> [MacroSource] {
        var combined: [String: (name: String, grams: Double)] = [:]

        for entry in entries {
            let value = grams(of: macro, in: entry.totalNutrition)
            guard value > 0 else { continue }
            let key = entry.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { continue }
            combined[key, default: (entry.name, 0)].grams += value
        }

        let total = combined.values.reduce(0) { $0 + $1.grams }
        guard total > 0 else { return [] }

        let ranked = combined
            .map {
                MacroSource(
                    id: $0.key,
                    name: $0.value.name,
                    grams: $0.value.grams,
                    share: $0.value.grams / total
                )
            }
            .sorted { $0.grams > $1.grams }

        let limit = 5
        guard ranked.count > limit else { return ranked }

        let remainder = ranked.dropFirst(limit).reduce(0) { $0 + $1.grams }
        return Array(ranked.prefix(limit)) + [
            MacroSource(
                id: "other",
                name: "Other foods",
                grams: remainder,
                share: remainder / total
            )
        ]
    }
}

// MARK: - Supporting types

enum Macro: String, CaseIterable, Identifiable {
    case protein
    case carbs
    case fat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        }
    }

    /// Matches the colors already used by the daily summary metrics.
    var color: Color {
        switch self {
        case .protein: return .orange
        case .carbs: return .teal
        case .fat: return .purple
        }
    }

    var caloriesPerGram: Double {
        switch self {
        case .protein, .carbs: return 4
        case .fat: return 9
        }
    }

    func grams(in amount: NutritionAmount) -> Decimal {
        switch self {
        case .protein: return amount.proteinGrams
        case .carbs: return amount.carbohydrateGrams
        case .fat: return amount.fatGrams
        }
    }
}

struct MacroSource: Identifiable {
    let id: String
    let name: String
    let grams: Double
    let share: Double
}

/// Whole grams read as "5g"; only a fractional amount keeps a decimal.
private func gramsText(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() {
        return String(Int(rounded))
    }
    return String(format: "%.1f", rounded)
}

private func percentText(_ share: Double) -> String {
    "\(Int((share * 100).rounded()))%"
}

/// One horizontal bar showing protein/carb/fat shares of calories.
private struct StackedMacroBar: View {
    let shares: [Macro: Double]
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Macro.allCases) { macro in
                    let share = shares[macro] ?? 0
                    if share > 0 {
                        Rectangle()
                            .fill(macro.color)
                            .frame(width: proxy.size.width * share)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

private struct MacroLegendItem: View {
    let macro: Macro
    let grams: Double
    let share: Double

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(macro.color)
                    .frame(width: 7, height: 7)
                Text(macro.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("\(gramsText(grams))g")
                .font(.caption.weight(.semibold))
            Text(percentText(share))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(macro.title) \(gramsText(grams)) grams, \(percentText(share)) of macro calories")
    }
}

private struct MacroSourceRow: View {
    let source: MacroSource
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(source.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(gramsText(source.grams))g")
                    .font(.caption.weight(.semibold))
                Text(percentText(source.share))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: max(proxy.size.width * source.share, 5))
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.name), \(gramsText(source.grams)) grams, \(percentText(source.share))")
    }
}

#Preview {
    let store = FoodTrackingStore.preview
    ScrollView {
        NutritionBreakdownView(meals: store.meals(on: Date()))
            .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
