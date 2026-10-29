//
//  FoodPickerView.swift
//  IOS Frontend
//
//  Chooses how a food gets added to a meal: reuse something already logged,
//  search a food database once the OAS documents one, or enter it manually.
//

import SwiftUI

struct FoodPickerView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var pendingAdd: FoodEntry?
    @State private var draftSaved = false

    let date: Date
    let mealID: FoodMeal.ID

    @State private var searchText = ""
    @State private var databaseResults: [FoodDatabaseResult] = []
    @State private var isSearchingDatabase = false
    @State private var databaseError: String?
    @State private var selectedFood: FoodEntry?
    @State private var servingDescription = "1 serving of this food entry"
    @State private var savedFood: FoodEntry?
    @State private var openedInitialFood = false
    var initialFood: FoodEntry? = nil

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pickerHeader(timeOfDay: timeOfDay)
                if let savedFood {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54)).foregroundStyle(RepbaseDesign.success)
                    Text("Added to your meal")
                        .font(.community(.largeTitle, weight: .bold))
                    Text(savedFood.name).font(.community(.headline))
                    Text("\(savedFood.servings.nutritionText) servings · \(savedFood.totalNutrition.calories.nutritionText) kcal")
                        .foregroundStyle(.secondary)
                    Button("Add another food") {
                        self.savedFood = nil
                        pendingAdd = nil
                        draftSaved = false
                        searchText = ""
                    }.buttonStyle(RepbasePrimaryButtonStyle())
                    Button("Done") { dismiss() }.buttonStyle(RepbasePrimaryButtonStyle())
                } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Find your food.")
                        .font(.community(.largeTitle, weight: .bold))
                        .tracking(-0.8)
                    Text("Try chicken, rice, or yogurt. Then choose how much you had.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                    TextField("Search foods", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                if let pendingAdd {
                    Button("Retry saving \(pendingAdd.name)") { add(pendingAdd) }
                        .font(.community(.subheadline, weight: .semibold))
                        .disabled(isSaving)
                }

                databaseEditorialSection(timeOfDay: timeOfDay)
                if !store.recentFoods.isEmpty {
                    recentEditorialSection(timeOfDay: timeOfDay)
                }

                manualEntryCard(timeOfDay: timeOfDay)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemBackground))
        .saveFeedback(isSaving: isSaving, error: saveError)
        .recoverableDraft(key: "food-picker-\(mealID)", value: $pendingAdd,
                          saved: $draftSaved, error: $saveError)
        .task(id: searchText) { await searchDatabase() }
        .onAppear {
            if let initialFood, !openedInitialFood {
                openedInitialFood = true
                selectedFood = initialFood
            }
        }
        .sheet(item: $selectedFood) { food in
            NavigationStack {
                FoodPortionView(food: food, servingDescription: servingDescription,
                                isSaving: isSaving, error: saveError,
                                lockedForRetry: pendingAdd != nil, onAdd: add)
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func pickerHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.community(.subheadline, weight: .medium))
                .buttonStyle(.plain)
            Spacer()
            Text("Add Food").font(.community(.subheadline, weight: .bold))
            Spacer()
            Color.clear.frame(width: 46, height: 1)
        }
        .foregroundStyle(timeOfDay.canvasPrimaryText)
        .frame(height: 48)
    }

    private func databaseEditorialSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FOOD DATABASE")
                    .font(.community(.caption2, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(timeOfDay.accent)
                Spacer()
                if isSearchingDatabase { ProgressView().controlSize(.mini) }
                else if searchText.trimmed.count >= 2 {
                    Text("USDA FOODDATA CENTRAL")
                        .font(.community(.caption2, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            }

            if let databaseError {
                Text(databaseError)
                    .font(.community(.caption))
                    .foregroundStyle(.orange)
            } else if searchText.trimmed.count < 2 {
                Text("Type at least two letters to search foods.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            } else if !isSearchingDatabase && databaseResults.isEmpty {
                Text("No database foods match this search.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(databaseResults.enumerated()), id: \.element.id) { index, result in
                        Button {
                            servingDescription = result.servingDescription
                            selectedFood = result.entry
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                DatabaseFoodRow(result: result)
                                Text("Choose portion →").font(.community(.subheadline, weight: .semibold))
                                    .foregroundStyle(timeOfDay.accent)
                            }.padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || pendingAdd != nil)
                        if index < databaseResults.count - 1 { Divider() }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func recentEditorialSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENTLY USED")
                .font(.community(.caption2, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(timeOfDay.accent)
            Text("Choose a food, then check your portion")
                .font(.community(.footnote))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            VStack(spacing: 0) {
                if filteredRecents.isEmpty {
                    Text(recentEmptyMessage)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 22)
                } else {
                    ForEach(Array(filteredRecents.enumerated()), id: \.element.id) { index, food in
                        Button {
                            servingDescription = "1 serving of this food entry"
                            selectedFood = food
                        } label: {
                            RecentFoodRow(food: food)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || pendingAdd != nil)
                        if index < filteredRecents.count - 1 { Divider() }
                    }
                }
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func manualEntryCard(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationLink {
            FoodEntryEditorView(date: date, mealID: mealID) { dismiss() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.and.pencil")
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .frame(width: 28, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enter nutrition manually").font(.community(.subheadline, weight: .semibold))
                    Text("Calories, protein, carbs, and fat")
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.community(.caption, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Data

    private var filteredRecents: [FoodEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.recentFoods }
        return store.recentFoods.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var recentEmptyMessage: String {
        store.recentFoods.isEmpty
            ? "Foods you log will show up here so you can add them again in one tap."
            : "No previously used food matches that search."
    }

    /// Adds a copy of a previously used food. A fresh identifier keeps this
    /// entry independent, so editing it never changes the original.
    private func add(_ food: FoodEntry) {
        guard !isSaving else { return }
        if let pendingAdd,
           pendingAdd.name != food.name || pendingAdd.servings != food.servings || pendingAdd.nutritionPerServing != food.nutritionPerServing {
            saveError = "Please retry the previous food first so we can confirm whether it saved."
            return
        }
        let entry = pendingAdd ?? FoodEntry(name: food.name, servings: food.servings,
                                           nutritionPerServing: food.nutritionPerServing)
        pendingAdd = entry
        isSaving = true
        saveError = nil
        Task {
            defer { isSaving = false }
            let saved = await store.saveFood(
            entry,
            in: mealID,
            on: date
        )
        guard saved else {
            saveError = store.errorMessage ?? SaveFailure.unexplained
            return
        }
        draftSaved = true
        savedFood = entry
        selectedFood = nil
        }
    }

    private func searchDatabase() async {
        let query = searchText.trimmed
        guard query.count >= 2 else {
            databaseResults = []
            databaseError = nil
            isSearchingDatabase = false
            return
        }
        isSearchingDatabase = true
        databaseError = nil
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let results = try await store.searchCatalogue(query)
            guard !Task.isCancelled, query == searchText.trimmed else { return }
            databaseResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            databaseResults = []
            databaseError = "The food database could not be reached. You can still reuse or enter a food manually."
        }
        isSearchingDatabase = false
    }
}

/// Portion selection changes only the quantity; saving still uses the picker's
/// existing retry-safe save path and a fresh entry identity.
private struct FoodPortionView: View {
    @Environment(\.dismiss) private var dismiss
    let food: FoodEntry
    let servingDescription: String
    let isSaving: Bool
    let error: String?
    let lockedForRetry: Bool
    let onAdd: (FoodEntry) -> Void
    @State private var quantity: String

    init(food: FoodEntry, servingDescription: String, isSaving: Bool,
         error: String?, lockedForRetry: Bool, onAdd: @escaping (FoodEntry) -> Void) {
        self.food = food
        self.servingDescription = servingDescription
        self.isSaving = isSaving
        self.error = error
        self.lockedForRetry = lockedForRetry
        self.onAdd = onAdd
        _quantity = State(initialValue: food.servings.nutritionText)
    }

    private var servings: Decimal? {
        guard let value = Decimal(string: quantity, locale: .current), value > 0, value <= 1000 else { return nil }
        return value
    }
    private var nutrition: NutritionAmount { food.nutritionPerServing * (servings ?? 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("How much did you have?").font(.community(.largeTitle, weight: .bold))
                Text(food.name).font(.community(.subheadline)).foregroundStyle(.secondary)
                Text("YOUR PORTION").font(.community(.caption, weight: .semibold)).foregroundStyle(.secondary)
                HStack {
                    Button { adjust(by: Decimal(string: "-0.5")!) } label: {
                        Image(systemName: "minus").frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.bordered).buttonBorderShape(.circle)
                        .accessibilityLabel("Decrease servings")
                    Spacer()
                    TextField("1", text: $quantity)
                        .keyboardType(.decimalPad)
                        .font(.community(.largeTitle, weight: .bold))
                        .multilineTextAlignment(.center)
                        .frame(width: 130, height: 130)
                        .overlay(Circle().strokeBorder(RepbaseDesign.accent, lineWidth: 3))
                        .accessibilityLabel("Servings")
                    Spacer()
                    Button { adjust(by: Decimal(string: "0.5")!) } label: {
                        Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.bordered).buttonBorderShape(.circle)
                        .accessibilityLabel("Increase servings")
                }
                .disabled(isSaving || lockedForRetry)
                Text("Per serving: \(servingDescription)")
                    .font(.community(.caption)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("For your portion").foregroundStyle(.secondary)
                    Text("\(nutrition.calories.nutritionText) kcal").font(.community(.largeTitle, weight: .bold))
                    ForEach(Macro.allCases) { macro in
                        Text("\(macro.grams(in: nutrition).nutritionText) g \(macro.title)")
                            .font(.community(.subheadline)).foregroundStyle(macro.color)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) }
                if servings == nil { Text("Enter a quantity greater than zero, up to 1,000 servings.").foregroundStyle(.secondary) }
                Button(isSaving ? "Saving…" : lockedForRetry ? "Retry adding food" : "Add to meal") {
                    guard let servings else { return }
                    var entry = food
                    entry.servings = servings
                    onAdd(entry)
                }
                .buttonStyle(RepbasePrimaryButtonStyle())
                .disabled(isSaving || servings == nil)
                Text("You can edit the portion later.").font(.community(.caption)).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back to results") { dismiss() }.disabled(isSaving)
            }
        }
    }

    private func adjust(by delta: Decimal) {
        quantity = min(1000, max(Decimal(string: "0.5")!, (servings ?? 1) + delta)).nutritionText
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A catalogue row.
///
/// Says what the numbers are measured against, which the recents row has no
/// need to: a food logged before carries the serving it was logged with, while
/// nearly everything out of FoodData Central is per 100 g. Adding one without
/// reading that is how a chicken breast gets logged as a third of itself.
private struct DatabaseFoodRow: View {
    let result: FoodDatabaseResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.community(.subheadline))
                .foregroundStyle(Color.orange)
                .frame(width: 24, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.entry.name)
                    .font(.community(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("Per \(result.servingDescription) · P \(result.entry.totalNutrition.proteinGrams.nutritionText) · C \(result.entry.totalNutrition.carbohydrateGrams.nutritionText) · F \(result.entry.totalNutrition.fatGrams.nutritionText)")
                    .font(.community(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(result.entry.totalNutrition.calories.nutritionText) cal")
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}

private struct RecentFoodRow: View {
    let food: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.community(.subheadline))
                .foregroundStyle(Color.orange)
                .frame(width: 24, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.community(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("P \(food.totalNutrition.proteinGrams.nutritionText) · C \(food.totalNutrition.carbohydrateGrams.nutritionText) · F \(food.totalNutrition.fatGrams.nutritionText)")
                    .font(.community(.caption2))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(food.totalNutrition.calories.nutritionText) cal")
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)

            Image(systemName: "plus")
                .font(.community(.caption, weight: .bold))
                .foregroundStyle(RepbaseDesign.onInk)
                .frame(width: 30, height: 30)
                .background(RepbaseDesign.ink, in: RoundedRectangle(cornerRadius: 9))
        }
        .contentShape(.rect)
    }
}

#Preview {
    let store = FoodTrackingStore.preview
    let meal = store.meals(on: Date())[0]
    NavigationStack {
        FoodPickerView(date: Date(), mealID: meal.id)
    }
    .environment(store)
}
