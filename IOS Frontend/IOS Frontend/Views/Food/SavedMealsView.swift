//
//  SavedMealsView.swift
//  IOS Frontend
//
//  Backend-backed reusable recipe library.
//

import SwiftUI

struct SavedMealsView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase

    let referenceDate: Date

    @State private var isCreatingMeal = false
    @State private var mealToEdit: SavedFoodMeal?
    @State private var mealToApply: SavedFoodMeal?

    var body: some View {
        Group {
            if store.savedMeals.isEmpty {
                emptyLibrary
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RepbaseScreenHeader(
                            eyebrow: "YOUR LIBRARY",
                            title: "Saved meals",
                            detail: "Recipes and combinations ready for another day."
                        )
                        VStack(spacing: 0) {
                            ForEach(Array(store.savedMeals.enumerated()), id: \.element.id) { index, savedMeal in
                            SavedMealRow(savedMeal: savedMeal) {
                                mealToApply = savedMeal
                            } onEdit: {
                                mealToEdit = savedMeal
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.removeReusableMeal(id: savedMeal.id)
                                }
                            }
                            if index < store.savedMeals.count - 1 { Divider().opacity(0.45) }
                        }
                        }
                        .overlay(alignment: .top) { Divider() }
                        Text("Saved meals sync with your Repbase account and are ready on every signed-in device.")
                            .font(.community(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, RepbaseDesign.pageInset)
                    .padding(.vertical, 16)
                }
            }
        }
        .repbaseScreen(phase)
        .navigationTitle("Saved Meals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") {
                    isCreatingMeal = true
                }
            }
        }
        .fullScreenCover(isPresented: $isCreatingMeal) {
            NavigationStack {
                SavedMealEditorView()
            }
        }
        .fullScreenCover(item: $mealToEdit) { savedMeal in
            NavigationStack {
                SavedMealEditorView(existing: savedMeal)
            }
        }
        .fullScreenCover(item: $mealToApply) { savedMeal in
            NavigationStack {
                ApplySavedMealView(savedMeal: savedMeal, referenceDate: referenceDate)
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 22) {
            RepbaseScreenHeader(
                eyebrow: "YOUR LIBRARY",
                title: "Save it once.",
                detail: "Keep complete meals here, then place them into any day without rebuilding them."
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("NO SAVED MEALS YET")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(RepbasePalette.caramel)
                Text("Your fastest meals will live here.")
                    .font(.community(.title2, weight: .bold))
                Text("Build a recipe with its real ingredients and nutrition. Repbase keeps the totals ready to reuse.")
                    .font(.community(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            Button("Create your first meal", systemImage: "plus") { isCreatingMeal = true }
                .buttonStyle(RepbasePrimaryButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 18)
    }
}

private struct SavedMealRow: View {
    let savedMeal: SavedFoodMeal
    let onUse: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(savedMeal.name)
                        .font(.community(.headline))
                    Text(ingredientSummary)
                        .font(.community(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(savedMeal.totalNutrition.calories.nutritionText) cal")
                    .font(.community(.subheadline, weight: .semibold))
            }

            HStack(spacing: 18) {
                Button("Add to days", systemImage: "calendar.badge.plus", action: onUse)
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
            .font(.community(.caption, weight: .semibold))
            .foregroundStyle(RepbasePalette.caramel)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
    }

    private var ingredientSummary: String {
        let count = savedMeal.ingredients.count
        return count == 1 ? "1 ingredient" : "\(count) ingredients"
    }
}

private struct SavedMealEditorView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase

    @State private var draft: SavedFoodMeal
    @State private var isAddingIngredient = false
    @State private var ingredientToEdit: FoodEntry?

    init(existing: SavedFoodMeal? = nil) {
        _draft = State(
            initialValue: existing ?? SavedFoodMeal(name: "")
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RECIPE NAME")
                        .font(.community(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(phase.secondaryText)
                TextField("Recipe or meal name", text: $draft.name)
                    .textContentType(.name)
                    .font(.community(.title2, weight: .semibold))
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Divider() }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingredients")
                        .font(.community(.title3, weight: .bold))

                    if draft.ingredients.isEmpty {
                        Text("Add each ingredient using the nutrition shown for one serving.")
                            .font(.community(.subheadline))
                            .foregroundStyle(phase.secondaryText)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(Array(draft.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                            HStack(spacing: 12) {
                                Button { ingredientToEdit = ingredient } label: {
                                    IngredientRow(ingredient: ingredient)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    draft.ingredients.removeAll { $0.id == ingredient.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.red.opacity(0.82))
                                .accessibilityLabel("Remove \(ingredient.name)")
                            }
                            .padding(.vertical, 13)
                            if index < draft.ingredients.count - 1 { Divider() }
                        }
                    }

                    Button {
                        isAddingIngredient = true
                    } label: {
                        Label("Add ingredient", systemImage: "plus")
                            .font(.community(.headline))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Divider() }
                    .overlay(alignment: .bottom) { Divider() }
                }

                if !draft.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recipe total")
                            .font(.community(.title3, weight: .bold))
                        NutritionTotalRow(amount: draft.totalNutrition)
                    }
                }

                Label(
                    "Saved recipes sync with your Repbase account.",
                    systemImage: "checkmark.icloud"
                )
                .font(.community(.caption))
                .foregroundStyle(phase.secondaryText)
            }
            .padding(22)
        }
        .navigationTitle(draft.name.isEmpty ? "New Recipe" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.saveReusableMeal(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .repbaseScreen(phase)
        .fullScreenCover(isPresented: $isAddingIngredient) {
            NavigationStack {
                RecipeIngredientEditorView { ingredient in
                    draft.ingredients.append(ingredient)
                }
            }
        }
        .fullScreenCover(item: $ingredientToEdit) { ingredient in
            NavigationStack {
                RecipeIngredientEditorView(existing: ingredient) { updated in
                    guard let index = draft.ingredients.firstIndex(where: { $0.id == updated.id }) else {
                        return
                    }
                    draft.ingredients[index] = updated
                }
            }
        }
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.ingredients.isEmpty
    }
}

private struct IngredientRow: View {
    let ingredient: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .foregroundStyle(.primary)
                Text("\(ingredient.servings.nutritionText) serving\(ingredient.servings == 1 ? "" : "s")")
                    .font(.community(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(ingredient.totalNutrition.calories.nutritionText) cal")
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.forward")
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct NutritionTotalRow: View {
    let amount: NutritionAmount

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            metric("CALORIES", amount.calories, "kcal", tint: RepbasePalette.caramel)
            metric("PROTEIN", amount.proteinGrams, "g", tint: Color(hex: 0xD9824B))
            metric("CARBS", amount.carbohydrateGrams, "g", tint: Color(hex: 0x4AAFB3))
            metric("FAT", amount.fatGrams, "g", tint: Color(hex: 0xB76AA5))
        }
    }

    private func metric(_ label: String, _ value: Decimal, _ unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.community(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(value.nutritionText) \(unit)")
                .font(.community(.subheadline, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Capsule().fill(tint).frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecipeIngredientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase

    private let ingredientID: FoodEntry.ID
    private let onSave: (FoodEntry) -> Void

    @State private var name: String
    @State private var servings: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbohydrates: String
    @State private var fat: String

    init(existing: FoodEntry? = nil, onSave: @escaping (FoodEntry) -> Void) {
        ingredientID = existing?.id ?? UUID()
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _servings = State(initialValue: existing?.servings.nutritionText ?? "1")
        _calories = State(initialValue: existing?.nutritionPerServing.calories.nutritionText ?? "")
        _protein = State(initialValue: existing?.nutritionPerServing.proteinGrams.nutritionText ?? "")
        _carbohydrates = State(initialValue: existing?.nutritionPerServing.carbohydrateGrams.nutritionText ?? "")
        _fat = State(initialValue: existing?.nutritionPerServing.fatGrams.nutritionText ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("INGREDIENT")
                        .font(.community(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(phase.secondaryText)
                TextField("Ingredient name", text: $name)
                        .font(.community(.title2, weight: .semibold))
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Divider() }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Servings").font(.community(.subheadline, weight: .medium))
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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Nutrition per serving")
                        .font(.community(.title3, weight: .bold))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("CALORIES")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(phase.secondaryText)
                        HStack(alignment: .firstTextBaseline) {
                            TextField("0", text: $calories)
                                .keyboardType(.decimalPad)
                                .font(.community(size: 38, weight: .bold, design: .rounded))
                            Spacer()
                            Text("kcal")
                                .font(.community(.subheadline, weight: .medium))
                                .foregroundStyle(phase.accent)
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Divider() }

                    HStack(alignment: .top, spacing: 18) {
                        ingredientMacro("PROTEIN", text: $protein, tint: Color(hex: 0xD9824B))
                        ingredientMacro("CARBS", text: $carbohydrates, tint: Color(hex: 0x4AAFB3))
                        ingredientMacro("FAT", text: $fat, tint: Color(hex: 0xB76AA5))
                    }
                }
            }
            .padding(22)
        }
        .navigationTitle(name.isEmpty ? "Add Ingredient" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!isValid)
            }
        }
        .repbaseScreen(phase)
    }

    private func ingredientMacro(_ title: String, text: Binding<String>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.community(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.community(.title2, weight: .semibold))
                Text("g").font(.community(.caption)).foregroundStyle(.secondary)
            }
            Capsule().fill(tint).frame(height: 4)
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

        onSave(
            FoodEntry(
                id: ingredientID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                servings: servings,
                nutritionPerServing: NutritionAmount(
                    calories: calories,
                    proteinGrams: protein,
                    carbohydrateGrams: carbohydrates,
                    fatGrams: fat
                )
            )
        )
        dismiss()
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

private struct ApplySavedMealView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase

    let savedMeal: SavedFoodMeal
    let referenceDate: Date

    @State private var mealNumber = 1
    @State private var selectedDates: Set<Date>

    init(savedMeal: SavedFoodMeal, referenceDate: Date) {
        self.savedMeal = savedMeal
        self.referenceDate = referenceDate
        _selectedDates = State(initialValue: [Calendar.current.startOfDay(for: referenceDate)])
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(savedMeal.name)
                            .font(.community(.headline))
                        Text("\(savedMeal.ingredients.count) ingredients")
                            .font(.community(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(savedMeal.totalNutrition.calories.nutritionText) cal")
                        .font(.community(.subheadline, weight: .bold))
                }
            }

            Section("Meal slot") {
                Picker("Add to", selection: $mealNumber) {
                    ForEach(1...8, id: \.self) { number in
                        Text("Meal \(number)").tag(number)
                    }
                }
            }

            Section {
                WeekApplicationSelector(
                    dates: weekDates,
                    selectedDates: $selectedDates
                )

                Button(selectedDates.count == weekDates.count ? "Clear Week" : "Select Entire Week") {
                    if selectedDates.count == weekDates.count {
                        selectedDates.removeAll()
                    } else {
                        selectedDates = Set(weekDates)
                    }
                }
                .font(.community(.subheadline, weight: .semibold))
            } header: {
                Text("Days")
            } footer: {
                Text("The saved meal is added once to the selected meal slot on each chosen day.")
            }
        }
        .navigationTitle("Add to Week")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    store.applyReusableMeal(
                        savedMeal,
                        to: selectedDates.sorted(),
                        mealNumber: mealNumber
                    )
                    dismiss()
                }
                .disabled(selectedDates.isEmpty)
            }
        }
        .repbaseScreen(phase)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: day)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: sunday)
        }
    }
}

private struct WeekApplicationSelector: View {
    let dates: [Date]
    @Binding var selectedDates: Set<Date>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                Button {
                    if selectedDates.contains(date) {
                        selectedDates.remove(date)
                    } else {
                        selectedDates.insert(date)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.community(.caption2, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(selectedDates.contains(date) ? Color.accentColor : Color.clear)
                            Circle()
                                .strokeBorder(
                                    selectedDates.contains(date) ? Color.accentColor : Color.secondary.opacity(0.5),
                                    lineWidth: 1.25
                                )
                            if selectedDates.contains(date) {
                                Image(systemName: "checkmark")
                                    .font(.community(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(date.formatted(.dateTime.day()))
                            .font(.community(.caption2))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityValue(selectedDates.contains(date) ? "Selected" : "Not selected")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SavedMealsView(referenceDate: Date())
    }
    .environment(FoodTrackingStore.preview)
}
