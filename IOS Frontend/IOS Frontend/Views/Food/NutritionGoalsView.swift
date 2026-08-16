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
            VStack(spacing: 0) {
                goalsHeader(timeOfDay: timeOfDay)

                Form {
                    Section {
                        NutritionGoalField(title: "Calories", unit: "cal", text: $calories)
                        NutritionGoalField(title: "Protein", unit: "g", text: $protein)
                        NutritionGoalField(title: "Carbohydrates", unit: "g", text: $carbohydrates)
                        NutritionGoalField(title: "Fat", unit: "g", text: $fat)
                    } header: {
                        Text("Daily targets")
                    } footer: {
                        Text("These targets control the progress rings on Home and Food Tracking.")
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
    }

    private func goalsHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timeOfDay.secondaryText)
                .buttonStyle(.plain)

            Spacer()

            Button {
                save()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(RepbaseAccentCapsuleButtonStyle(timeOfDay: timeOfDay))
            .disabled(!isValid)
        }
        .overlay {
            Text("Nutrition Goals")
                .font(.headline)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
