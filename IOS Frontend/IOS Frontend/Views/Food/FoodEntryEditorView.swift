//
//  FoodEntryEditorView.swift
//  IOS Frontend
//
//  Manual nutrition entry until food search is represented by the OAS.
//

import SwiftUI

struct FoodEntryEditorView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase

    let date: Date
    let mealID: FoodMeal.ID
    private let existingID: FoodEntry.ID
    private let isEditing: Bool
    /// Called instead of `dismiss()` after a successful save. Lets a presenting
    /// picker close its whole sheet rather than only popping this screen.
    private let onSaved: (() -> Void)?

    @State private var name: String
    @State private var servings: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbohydrates: String
    @State private var fat: String

    init(
        date: Date,
        mealID: FoodMeal.ID,
        existing: FoodEntry? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.date = date
        self.mealID = mealID
        self.onSaved = onSaved
        existingID = existing?.id ?? UUID()
        isEditing = existing != nil
        _name = State(initialValue: existing?.name ?? "")
        _servings = State(initialValue: existing?.servings.nutritionText ?? "1")
        _calories = State(initialValue: existing?.nutritionPerServing.calories.nutritionText ?? "")
        _protein = State(initialValue: existing?.nutritionPerServing.proteinGrams.nutritionText ?? "")
        _carbohydrates = State(initialValue: existing?.nutritionPerServing.carbohydrateGrams.nutritionText ?? "")
        _fat = State(initialValue: existing?.nutritionPerServing.fatGrams.nutritionText ?? "")
    }

    var body: some View {
        Form {
            Section("Food") {
                TextField("Food name", text: $name)
                    .textContentType(.name)
                HStack {
                    Text("Servings")
                    Spacer()
                    TextField("1", text: $servings)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
            }

            Section {
                FoodNutritionField(title: "Calories", unit: "cal", text: $calories)
                FoodNutritionField(title: "Protein", unit: "g", text: $protein)
                FoodNutritionField(title: "Carbohydrates", unit: "g", text: $carbohydrates)
                FoodNutritionField(title: "Fat", unit: "g", text: $fat)
            } header: {
                Text("Nutrition per serving")
            } footer: {
                Text("Enter the values shown on the food label for one serving.")
            }

            if isEditing {
                Section {
                    Button("Delete Food", systemImage: "trash", role: .destructive) {
                        store.removeFood(id: existingID, from: mealID, on: date)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(name.isEmpty ? "Add Food" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
        .repbaseScreen(phase)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && positiveDecimal(servings) != nil
            && nonnegativeDecimal(calories) != nil
            && nonnegativeDecimal(protein) != nil
            && nonnegativeDecimal(carbohydrates) != nil
            && nonnegativeDecimal(fat) != nil
    }

    private func save() {
        guard let servings = positiveDecimal(servings),
              let calories = nonnegativeDecimal(calories),
              let protein = nonnegativeDecimal(protein),
              let carbohydrates = nonnegativeDecimal(carbohydrates),
              let fat = nonnegativeDecimal(fat) else {
            return
        }

        store.saveFood(
            FoodEntry(
                id: existingID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                servings: servings,
                nutritionPerServing: NutritionAmount(
                    calories: calories,
                    proteinGrams: protein,
                    carbohydrateGrams: carbohydrates,
                    fatGrams: fat
                )
            ),
            in: mealID,
            on: date
        )
        if let onSaved {
            onSaved()
        } else {
            dismiss()
        }
    }

    private func positiveDecimal(_ value: String) -> Decimal? {
        guard let value = decimal(value), value > 0 else { return nil }
        return value
    }

    private func nonnegativeDecimal(_ value: String) -> Decimal? {
        guard let value = decimal(value), value >= 0 else { return nil }
        return value
    }

    private func decimal(_ value: String) -> Decimal? {
        Decimal(string: value.trimmingCharacters(in: .whitespacesAndNewlines), locale: .current)
    }
}

struct FoodNutritionField: View {
    let title: String
    let unit: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 25, alignment: .leading)
        }
    }
}
