//
//  FoodTrackingStore.swift
//  IOS Frontend
//
//  Interactive local food drafts. The supplied OAS currently has no food or
//  meal operations, so this store intentionally makes no undocumented calls.
//

import Foundation
import Observation

@Observable
final class FoodTrackingStore {
    private(set) var days: [String: FoodTrackingDay] = [:]
    private(set) var goals: NutritionGoals

    /// Remains true until food/meal operations are added to API/openapi.yaml.
    let isLocalDraftOnly = true

    init(goals: NutritionGoals = .default) {
        self.goals = goals
        ensureDay(Date())
    }

    func meals(on date: Date) -> [FoodMeal] {
        days[dateKey(for: date)]?.meals ?? []
    }

    func total(on date: Date) -> NutritionAmount {
        days[dateKey(for: date)]?.totalNutrition ?? .zero
    }

    func ensureDay(_ date: Date) {
        let key = dateKey(for: date)
        guard days[key] == nil else { return }
        days[key] = FoodTrackingDay(
            dateKey: key,
            meals: [
                FoodMeal(name: "Meal 1"),
                FoodMeal(name: "Meal 2"),
                FoodMeal(name: "Meal 3"),
                FoodMeal(name: "Meal 4")
            ]
        )
    }

    func addMeal(on date: Date) {
        mutateDay(on: date) { day in
            let nextNumber = day.meals.compactMap { meal -> Int? in
                guard meal.name.hasPrefix("Meal ") else { return nil }
                return Int(meal.name.dropFirst("Meal ".count))
            }.max().map { $0 + 1 } ?? (day.meals.count + 1)
            day.meals.append(FoodMeal(name: "Meal \(nextNumber)"))
        }
    }

    func renameMeal(id: FoodMeal.ID, to name: String, on date: Date) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        mutateMeal(id: id, on: date) { $0.name = name }
    }

    func removeMeal(id: FoodMeal.ID, on date: Date) {
        mutateDay(on: date) { day in
            day.meals.removeAll { $0.id == id }
        }
    }

    func saveFood(_ food: FoodEntry, in mealID: FoodMeal.ID, on date: Date) {
        mutateMeal(id: mealID, on: date) { meal in
            if let index = meal.entries.firstIndex(where: { $0.id == food.id }) {
                meal.entries[index] = food
            } else {
                meal.entries.append(food)
            }
            meal.isComplete = false
        }
    }

    func removeFood(id: FoodEntry.ID, from mealID: FoodMeal.ID, on date: Date) {
        mutateMeal(id: mealID, on: date) { meal in
            meal.entries.removeAll { $0.id == id }
            if meal.entries.isEmpty { meal.isComplete = false }
        }
    }

    func toggleMealComplete(id: FoodMeal.ID, on date: Date) {
        mutateMeal(id: id, on: date) { meal in
            guard !meal.entries.isEmpty else { return }
            meal.isComplete.toggle()
        }
    }

    func updateGoals(_ goals: NutritionGoals) {
        self.goals = goals
    }

    func reset() {
        days = [:]
        goals = .default
        ensureDay(Date())
    }

    func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func mutateDay(
        on date: Date,
        _ mutation: (inout FoodTrackingDay) -> Void
    ) {
        ensureDay(date)
        let key = dateKey(for: date)
        guard var day = days[key] else { return }
        mutation(&day)
        days[key] = day
    }

    private func mutateMeal(
        id: FoodMeal.ID,
        on date: Date,
        _ mutation: (inout FoodMeal) -> Void
    ) {
        mutateDay(on: date) { day in
            guard let index = day.meals.firstIndex(where: { $0.id == id }) else {
                return
            }
            mutation(&day.meals[index])
        }
    }
}

extension FoodTrackingStore {
    static var preview: FoodTrackingStore {
        let store = FoodTrackingStore()
        let meals = store.meals(on: Date())
        if let firstMeal = meals.first {
            store.saveFood(
                FoodEntry(
                    name: "Greek yogurt & berries",
                    nutritionPerServing: NutritionAmount(
                        calories: 280,
                        proteinGrams: 24,
                        carbohydrateGrams: 36,
                        fatGrams: 5
                    )
                ),
                in: firstMeal.id,
                on: Date()
            )
        }
        if meals.count > 1 {
            store.saveFood(
                FoodEntry(
                    name: "Chicken rice bowl",
                    nutritionPerServing: NutritionAmount(
                        calories: 610,
                        proteinGrams: 48,
                        carbohydrateGrams: 72,
                        fatGrams: 14
                    )
                ),
                in: meals[1].id,
                on: Date()
            )
        }
        return store
    }
}
