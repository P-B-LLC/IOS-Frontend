//
//  FoodTrackingView.swift
//  IOS Frontend
//
//  Daily food dashboard inspired by the user's top-level paper workflow.
//

import SwiftUI

struct FoodTrackingView: View {
    @Environment(FoodTrackingStore.self) private var store
    @State private var selectedDate = Date()
    @State private var isEditingGoals = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dayPicker
                dailySummary

                if store.isLocalDraftOnly {
                    localDraftNotice
                }

                mealsSection
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Food Tracking")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Goals", systemImage: "slider.horizontal.3") {
                    isEditingGoals = true
                }
            }
        }
        .sheet(isPresented: $isEditingGoals) {
            NutritionGoalsView()
        }
        .onChange(of: selectedDate) {
            store.ensureDay(selectedDate)
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 10) {
            Button {
                changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)

            DatePicker(
                "Tracking date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button {
                changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var dailySummary: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            NutritionTotalCard(
                title: "Calories",
                value: total.calories,
                goal: store.goals.calories,
                unit: "cal",
                icon: "flame.fill",
                color: .orange,
                detail: "\(loggedFoodCount) foods logged"
            )
            NutritionTotalCard(
                title: "Protein",
                value: total.proteinGrams,
                goal: store.goals.proteinGrams,
                unit: "g",
                icon: "dumbbell.fill",
                color: .blue
            )
            NutritionTotalCard(
                title: "Carbs",
                value: total.carbohydrateGrams,
                goal: store.goals.carbohydrateGrams,
                unit: "g",
                icon: "leaf.fill",
                color: .green
            )
            NutritionTotalCard(
                title: "Fat",
                value: total.fatGrams,
                goal: store.goals.fatGrams,
                unit: "g",
                icon: "drop.fill",
                color: .purple
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily nutrition totals")
    }

    private var localDraftNotice: some View {
        Label(
            "Saved only while the app is open. Food sync and search will activate when those endpoints are added to the API spec.",
            systemImage: "externaldrive.badge.exclamationmark"
        )
        .font(.caption)
        .foregroundStyle(Color.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meals")
                        .font(.title3.weight(.bold))
                    Text("Tap a meal to log or update food.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Meal", systemImage: "plus") {
                    store.addMeal(on: selectedDate)
                }
                .font(.subheadline.weight(.semibold))
            }

            ForEach(store.meals(on: selectedDate)) { meal in
                NavigationLink {
                    MealDetailView(date: selectedDate, mealID: meal.id)
                } label: {
                    MealRow(meal: meal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var total: NutritionAmount {
        store.total(on: selectedDate)
    }

    private var loggedFoodCount: Int {
        store.meals(on: selectedDate).reduce(0) { $0 + $1.entries.count }
    }

    private func changeDay(by amount: Int) {
        selectedDate = Calendar.current.date(
            byAdding: .day,
            value: amount,
            to: selectedDate
        ) ?? selectedDate
    }
}

private struct NutritionTotalCard: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let unit: String
    let icon: String
    let color: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.nutritionText)
                    .font(.title2.weight(.bold))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(color)
            Text("of \(goal.nutritionText) \(unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .foodCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title), \(value.nutritionText) of \(goal.nutritionText) \(unit)"
        )
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct MealRow: View {
    let meal: FoodMeal

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: meal.isComplete ? "checkmark.circle.fill" : "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(meal.isComplete ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(meal.totalNutrition.calories.nutritionText) cal")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .foodCard()
    }

    private var subtitle: String {
        guard !meal.entries.isEmpty else { return "Nothing logged yet" }
        return meal.entries.map(\.name).joined(separator: ", ")
    }
}

extension View {
    func foodCard() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 7, y: 2)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

#Preview {
    NavigationStack {
        FoodTrackingView()
    }
    .environment(FoodTrackingStore.preview)
}
