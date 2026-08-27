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
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.community(size: 12, weight: .bold))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 28, height: 28)
                            .background(timeOfDay.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        Text("Food Today")
                            .font(.community(size: 16, weight: .semibold, design: .rounded))
                    }

                    Spacer(minLength: 10)

                    HomeCalorieArc(
                        value: total.calories,
                        goal: store.goals.calories,
                        progress: calorieProgress
                    )
                }
                .frame(width: 116, alignment: .leading)

                VStack(spacing: 11) {
                    HomeMacroMetric(title: "Protein", value: total.proteinGrams, goal: store.goals.proteinGrams)
                    HomeMacroMetric(title: "Carbs", value: total.carbohydrateGrams, goal: store.goals.carbohydrateGrams)
                    HomeMacroMetric(title: "Fat", value: total.fatGrams, goal: store.goals.fatGrams)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.forward")
                    .font(.community(size: 11, weight: .bold))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .foregroundStyle(timeOfDay.primaryText)
            .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
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

private struct HomeCalorieArc: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let value: Decimal
    let goal: Decimal
    let progress: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(timeOfDay.accent.opacity(0.16), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            Circle()
                .trim(from: 0.5, to: 0.5 + progress * 0.5)
                .stroke(timeOfDay.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .animation(.easeInOut(duration: 0.55), value: progress)

            VStack(spacing: 1) {
                Text(value.nutritionText)
                    .font(.community(size: 22, weight: .semibold, design: .rounded))
                Text("of \(goal.nutritionText) cal")
                    .font(.community(size: 9, weight: .medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            }
            .padding(.bottom, 5)
        }
        .frame(width: 108, height: 62)
        .clipped()
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
        HStack(spacing: 8) {
            Text(title)
                .font(.community(size: 10, weight: .medium))
                .foregroundStyle(timeOfDay.secondaryText)
                .frame(width: 44, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(timeOfDay.accent.opacity(0.14))
                    Capsule().fill(timeOfDay.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            Text("\(value.nutritionText)g")
                .font(.community(size: 11, weight: .semibold))
                .frame(width: 36, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
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
