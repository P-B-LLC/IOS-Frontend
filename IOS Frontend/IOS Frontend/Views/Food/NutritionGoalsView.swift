//
//  NutritionGoalsView.swift
//  IOS Frontend
//
//  Customizable daily calorie and macronutrient targets.
//

import SwiftUI

struct NutritionGoalsView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var calories = ""
    @State private var protein = ""
    @State private var carbohydrates = ""
    @State private var fat = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            goalsScreen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
        .onAppear {
            calories = store.goals.calories.nutritionText
            protein = store.goals.proteinGrams.nutritionText
            carbohydrates = store.goals.carbohydrateGrams.nutritionText
            fat = store.goals.fatGrams.nutritionText
        }
    }

    private func goalsScreen(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    EditorialFormHeader(
                        title: "Nutrition Goals",
                        leadingAction: .cancel,
                        saveTitle: "Save",
                        canSave: isValid,
                        onDismiss: { dismiss() },
                        onSave: save
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DAILY TARGETS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text("Set your baseline.")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                        Text("These values power progress across Home and Food.")
                            .font(.subheadline)
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    EditorialRuleGroup {
                        goalRow("Calories", unit: "cal", text: $calories)
                        goalRow("Protein", unit: "g", text: $protein)
                        goalRow("Carbohydrates", unit: "g", text: $carbohydrates)
                        goalRow("Fat", unit: "g", text: $fat, showsDivider: false)
                    }

                    Button("Save goals") { save() }
                        .buttonStyle(EditorialPrimaryButtonStyle())
                        .disabled(!isValid)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
    }

    private func goalRow(
        _ title: String,
        unit: String,
        text: Binding<String>,
        showsDivider: Bool = true
    ) -> some View {
        EditorialRuleRow(showsDivider: showsDivider) {
            Text(title).font(.subheadline)
            Spacer()
            HStack(spacing: 6) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.weight(.semibold))
                    .frame(width: 92)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
        }
    }

    private var isValid: Bool {
        positive(calories) != nil
            && positive(protein) != nil
            && positive(carbohydrates) != nil
            && positive(fat) != nil
    }

    private func save() {
        guard let calories = positive(calories),
              let protein = positive(protein),
              let carbohydrates = positive(carbohydrates),
              let fat = positive(fat) else {
            return
        }
        store.updateGoals(
            NutritionGoals(
                calories: calories,
                proteinGrams: protein,
                carbohydrateGrams: carbohydrates,
                fatGrams: fat
            )
        )
        dismiss()
    }

    private func positive(_ text: String) -> Decimal? {
        guard let value = Decimal(
            string: text.trimmingCharacters(in: .whitespacesAndNewlines),
            locale: .current
        ), value > 0 else {
            return nil
        }
        return value
    }
}

private struct NutritionGoalField: View {
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
