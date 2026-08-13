//
//  MealDetailView.swift
//  IOS Frontend
//
//  One meal's complete logging workspace.
//

import SwiftUI

struct MealDetailView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let mealID: FoodMeal.ID

    @State private var isAddingFood = false
    @State private var editingFood: FoodEntry?
    @State private var isRenamingMeal = false
    @State private var renamedMeal = ""
    @State private var confirmsMealRemoval = false

    var body: some View {
        Group {
            if let meal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        mealSummary(meal)
                        foodList(meal)
                        addFoodButton
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
        .confirmationDialog(
            "Remove this meal and all of its foods?",
            isPresented: $confirmsMealRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Meal", role: .destructive) {
                store.removeMeal(id: mealID, on: date)
                dismiss()
            }
        }
    }

    private func mealSummary(_ meal: FoodMeal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    // Food counts the moment it is added, so a meal holding any
                    // food is logged. There is no separate confirmation step.
                    Text(meal.entries.isEmpty ? "No food yet" : "Meal logged")
                        .font(.headline)
                    Text("\(meal.entries.count) food\(meal.entries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(meal.totalNutrition.calories.nutritionText) cal")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.orange)
            }

            HStack(spacing: 8) {
                MealMacro(title: "Protein", value: meal.totalNutrition.proteinGrams, color: .blue)
                MealMacro(title: "Carbs", value: meal.totalNutrition.carbohydrateGrams, color: .green)
                MealMacro(title: "Fat", value: meal.totalNutrition.fatGrams, color: .purple)
            }
        }
        .foodCard()
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
            Label("Add Food", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Color.orange)
    }

    @ToolbarContentBuilder
    private func mealToolbar(_ meal: FoodMeal) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Rename Meal", systemImage: "pencil") {
                    renamedMeal = meal.name
                    isRenamingMeal = true
                }
                Button("Remove Meal", systemImage: "trash", role: .destructive) {
                    confirmsMealRemoval = true
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
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value.nutritionText)g")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
