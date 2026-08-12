//
//  FoodSummaryWidget.swift
//  IOS Frontend
//
//  One compact home widget for today's calories and macronutrients.
//

import SwiftUI

struct FoodSummaryWidget: View {
    @Environment(FoodTrackingStore.self) private var store

    var body: some View {
        NavigationLink {
            FoodTrackingView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Color.orange)
                    Text("Food Today")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                FilledNutritionMetric(
                    title: "Calories",
                    value: total.calories,
                    goal: store.goals.calories,
                    unit: "cal",
                    color: .blue,
                    isPrimary: true
                )

                HStack(spacing: 8) {
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Food today, \(total.calories.nutritionText) of \(store.goals.calories.nutritionText) calories"
        )
        .accessibilityHint("Opens food tracking")
    }

    private var total: NutritionAmount {
        store.total(on: Date())
    }
}

private struct FilledNutritionMetric: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let unit: String
    let color: Color
    var isPrimary = false

    var body: some View {
        VStack(alignment: .leading, spacing: isPrimary ? 7 : 5) {
            Text(title)
                .font(isPrimary ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value.nutritionText) \(unit)")
                    .font(isPrimary ? .headline : .subheadline.weight(.bold))
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

            if isPrimary {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isPrimary ? 76 : 68, alignment: .leading)
        .padding(isPrimary ? 12 : 10)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.08))
                    Rectangle()
                        .fill(color.opacity(0.22))
                        .frame(width: proxy.size.width * progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.13), lineWidth: 1)
        }
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }

    private var statusText: String {
        let remaining = goal - value
        if remaining >= 0 {
            return "\(remaining.nutritionText) \(unit) remaining"
        }
        return "\((-remaining).nutritionText) \(unit) over goal"
    }
}

#Preview {
    NavigationStack {
        FoodSummaryWidget()
            .padding()
    }
    .environment(FoodTrackingStore.preview)
}
