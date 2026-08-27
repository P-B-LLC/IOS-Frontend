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
                .font(.community(.headline))
            Text(scope == .day
                 ? "See where this day's macros come from."
                 : "See where this meal's macros come from.")
                .font(.community(.caption2))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyCard: some View {
        Text("Log food to see how your macros break down.")
            .font(.community(.caption))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Calorie split

    private var calorieSplitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calorie Split")
                    .font(.community(.subheadline, weight: .semibold))
                Spacer()
                Text("\(Int(macroCalories.rounded())) cal from macros")
                    .font(.community(.caption2))
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
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Sources

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Where It's Coming From")
                .font(.community(.subheadline, weight: .semibold))

            Picker("Macro", selection: $selectedMacro) {
                ForEach(Macro.allCases) { macro in
                    Text(macro.title).tag(macro)
                }
            }
            .pickerStyle(.segmented)

            let sources = sources(for: selectedMacro)
            if sources.isEmpty {
                Text("No \(selectedMacro.title.lowercased()) logged for this day yet.")
                    .font(.community(.caption))
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
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Per meal

    private var perMealCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("By Meal")
                .font(.community(.subheadline, weight: .semibold))

            VStack(spacing: 10) {
                ForEach(mealsWithFood) { meal in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(meal.name)
                                .font(.community(.caption, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text("\(meal.totalNutrition.calories.nutritionText) cal")
                                .font(.community(.caption2, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        StackedMacroBar(shares: shares(for: meal.totalNutrition), height: 7)

                        Text(macroSummary(for: meal.totalNutrition))
                            .font(.community(.caption2))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
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
        .font(.community(.caption2))
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

    /// Foods that are a real source of a macro, largest first.
    ///
    /// A food only earns a place in a macro's list when that macro is what the
    /// food mostly is, or when it supplies a meaningful slice of the food's own
    /// calories. That keeps a mixed food like Greek yogurt out of the fat list
    /// for a few trailing grams while still crediting it as protein and carbs.
    /// Everything filtered out, plus anything past the top few, is still
    /// counted in a trailing "Other foods" row so the percentages reconcile.
    private func sources(for macro: Macro) -> [MacroSource] {
        var combined: [String: (name: String, amount: NutritionAmount)] = [:]

        for entry in entries {
            let key = entry.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { continue }

            if let existing = combined[key] {
                combined[key] = (
                    existing.name,
                    existing.amount + entry.totalNutrition
                )
            } else {
                combined[key] = (entry.name, entry.totalNutrition)
            }
        }

        let foods = combined.compactMap { key, value -> MacroSource? in
            let macroGrams = grams(of: macro, in: value.amount)
            guard macroGrams > 0 else { return nil }
            let primary = primaryMacro(of: value.amount)
            return MacroSource(
                id: key,
                name: value.name,
                grams: macroGrams,
                share: 0,
                primary: primary,
                isMeaningful: primary == macro
                    || share(of: macro, within: value.amount) >= Self.sourceThreshold
            )
        }

        let total = foods.reduce(0) { $0 + $1.grams }
        guard total > 0 else { return [] }

        var listed = foods
            .filter(\.isMeaningful)
            .sorted { $0.grams > $1.grams }

        // Every food supplies only a trace of this macro. Naming them beats a
        // lone anonymous "Other foods" row that accounts for everything.
        if listed.isEmpty {
            listed = foods.sorted { $0.grams > $1.grams }
        }

        let limit = 5
        let shown = Array(listed.prefix(limit))

        let remainder = total - shown.reduce(0) { $0 + $1.grams }
        var result = shown.map { $0.withShare($0.grams / total) }

        if remainder > 0.05 {
            result.append(
                MacroSource(
                    id: "other",
                    name: "Other foods",
                    grams: remainder,
                    share: remainder / total,
                    primary: nil,
                    isMeaningful: true
                )
            )
        }

        return result
    }

    /// Share of a food's own macro calories supplied by one macro.
    private func share(of macro: Macro, within amount: NutritionAmount) -> Double {
        let total = Macro.allCases.reduce(0) {
            $0 + grams(of: $1, in: amount) * $1.caloriesPerGram
        }
        guard total > 0 else { return 0 }
        return grams(of: macro, in: amount) * macro.caloriesPerGram / total
    }

    /// What a food mostly is, by whichever macro supplies most of its calories.
    private func primaryMacro(of amount: NutritionAmount) -> Macro? {
        let ranked = Macro.allCases
            .map { ($0, grams(of: $0, in: amount) * $0.caloriesPerGram) }
            .filter { $0.1 > 0 }
        guard !ranked.isEmpty else { return nil }
        return ranked.max { $0.1 < $1.1 }?.0
    }

    /// A macro must supply at least this much of a food's own calories before
    /// that food is listed as a source of it.
    private static let sourceThreshold = 0.25
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
        case .protein: return Color(hex: 0xD9824B)
        case .carbs: return Color(hex: 0x4AAFB3)
        case .fat: return Color(hex: 0xB76AA5)
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
    /// Share of the day's (or meal's) total for the macro being listed.
    let share: Double
    /// The macro this food mostly is, used as its category tag.
    let primary: Macro?
    /// Whether the food is a real source of the macro being listed.
    let isMeaningful: Bool

    func withShare(_ share: Double) -> MacroSource {
        MacroSource(
            id: id,
            name: name,
            grams: grams,
            share: share,
            primary: primary,
            isMeaningful: isMeaningful
        )
    }
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
                    .font(.community(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("\(gramsText(grams))g")
                .font(.community(.caption, weight: .semibold))
            Text(percentText(share))
                .font(.community(.caption2))
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
            HStack(spacing: 6) {
                Text(source.name)
                    .font(.community(.caption, weight: .medium))
                    .lineLimit(1)

                // What the food mostly is, so "chicken" reads as a protein and
                // "rice" as a carb regardless of which list it appears in.
                if let primary = source.primary {
                    Text(primary.title)
                        .font(.community(size: 9, weight: .semibold))
                        .foregroundStyle(primary.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(primary.color.opacity(0.14), in: Capsule())
                        .layoutPriority(1)
                }

                Spacer(minLength: 0)
                Text("\(gramsText(source.grams))g")
                    .font(.community(.caption, weight: .semibold))
                Text(percentText(source.share))
                    .font(.community(.caption2))
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
    .repbaseScreen(.prepare)
}
