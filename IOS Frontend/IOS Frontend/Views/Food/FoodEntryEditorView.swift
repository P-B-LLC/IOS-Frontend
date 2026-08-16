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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    EditorialFormHeader(
                        title: name.isEmpty ? "Add Food" : name,
                        leadingAction: .back,
                        saveTitle: "Save",
                        canSave: isValid,
                        onDismiss: { dismiss() },
                        onSave: save
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("FOOD / MANUAL ENTRY")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text(isEditing ? "Update this food." : "Log what you ate.")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                        Text("Enter the values shown on the label for one serving.")
                            .font(.subheadline)
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        EditorialSectionTitle(title: "Food")
                        EditorialRuleGroup {
                            EditorialRuleRow {
                                TextField("Food name", text: $name)
                                    .font(.title3)
                                    .textContentType(.name)
                            }
                            EditorialRuleRow(showsDivider: false) {
                                Text("Servings").font(.subheadline)
                                Spacer()
                                editorialNumberField($servings, placeholder: "1", unit: nil)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        EditorialSectionTitle(title: "Nutrition per serving")
                        EditorialRuleGroup {
                            editorialNutritionRow("Calories", unit: "cal", text: $calories)
                            editorialNutritionRow("Protein", unit: "g", text: $protein)
                            editorialNutritionRow("Carbohydrates", unit: "g", text: $carbohydrates)
                            editorialNutritionRow("Fat", unit: "g", text: $fat, showsDivider: false)
                        }
                    }

                    Button(isEditing ? "Save changes" : "Add food") { save() }
                        .buttonStyle(EditorialPrimaryButtonStyle())
                        .disabled(!isValid)

                    if isEditing {
                        Button(role: .destructive) {
                            store.removeFood(id: existingID, from: mealID, on: date)
                            dismiss()
                        } label: {
                            Label("Delete Food", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
    }

    private func editorialNutritionRow(
        _ title: String,
        unit: String,
        text: Binding<String>,
        showsDivider: Bool = true
    ) -> some View {
        EditorialRuleRow(showsDivider: showsDivider) {
            Text(title).font(.subheadline)
            Spacer()
            editorialNumberField(text, placeholder: "0", unit: unit)
        }
    }

    private func editorialNumberField(
        _ text: Binding<String>,
        placeholder: String,
        unit: String?
    ) -> some View {
        HStack(spacing: 5) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            if let unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
        }
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
