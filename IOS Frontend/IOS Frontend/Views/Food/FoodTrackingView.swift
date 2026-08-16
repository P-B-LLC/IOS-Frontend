//
//  FoodTrackingView.swift
//  IOS Frontend
//
//  Time-aware daily nutrition dashboard.
//

import SwiftUI

struct FoodTrackingView: View {
    @Environment(FoodTrackingStore.self) private var store
    @State private var selectedDate = Date()
    @State private var isEditingGoals = false
    @State private var isShowingSavedMeals = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(timeOfDay: HomeTimeOfDay(date: context.date))
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

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                weekSelector(timeOfDay: timeOfDay)
                dailySummary

                if store.isLocalDraftOnly {
                    localDraftNotice(timeOfDay: timeOfDay)
                }

                mealsSection(timeOfDay: timeOfDay)
                nutritionBreakdownLink(timeOfDay: timeOfDay)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Food Logging")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Goals", systemImage: "slider.horizontal.3") {
                    isEditingGoals = true
                }
            }
        }
        .homeTimeScreen(timeOfDay)
    }

    private func weekSelector(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    selectedDate = Date()
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedDateTitle)
                            .font(.subheadline.weight(.bold))
                        if Calendar.current.isDateInToday(selectedDate) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    changeWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Previous week")

                Text(weekRangeTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .frame(minWidth: 90)

                Button {
                    changeWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 6) {
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(timeOfDay.secondaryText)

                            Text(date.formatted(.dateTime.day()))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(isSelected(date) ? Color.white : timeOfDay.primaryText)
                                .frame(width: 30, height: 28)
                                .background(
                                    isSelected(date) ? timeOfDay.accent : Color.clear,
                                    in: Capsule()
                                )
                                .overlay(alignment: .bottomTrailing) {
                                    if store.hasLoggedFood(on: date), !isSelected(date) {
                                        Circle()
                                            .fill(timeOfDay.accent)
                                            .frame(width: 5, height: 5)
                                            .offset(x: 1, y: 1)
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
        .repbaseCard(contentPadding: 13, cornerRadius: 20)
    }

    private var dailySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            CalorieGoalCard(
                value: total.calories,
                goal: store.goals.calories,
                loggedFoodCount: loggedFoodCount
            )

            HStack(spacing: 8) {
                MacroGoalCard(title: "Protein", value: total.proteinGrams, goal: store.goals.proteinGrams)
                MacroGoalCard(title: "Carbs", value: total.carbohydrateGrams, goal: store.goals.carbohydrateGrams)
                MacroGoalCard(title: "Fat", value: total.fatGrams, goal: store.goals.fatGrams)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily nutrition totals")
    }

    private func localDraftNotice(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(timeOfDay.accent)
            Text("Food entries are temporary until API sync is available.")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(timeOfDay.canvasSecondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mealsSection(timeOfDay: HomeTimeOfDay) -> some View {
        let meals = store.meals(on: selectedDate)
        let visualPhase: WorkoutVisualPhase = timeOfDay.usesDarkAppearance ? .focus : .prepare

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today’s meals")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
                Text("\(total.calories.nutritionText) kcal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    NavigationLink {
                        MealDetailView(date: selectedDate, mealID: meal.id)
                    } label: {
                        MealRow(meal: meal)
                    }
                    .buttonStyle(.plain)

                    if index < meals.count - 1 {
                        Divider().opacity(0.55)
                    }
                }
            }
            .repbaseCard(contentPadding: 10, cornerRadius: 20)

            HStack(spacing: 9) {
                Button {
                    isShowingSavedMeals = true
                } label: {
                    Label("Saved foods", systemImage: "bookmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)

                Button {
                    store.addMeal(on: selectedDate)
                } label: {
                    Label("Add meal", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .repbaseControlSurface(cornerRadius: 15)
            }

            if let firstMeal = meals.first {
                NavigationLink {
                    MealDetailView(date: selectedDate, mealID: firstMeal.id)
                } label: {
                    Label("Log Food", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorkoutPrimaryButtonStyle(phase: visualPhase))
            }
        }
    }

    private func nutritionBreakdownLink(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationLink {
            ScrollView {
                NutritionBreakdownView(meals: store.meals(on: selectedDate))
                    .padding()
            }
            .navigationTitle("Nutrition Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "chart.pie")
                    .font(.title3)
                    .foregroundStyle(timeOfDay.accent)
                Text("Nutrition breakdown")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .repbaseCard(contentPadding: 14, cornerRadius: 17)
        }
        .buttonStyle(.plain)
    }

    private var total: NutritionAmount { store.total(on: selectedDate) }

    private var loggedFoodCount: Int {
        store.meals(on: selectedDate).reduce(0) { $0 + $1.entries.count }
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: day)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
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

    private func changeWeek(by amount: Int) {
        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: selectedDate) ?? selectedDate
    }
}

private struct CalorieGoalCard: View {
    @Environment(\.workoutVisualPhase) private var phase
    let value: Decimal
    let goal: Decimal
    let loggedFoodCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calorie Goal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(phase.secondaryText)
                    Text("\(value.nutritionText) / \(goal.nutritionText) kcal")
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(remaining.nutritionText) left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(phase.accent)
                    Text("^[\(loggedFoodCount) food](inflect: true) logged")
                        .font(.caption2)
                        .foregroundStyle(phase.secondaryText)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.accent.opacity(0.12))
                    Capsule().fill(phase.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 7)
        }
        .repbaseCard(contentPadding: 16, cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories, \(value.nutritionText) of \(goal.nutritionText), \(remaining.nutritionText) remaining")
    }

    private var remaining: Decimal { max(goal - value, 0) }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct MacroGoalCard: View {
    @Environment(\.workoutVisualPhase) private var phase
    let title: String
    let value: Decimal
    let goal: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(phase.secondaryText)
            Text("\(value.nutritionText) / \(goal.nutritionText)g")
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(phase.accent.opacity(0.12))
                    Capsule().fill(phase.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .repbaseCard(contentPadding: 12, cornerRadius: 17)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.nutritionText) of \(goal.nutritionText) grams")
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct MealRow: View {
    @Environment(\.workoutVisualPhase) private var phase
    let meal: FoodMeal

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: mealSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(phase.accent)
                .frame(width: 38, height: 38)
                .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(phase.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isLogged ? "checkmark" : "plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(isLogged ? Color.white : phase.accent)
                .frame(width: 29, height: 29)
                .background(isLogged ? Color(hex: 0x5DAA86) : phase.accent.opacity(0.10), in: Circle())
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var isLogged: Bool { !meal.entries.isEmpty }

    private var subtitle: String {
        guard !meal.entries.isEmpty else { return "Nothing logged yet" }
        return "\(meal.entries.map(\.name).joined(separator: ", ")) · \(meal.totalNutrition.calories.nutritionText) kcal"
    }

    private var mealSymbol: String {
        let name = meal.name.lowercased()
        if name.contains("breakfast") || name.contains("1") { return "sun.max" }
        if name.contains("lunch") || name.contains("2") { return "sun.haze" }
        if name.contains("dinner") || name.contains("3") { return "takeoutbag.and.cup.and.straw" }
        if name.contains("snack") || name.contains("4") { return "moon" }
        return "fork.knife"
    }
}

extension View {
    func foodCard() -> some View {
        repbaseCard(contentPadding: 12, cornerRadius: 16)
    }
}

#Preview {
    NavigationStack { FoodTrackingView() }
        .environment(FoodTrackingStore.preview)
}
