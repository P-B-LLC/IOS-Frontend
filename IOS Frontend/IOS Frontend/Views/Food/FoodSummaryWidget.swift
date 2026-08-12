//
//  FoodSummaryWidget.swift
//  IOS Frontend
//
//  Compact home entry point for today's calories and macronutrients.
//

import SwiftUI

struct FoodSummaryWidget: View {
    @Environment(FoodTrackingStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .foregroundStyle(Color.orange)
                Text("Food Today")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Tap a total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                metricLink(
                    title: "Calories",
                    value: total.calories,
                    goal: store.goals.calories,
                    unit: "cal",
                    icon: "flame.fill",
                    color: .orange
                )
                metricLink(
                    title: "Protein",
                    value: total.proteinGrams,
                    goal: store.goals.proteinGrams,
                    unit: "g",
                    icon: "dumbbell.fill",
                    color: .blue
                )
                metricLink(
                    title: "Carbs",
                    value: total.carbohydrateGrams,
                    goal: store.goals.carbohydrateGrams,
                    unit: "g",
                    icon: "leaf.fill",
                    color: .green
                )
                metricLink(
                    title: "Fat",
                    value: total.fatGrams,
                    goal: store.goals.fatGrams,
                    unit: "g",
                    icon: "drop.fill",
                    color: .purple
                )
            }
        }
    }

    private var total: NutritionAmount {
        store.total(on: Date())
    }

    private func metricLink(
        title: String,
        value: Decimal,
        goal: Decimal,
        unit: String,
        icon: String,
        color: Color
    ) -> some View {
        NavigationLink {
            FoodTrackingView()
        } label: {
            HomeNutritionCard(
                title: title,
                value: value,
                goal: goal,
                unit: unit,
                icon: icon,
                color: color
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeNutritionCard: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.nutritionText)
                    .font(.title3.weight(.bold))
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(color)
            Text("of \(goal.nutritionText) \(unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        }
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

#Preview {
    NavigationStack {
        FoodSummaryWidget()
            .padding()
    }
    .environment(FoodTrackingStore.preview)
}
