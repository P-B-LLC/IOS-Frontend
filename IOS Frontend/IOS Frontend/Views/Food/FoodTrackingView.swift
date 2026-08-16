//
//  FoodTrackingView.swift
//  IOS Frontend
//
//  Daily food dashboard inspired by the user's top-level paper workflow.
//

import SwiftUI

struct FoodTrackingView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.workoutVisualPhase) private var phase
    @State private var selectedDate = Date()
    @State private var isEditingGoals = false
    @State private var isShowingSavedMeals = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                weekSelector
                dailySummary

                if store.isLocalDraftOnly {
                    localDraftNotice
                }

                mealsSection
                NutritionBreakdownView(meals: store.meals(on: selectedDate))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .repbaseScreen(phase)
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
        .sheet(isPresented: $isShowingSavedMeals) {
            NavigationStack {
                SavedMealsView(referenceDate: selectedDate)
            }
        }
        .onChange(of: selectedDate) {
            store.ensureDay(selectedDate)
        }
    }

    private var weekSelector: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    selectedDate = Date()
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedDateTitle)
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "location.fill")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    changeWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 25, height: 25)
                }
                .accessibilityLabel("Previous week")

                Text(weekRangeTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 86)

                Button {
                    changeWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 25, height: 25)
                }
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 5) {
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(
                                    isSelected(date) ? phase.primaryText : phase.secondaryText
                                )

                            ZStack {
                                Circle()
                                    .fill(circleFill(for: date))
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .strokeBorder(circleBorder(for: date), lineWidth: 1.25)
                                    .frame(width: 24, height: 24)

                                Text(date.formatted(.dateTime.day()))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(
                                        isSelected(date) ? Color.white : phase.primaryText
                                    )

                                if store.hasLoggedFood(on: date) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(phase.accent)
                                        .frame(width: 10, height: 10)
                                        .background(phase.surfaceStart, in: Circle())
                                        .offset(x: 9, y: 9)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(isSelected(date) ? "Selected" : "")
                }
            }
        }
        .padding(11)
        .repbaseCard(contentPadding: 0, cornerRadius: 16)
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
                    title: "Protein",
                    value: total.proteinGrams,
                    goal: store.goals.proteinGrams,
                    unit: "g",
                    color: .orange
                )
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
                Button("Saved", systemImage: "bookmark") {
                    isShowingSavedMeals = true
                }
                .font(.footnote.weight(.semibold))
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

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: day)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: sunday)
        }
    }

    private var selectedDateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var weekRangeTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.day()))"
        }
        return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func circleFill(for date: Date) -> Color {
        if isSelected(date) { return phase.accent }
        return Color.clear
    }

    private func circleBorder(for date: Date) -> Color {
        if isSelected(date) || store.hasLoggedFood(on: date) { return phase.accent }
        return phase.secondaryText.opacity(0.55)
    }

    private func changeWeek(by amount: Int) {
        selectedDate = Calendar.current.date(
            byAdding: .weekOfYear,
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
        VStack(alignment: .leading, spacing: isPrimary ? 3 : 2) {
            if isPrimary {
                Text("\(value.nutritionText) / \(goal.nutritionText)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title.lowercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(value.nutritionText) / \(goal.nutritionText) \(unit)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.67)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isPrimary ? 62 : 42, alignment: .leading)
        .padding(isPrimary ? 11 : 8)
        .overlay(alignment: .bottomTrailing) {
            if isPrimary, let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(11)
            }
        }
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
            // A meal counts as logged as soon as it holds food.
            Image(systemName: isLogged ? "checkmark" : "fork.knife")
                .font(.caption.weight(.bold))
                .foregroundStyle(isLogged ? Color.green : Color.orange)
                .frame(width: 30, height: 30)
                .background(
                    (isLogged ? Color.green : Color.orange).opacity(0.08),
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

    private var isLogged: Bool {
        !meal.entries.isEmpty
    }

    private var subtitle: String {
        guard !meal.entries.isEmpty else { return "Nothing logged yet" }
        return meal.entries.map(\.name).joined(separator: ", ")
    }
}

extension View {
    func foodCard() -> some View {
        repbaseCard(contentPadding: 12, cornerRadius: 16)
    }
}

#Preview {
    NavigationStack {
        FoodTrackingView()
    }
    .environment(FoodTrackingStore.preview)
}
