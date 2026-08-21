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
                            .font(.caption)
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
        .sheet(isPresented: $isCreatingMeal) {
            NavigationStack {
                SavedMealEditorView()
            }
        }
        .sheet(item: $mealToEdit) { savedMeal in
            NavigationStack {
                SavedMealEditorView(existing: savedMeal)
            }
        }
        .sheet(item: $mealToApply) { savedMeal in
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
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(RepbasePalette.caramel)
                Text("Your fastest meals will live here.")
                    .font(.title2.weight(.bold))
                Text("Build a recipe with its real ingredients and nutrition. Repbase keeps the totals ready to reuse.")
                    .font(.subheadline)
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
                        .font(.headline)
                    Text(ingredientSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(savedMeal.totalNutrition.calories.nutritionText) cal")
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 18) {
                Button("Add to days", systemImage: "calendar.badge.plus", action: onUse)
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
            .font(.caption.weight(.semibold))
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
        Form {
            Section("Recipe") {
                TextField("Recipe or meal name", text: $draft.name)
                    .textContentType(.name)
            }

            Section {
                if draft.ingredients.isEmpty {
                    Text("Add each ingredient using the nutrition shown for one serving.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(draft.ingredients) { ingredient in
                    Button {
                        ingredientToEdit = ingredient
                    } label: {
                        IngredientRow(ingredient: ingredient)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    draft.ingredients.remove(atOffsets: offsets)
                }

                Button("Add Ingredient", systemImage: "plus") {
                    isAddingIngredient = true
                }
            } header: {
                Text("Ingredients")
            }

            if !draft.ingredients.isEmpty {
                Section("Recipe total") {
                    NutritionTotalRow(amount: draft.totalNutrition)
                }
            }

            Section {
                Label(
                    "Saved recipes sync with your Repbase account.",
                    systemImage: "checkmark.icloud"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
        .sheet(isPresented: $isAddingIngredient) {
            NavigationStack {
                RecipeIngredientEditorView { ingredient in
                    draft.ingredients.append(ingredient)
                }
            }
        }
        .sheet(item: $ingredientToEdit) { ingredient in
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(ingredient.totalNutrition.calories.nutritionText) cal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.forward")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct NutritionTotalRow: View {
    let amount: NutritionAmount

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
            GridRow {
                metric("Calories", amount.calories, "cal")
                metric("Protein", amount.proteinGrams, "g")
            }
            GridRow {
                metric("Carbs", amount.carbohydrateGrams, "g")
                metric("Fat", amount.fatGrams, "g")
            }
        }
    }

    private func metric(_ label: String, _ value: Decimal, _ unit: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value.nutritionText) \(unit)")
                .fontWeight(.semibold)
        }
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
        Form {
            Section("Ingredient") {
                TextField("Ingredient name", text: $name)
                FoodNutritionField(title: "Servings", unit: "", text: $servings)
            }

            Section("Nutrition per serving") {
                FoodNutritionField(title: "Calories", unit: "cal", text: $calories)
                FoodNutritionField(title: "Protein", unit: "g", text: $protein)
                FoodNutritionField(title: "Carbohydrates", unit: "g", text: $carbohydrates)
                FoodNutritionField(title: "Fat", unit: "g", text: $fat)
            }
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
                            .font(.headline)
                        Text("\(savedMeal.ingredients.count) ingredients")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(savedMeal.totalNutrition.calories.nutritionText) cal")
                        .font(.subheadline.weight(.bold))
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
                .font(.subheadline.weight(.semibold))
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
                            .font(.caption2.weight(.semibold))
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
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(date.formatted(.dateTime.day()))
                            .font(.caption2)
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
