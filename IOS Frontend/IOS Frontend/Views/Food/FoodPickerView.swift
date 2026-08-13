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

    var body: some View {
        List {
            databaseSection
            recentSection
            manualSection
        }
        .searchable(text: $searchText, prompt: "Search your foods")
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    /// The food-database affordance. It stays visibly unavailable until
    /// nutrition search exists in API/openapi.yaml; the app must not call an
    /// undocumented endpoint.
    private var databaseSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search food database")
                        .foregroundStyle(.secondary)
                    Text("Not connected yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Search food database, not connected yet")
        } header: {
            Text("Food Database")
        } footer: {
            Text("Database search needs a documented backend endpoint. Until then, reuse a food below or enter one manually.")
        }
    }

    private var recentSection: some View {
        Section("Previously Used") {
            if filteredRecents.isEmpty {
                Text(recentEmptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredRecents) { food in
                    Button {
                        add(food)
                    } label: {
                        RecentFoodRow(food: food)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var manualSection: some View {
        Section {
            NavigationLink {
                // Saving from here closes the whole sheet and returns to the
                // meal; cancelling just pops back to this picker.
                FoodEntryEditorView(date: date, mealID: mealID) {
                    dismiss()
                }
            } label: {
                Label("Enter Manually", systemImage: "square.and.pencil")
            }
        } footer: {
            Text("Add a food by typing its name and nutrition label values.")
        }
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
}

private struct RecentFoodRow: View {
    let food: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.subheadline)
                .foregroundStyle(Color.orange)
                .frame(width: 34, height: 34)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("P \(food.totalNutrition.proteinGrams.nutritionText) · C \(food.totalNutrition.carbohydrateGrams.nutritionText) · F \(food.totalNutrition.fatGrams.nutritionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(food.totalNutrition.calories.nutritionText) cal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
