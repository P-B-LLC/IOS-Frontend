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
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text("Set your baseline.")
                            .font(.community(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                        Text("These values power progress across Home and Food.")
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }

                    calorieTarget(timeOfDay: timeOfDay)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Macro balance")
                            .font(.community(.headline))

                        HStack(alignment: .top, spacing: 18) {
                            macroTarget(
                                "PROTEIN",
                                text: $protein,
                                tint: Color(hex: 0xD9824B),
                                caloriesPerGram: 4
                            )
                            macroTarget(
                                "CARBS",
                                text: $carbohydrates,
                                tint: Color(hex: 0x4AAFB3),
                                caloriesPerGram: 4
                            )
                            macroTarget(
                                "FAT",
                                text: $fat,
                                tint: Color(hex: 0xB76AA5),
                                caloriesPerGram: 9
                            )
                        }

                        Text("Tap any value to edit your daily target.")
                            .font(.community(.caption))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
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

    private func calorieTarget(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL CALORIES")
                .font(.community(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(timeOfDay.canvasSecondaryText)

            HStack(alignment: .firstTextBaseline) {
                TextField("0", text: $calories)
                    .keyboardType(.decimalPad)
                    .font(.community(size: 42, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("kcal per day")
                    .font(.community(.subheadline, weight: .medium))
                    .foregroundStyle(timeOfDay.accent)
            }
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func macroTarget(
        _ title: String,
        text: Binding<String>,
        tint: Color,
        caloriesPerGram: Decimal
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.community(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.community(.title2, weight: .semibold))
                    .minimumScaleFactor(0.7)
                Text("g")
                    .font(.community(.caption))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * macroShare(text.wrappedValue, caloriesPerGram: caloriesPerGram))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroShare(_ grams: String, caloriesPerGram: Decimal) -> CGFloat {
        guard let total = positive(calories),
              let grams = positive(grams),
              total > 0 else { return 0 }
        let share = NSDecimalNumber(decimal: grams * caloriesPerGram / total).doubleValue
        return CGFloat(min(max(share, 0), 1))
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
