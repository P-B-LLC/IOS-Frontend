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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pickerHeader(timeOfDay: timeOfDay)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("FOOD DATABASE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.25)
                            .foregroundStyle(timeOfDay.accent)
                        Text("Find it quickly.")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.8)
                        Text("Search foods you have logged or enter nutrition manually.")
                            .font(.subheadline)
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
                    .repbaseDepthSurface(cornerRadius: 18)

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
        }
    }

    private func pickerHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
            Spacer()
            Text("Add Food").font(.subheadline.weight(.bold))
            Spacer()
            Color.clear.frame(width: 46, height: 1)
        }
        .foregroundStyle(timeOfDay.canvasPrimaryText)
        .frame(height: 48)
    }

    private func databaseEditorialSection(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .frame(width: 40, height: 40)
                .background(RepbasePalette.oatmeal, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Online food database").font(.subheadline.weight(.semibold))
                Text("Connect search to expand results")
                    .font(.caption)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            Spacer(minLength: 4)
            Text("OFFLINE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RepbasePalette.oatmeal, in: Capsule())
        }
        .padding(12)
        .repbaseDepthSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Online food database, offline")
    }

    private func recentEditorialSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENTLY USED")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(timeOfDay.accent)
            Text("Add again in one tap")
                .font(.footnote)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            VStack(spacing: 0) {
                if filteredRecents.isEmpty {
                    Text(recentEmptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 22)
                } else {
                    ForEach(Array(filteredRecents.enumerated()), id: \.element.id) { index, food in
                        Button { add(food) } label: {
                            RecentFoodRow(food: food)
                                .padding(14)
                        }
                        .buttonStyle(.plain)
                        if index < filteredRecents.count - 1 { Divider().padding(.leading, 68) }
                    }
                }
            }
            .repbaseDepthSurface(cornerRadius: 22)
        }
    }

    private func manualEntryCard(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationLink {
            FoodEntryEditorView(date: date, mealID: mealID) { dismiss() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .frame(width: 44, height: 44)
                    .background(RepbasePalette.oatmeal, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enter nutrition manually").font(.subheadline.weight(.semibold))
                    Text("Calories, protein, carbs, and fat")
                        .font(.caption)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .repbaseDepthSurface(cornerRadius: 20)
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
