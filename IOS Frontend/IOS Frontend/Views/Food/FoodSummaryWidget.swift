//
//  FoodSummaryWidget.swift
//  IOS Frontend
//
//  Home nutrition summary with calorie progress drawn around the card.
//

import SwiftUI

struct FoodSummaryWidget: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        NavigationLink {
            FoodTrackingView()
        } label: {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 28, height: 28)
                            .background(timeOfDay.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        Text("Food Today")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }

                    Spacer(minLength: 10)

                    Text(total.calories.nutritionText)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("of \(store.goals.calories.nutritionText) calories")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    HomeMacroMetric(title: "Protein", value: total.proteinGrams, goal: store.goals.proteinGrams)
                    HomeMacroMetric(title: "Carbs", value: total.carbohydrateGrams, goal: store.goals.carbohydrateGrams)
                    HomeMacroMetric(title: "Fat", value: total.fatGrams, goal: store.goals.fatGrams)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .foregroundStyle(timeOfDay.primaryText)
            .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
            .overlay {
                ZStack {
                    FoodWidgetProgressBorder(cornerRadius: 22)
                        .stroke(timeOfDay.accent.opacity(0.16), lineWidth: 3.5)
                    FoodWidgetProgressBorder(cornerRadius: 22)
                        .trim(from: 0, to: calorieProgress)
                        .stroke(
                            timeOfDay.accent,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: timeOfDay.accent.opacity(0.28), radius: 3)
                        .animation(.easeInOut(duration: 0.55), value: calorieProgress)
                }
                .padding(1.75)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Food today, \(total.calories.nutritionText) of \(store.goals.calories.nutritionText) calories"
        )
        .accessibilityHint("Opens food tracking")
    }

    private var total: NutritionAmount { store.total(on: Date()) }

    private var calorieProgress: CGFloat {
        let goal = store.goals.calories.nutritionDouble
        guard goal > 0 else { return 0 }
        return CGFloat(min(max(total.calories.nutritionDouble / goal, 0), 1))
    }
}

/// A clockwise rounded path beginning on the top edge. Progress travels left
/// to right, down the right edge, around the bottom, then back up the left.
private struct FoodWidgetProgressBorder: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct HomeMacroMetric: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let title: String
    let value: Decimal
    let goal: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value.nutritionText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(timeOfDay.secondaryText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(timeOfDay.accent.opacity(0.14))
                    Capsule().fill(timeOfDay.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
        }
        .frame(width: 47, alignment: .leading)
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return CGFloat(min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1))
    }
}

#Preview {
    NavigationStack {
        FoodSummaryWidget().padding()
    }
    .homeTimeScreen(.day)
    .environment(FoodTrackingStore.preview)
}
