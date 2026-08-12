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
            VStack(alignment: .leading, spacing: 14) {
                dayPicker
                dailySummary

                if store.isLocalDraftOnly {
                    localDraftNotice
                }

                mealsSection
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
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
        HStack(spacing: 8) {
            Button {
                changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            DatePicker(
                "Tracking date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)

            Button {
                changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(8)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.75)
        }
    }

    private var dailySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilledNutritionMetric(
                title: "Calories",
                value: total.calories,
                goal: store.goals.calories,
                unit: "cal",
                color: .blue,
                isPrimary: true,
                detail: "\(loggedFoodCount) foods logged"
            )

            HStack(spacing: 6) {
                FilledNutritionMetric(
                    title: "Carbs",
                    value: total.carbohydrateGrams,
                    goal: store.goals.carbohydrateGrams,
                    unit: "g",
                    color: .teal
                )
                FilledNutritionMetric(
                    title: "Fat",
                    value: total.fatGrams,
                    goal: store.goals.fatGrams,
                    unit: "g",
                    color: .purple
                )
                FilledNutritionMetric(
                    title: "Protein",
                    value: total.proteinGrams,
                    goal: store.goals.proteinGrams,
                    unit: "g",
                    color: .orange
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily nutrition totals")
    }

    private var localDraftNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(Color.orange)
            Text("Food entries are temporary until API sync is available.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meals")
                        .font(.headline)
                    Text("Tap a meal to log or update food.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Meal", systemImage: "plus") {
                    store.addMeal(on: selectedDate)
                }
                .font(.footnote.weight(.semibold))
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

private struct FilledNutritionMetric: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let unit: String
    let color: Color
    var isPrimary = false
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: isPrimary ? 5 : 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value.nutritionText) \(unit)")
                    .font(isPrimary ? .subheadline.weight(.bold) : .caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                Text("/ \(goal.nutritionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isPrimary ? 66 : 58, alignment: .leading)
        .padding(isPrimary ? 11 : 9)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.06))
                    Rectangle()
                        .fill(color.opacity(0.16))
                        .frame(width: proxy.size.width * progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.1), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.nutritionText) of \(goal.nutritionText) \(unit)")
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct MealRow: View {
    let meal: FoodMeal

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: meal.isComplete ? "checkmark" : "fork.knife")
                .font(.caption.weight(.bold))
                .foregroundStyle(meal.isComplete ? Color.green : Color.orange)
                .frame(width: 30, height: 30)
                .background(
                    (meal.isComplete ? Color.green : Color.orange).opacity(0.08),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            HStack(spacing: 6) {
                Text("\(meal.totalNutrition.calories.nutritionText) cal")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
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
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.03), radius: 5, y: 1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.75)
            }
    }
}

#Preview {
    NavigationStack {
        FoodTrackingView()
    }
    .environment(FoodTrackingStore.preview)
}
