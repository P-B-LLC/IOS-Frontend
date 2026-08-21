//
//  MealDetailView.swift
//  IOS Frontend
//
//  One meal's complete logging workspace.
//

import SwiftUI

struct MealDetailView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.workoutVisualPhase) private var phase
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let mealID: FoodMeal.ID

    @State private var isAddingFood = false
    @State private var isEnteringFood = false
    @State private var isShowingSavedMeals = false
    @State private var editingFood: FoodEntry?
    @State private var isRenamingMeal = false
    @State private var renamedMeal = ""

    var body: some View {
        Group {
            if let meal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mealSummary(meal)
                        if meal.entries.isEmpty {
                            emptyMealActions
                            mealGuidance
                        } else {
                            foodList(meal)
                        }
                        addFoodButton

                        // An empty meal already states that in the food list,
                        // so the breakdown only appears once there is food.
                        if !meal.entries.isEmpty {
                            NutritionBreakdownView(meals: [meal], scope: .meal)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    // Pushed inside the tab, so the bottom bar overlays it.
                    .padding(.bottom, RepbaseDesign.bottomBarClearance)
                }
                .repbaseScreen(phase)
                .navigationTitle(meal.name)
                .toolbar { mealToolbar(meal) }
            } else {
                ContentUnavailableView(
                    "Meal Not Found",
                    systemImage: "fork.knife",
                    description: Text("This meal may have been removed.")
                )
            }
        }
        .sheet(isPresented: $isAddingFood) {
            NavigationStack {
                FoodPickerView(date: date, mealID: mealID)
            }
        }
        .sheet(isPresented: $isEnteringFood) {
            NavigationStack {
                FoodEntryEditorView(date: date, mealID: mealID)
            }
        }
        .sheet(isPresented: $isShowingSavedMeals) {
            NavigationStack { SavedMealsView(referenceDate: date) }
        }
        .sheet(item: $editingFood) { food in
            NavigationStack {
                FoodEntryEditorView(date: date, mealID: mealID, existing: food)
            }
        }
        .alert("Rename Meal", isPresented: $isRenamingMeal) {
            TextField("Meal name", text: $renamedMeal)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                store.renameMeal(id: mealID, to: renamedMeal, on: date)
            }
        }
    }

    private func mealSummary(_ meal: FoodMeal) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(meal.name.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(phase.accent)
                Spacer()
                Text("\(meal.totalNutrition.calories.nutritionText) KCAL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RepbaseDesign.warning)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(RepbasePalette.oatmeal, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.entries.isEmpty ? "Build your plate." : "Your meal, at a glance.")
                    .font(.title2.weight(.bold))
                Text(meal.entries.isEmpty ? "Add one food and the mix comes to life." : "See what this meal is made of—not a daily target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                MacroMixRing(nutrition: meal.totalNutrition)
                    .frame(width: 128, height: 128)

                VStack(spacing: 9) {
                    ForEach(Macro.allCases) { macro in
                        MealMacro(
                            title: macro.title,
                            value: macro.grams(in: meal.totalNutrition),
                            share: meal.totalNutrition.energyShare(for: macro),
                            color: macro.color
                        )
                    }
                }
            }

            MacroMixRibbon(nutrition: meal.totalNutrition)
        }
        .foodCard()
    }

    private var emptyMealActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BUILD YOUR MEAL")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(phase.accent)
            Text("Choose where to start")
                .font(.title2.weight(.bold))
            Text("Add something new or reuse what already works.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                mealAction("Search foods", detail: "Find food from your history or database", symbol: "magnifyingglass") { isAddingFood = true }
                Divider().padding(.leading, 52)
                mealAction("Enter manually", detail: "Add calories and macros yourself", symbol: "square.and.pencil") { isEnteringFood = true }
                Divider().padding(.leading, 52)
                mealAction("Use a saved meal", detail: "Apply a meal you have already built", symbol: "bookmark.fill") { isShowingSavedMeals = true }
            }
            .foodCard()
        }
    }

    private func mealAction(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(phase.accent)
                    .frame(width: 36, height: 36)
                    .background(phase.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var mealGuidance: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Macros update as you add foods").font(.subheadline.weight(.semibold))
                Text("Review the totals before leaving this meal.").font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "chart.bar.fill")
        }
        .foregroundStyle(RepbaseDesign.success)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RepbaseDesign.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    private func foodList(_ meal: FoodMeal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Foods")
                .font(.title3.weight(.bold))

            if meal.entries.isEmpty {
                ContentUnavailableView(
                    "No Food Logged",
                    systemImage: "takeoutbag.and.cup.and.straw",
                    description: Text("Add nutrition manually to start this meal.")
                )
                .frame(maxWidth: .infinity)
                .foodCard()
            } else {
                ForEach(meal.entries) { food in
                    Button {
                        editingFood = food
                    } label: {
                        FoodEntryRow(food: food)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.removeFood(id: food.id, from: mealID, on: date)
                        }
                    }
                }
            }
        }
    }

    private var addFoodButton: some View {
        Button {
            isAddingFood = true
        } label: {
            Label("Add food", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(RepbasePrimaryButtonStyle())
    }

    @ToolbarContentBuilder
    private func mealToolbar(_ meal: FoodMeal) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // Sharing is not here. It lives on the food page, which lists
                // every meal and can therefore ask which one to post.
                Button("Rename Meal", systemImage: "pencil") {
                    renamedMeal = meal.name
                    isRenamingMeal = true
                }
                Button("Remove Meal", systemImage: "trash", role: .destructive) {
                    store.removeMeal(id: mealID, on: date)
                    dismiss()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var meal: FoodMeal? {
        store.meals(on: date).first { $0.id == mealID }
    }

}

private struct MealMacro: View {
    let title: String
    let value: Decimal
    let share: Double
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(value.nutritionText)g").font(.subheadline.weight(.bold))
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MacroMixRing: View {
    let nutrition: NutritionAmount

    var body: some View {
        ZStack {
            Circle().stroke(RepbasePalette.oatmeal, lineWidth: 14)
            ForEach(Macro.allCases) { macro in
                Circle()
                    .trim(from: 0, to: max(0, nutrition.energyShare(for: macro) - 0.018))
                    .stroke(macro.color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90 + nutrition.startAngle(for: macro)))
            }
            VStack(spacing: 2) {
                Text("Meal mix").font(.subheadline.weight(.bold))
                Text("BY ENERGY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Meal macro energy composition")
    }
}

private struct MacroMixRibbon: View {
    let nutrition: NutritionAmount

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - 6)
            HStack(spacing: 3) {
                ForEach(Macro.allCases) { macro in
                    Capsule()
                        .fill(macro.color.opacity(0.78))
                        .frame(width: max(3, availableWidth * nutrition.energyShare(for: macro)))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private extension NutritionAmount {
    func energyShare(for macro: Macro) -> Double {
        let total = macroEnergyTotal
        guard total > 0 else { return 0 }
        return energy(for: macro) / total
    }

    func startAngle(for macro: Macro) -> Double {
        switch macro {
        case .protein: 0
        case .carbs: energyShare(for: .protein) * 360
        case .fat: (energyShare(for: .protein) + energyShare(for: .carbs)) * 360
        }
    }

    private var macroEnergyTotal: Double {
        Macro.allCases.reduce(0) { $0 + energy(for: $1) }
    }

    private func energy(for macro: Macro) -> Double {
        NSDecimalNumber(decimal: macro.grams(in: self)).doubleValue * macro.caloriesPerGram
    }
}

private struct FoodEntryRow: View {
    let food: FoodEntry

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "carrot.fill")
                .foregroundStyle(Color.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(food.servings.nutritionText) serving\(food.servings == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(food.totalNutrition.calories.nutritionText) cal")
                    .font(.subheadline.weight(.semibold))
                Text("P \(food.totalNutrition.proteinGrams.nutritionText) · C \(food.totalNutrition.carbohydrateGrams.nutritionText) · F \(food.totalNutrition.fatGrams.nutritionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foodCard()
    }
}

#Preview {
    let store = FoodTrackingStore.preview
    let meal = store.meals(on: Date())[0]
    NavigationStack {
        MealDetailView(date: Date(), mealID: meal.id)
    }
    .environment(store)
}
