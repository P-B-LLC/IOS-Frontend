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

    let date: Date
    let mealID: FoodMeal.ID

    @State private var searchText = ""
    @State private var databaseResults: [FoodEntry] = []
    @State private var isSearchingDatabase = false
    @State private var databaseError: String?
    private let foodDatabase = FoodDatabaseRepository()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pickerHeader(timeOfDay: timeOfDay)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("FOOD DATABASE")
                            .font(.community(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text("Find it quickly.")
                            .font(.community(size: 28, weight: .bold))
                            .tracking(-0.8)
                        Text("Search foods you have logged or enter nutrition manually.")
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
                    .padding(.horizontal, 2)
                    .frame(height: 52)
                    .overlay(alignment: .bottom) { Divider() }

                    databaseEditorialSection(timeOfDay: timeOfDay)
                    recentEditorialSection(timeOfDay: timeOfDay)

                    manualEntryCard(timeOfDay: timeOfDay)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
            .task(id: searchText) { await searchDatabase() }
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
                    Text("OPEN FOOD FACTS")
                        .font(.community(.caption2, weight: .bold))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            }

            if let databaseError {
                Text(databaseError)
                    .font(.community(.caption))
                    .foregroundStyle(.orange)
            } else if searchText.trimmed.count < 2 {
                Text("Type at least two letters to search packaged foods worldwide.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            } else if !isSearchingDatabase && databaseResults.isEmpty {
                Text("No database foods match this search.")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(databaseResults.enumerated()), id: \.element.id) { index, food in
                        Button { add(food) } label: { RecentFoodRow(food: food).padding(.vertical, 12) }
                            .buttonStyle(.plain)
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
            Text("Add again in one tap")
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
                        Button { add(food) } label: {
                            RecentFoodRow(food: food)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
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
        store.saveFood(
            FoodEntry(
                name: food.name,
                servings: food.servings,
                nutritionPerServing: food.nutritionPerServing
            ),
            in: mealID,
            on: date
        )
        dismiss()
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
            let results = try await foodDatabase.search(query)
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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
