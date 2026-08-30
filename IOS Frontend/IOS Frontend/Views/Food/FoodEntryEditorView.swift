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
                        onSave: save,
                        showsSaveAction: false
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("FOOD / MANUAL ENTRY")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text(isEditing ? "Update this food." : "Log what you ate.")
                            .font(.community(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                        Text("Enter the values shown on the label for one serving.")
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        EditorialSectionTitle(title: "Food")
                        TextField("Food name", text: $name)
                            .font(.community(.title2, weight: .semibold))
                            .textContentType(.name)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Divider() }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Servings")
                                .font(.community(.subheadline, weight: .medium))
                            Spacer()
                            TextField("1", text: $servings)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.community(.title3, weight: .semibold))
                                .frame(width: 80)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Divider() }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        EditorialSectionTitle(title: "Nutrition per serving")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CALORIES")
                                .font(.community(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(timeOfDay.canvasSecondaryText)
                            HStack(alignment: .firstTextBaseline) {
                                TextField("0", text: $calories)
                                    .keyboardType(.decimalPad)
                                    .font(.community(size: 38, weight: .bold, design: .rounded))
                                Spacer()
                                Text("kcal")
                                    .font(.community(.subheadline, weight: .medium))
                                    .foregroundStyle(timeOfDay.accent)
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Divider() }

                        HStack(alignment: .top, spacing: 18) {
                            macroField("PROTEIN", text: $protein, tint: Color(hex: 0xD9824B))
                            macroField("CARBS", text: $carbohydrates, tint: Color(hex: 0x4AAFB3))
                            macroField("FAT", text: $fat, tint: Color(hex: 0xB76AA5))
                        }
                        .padding(.top, 8)
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
                                .font(.community(.subheadline, weight: .semibold))
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

    private func macroField(
        _ title: String,
        text: Binding<String>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.community(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("0", text: text)
                    .font(.community(.title2, weight: .semibold))
                    .keyboardType(.decimalPad)
                Text("g")
                    .font(.community(.caption))
                    .foregroundStyle(.secondary)
            }
            Capsule()
                .fill(tint)
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            on: date,
            celebrates: !isEditing
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
                .font(.community(.caption))
                .foregroundStyle(.secondary)
                .frame(width: 25, alignment: .leading)
        }
    }
}
