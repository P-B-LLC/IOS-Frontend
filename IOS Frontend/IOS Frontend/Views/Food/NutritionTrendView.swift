//
//  NutritionTrendView.swift
//  IOS Frontend
//
//  Whether the eating is consistent, rather than what happened today.
//
//  Everything in Food answers for one day: today's total, today's macros,
//  today's meals. That is the right unit for logging and the wrong one for
//  the question people actually have, which is whether any of it is holding
//  together over a week. A single good day and a single bad day look
//  identical from inside the day.
//
//  Nothing new is fetched to answer it. `ensureMonth` already loads a whole
//  month and caches it, and the totals per day already exist; this reads
//  what the app has and draws it.
//

import Charts
import SwiftUI

struct NutritionTrendView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The day the Food tab was on, so the window ends where the user was
    /// looking rather than always at today.
    let referenceDate: Date

    enum Window: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30

        var id: Int { rawValue }
        var title: String { self == .week ? "7 days" : "30 days" }
    }

    @State private var window: Window = .week

    private struct Day: Identifiable {
        let date: Date
        let total: NutritionAmount
        var id: Date { date }
        var calories: Double { NSDecimalNumber(decimal: total.calories).doubleValue }
        /// A day with nothing logged is not a day of eating nothing. It is a
        /// day nobody wrote down, and averaging it as a zero would quietly
        /// claim otherwise.
        var wasLogged: Bool { total.calories > 0 }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: referenceDate)
        return (0..<window.rawValue).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            return Day(date: date, total: store.total(on: date))
        }
    }

    private var logged: [Day] { days.filter(\.wasLogged) }
    private var goal: Double { NSDecimalNumber(decimal: store.goals.calories).doubleValue }

    private var average: Double {
        guard !logged.isEmpty else { return 0 }
        return logged.map(\.calories).reduce(0, +) / Double(logged.count)
    }

    /// Days inside a tenth of the goal either way. Close enough is the useful
    /// question; exactly on target never happens and would measure nothing.
    private var onTarget: Int {
        guard goal > 0 else { return 0 }
        return logged.filter { abs($0.calories - goal) <= goal * 0.1 }.count
    }

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(timeOfDay: timeOfDay)
                Picker("Window", selection: $window) {
                    ForEach(Window.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if logged.isEmpty {
                    empty(timeOfDay: timeOfDay)
                } else {
                    chart(timeOfDay: timeOfDay)
                    summary(timeOfDay: timeOfDay)
                    macros(timeOfDay: timeOfDay)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Nutrition trend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .homeTimeScreen(timeOfDay)
        // Keyed on the window, because thirty days reaches back into the
        // month before and that month has to be asked for too.
        .task(id: window) { await load() }
    }

    private func load() async {
        let calendar = Calendar.current
        await store.ensureMonth(referenceDate)
        if let earliest = days.first?.date,
           !calendar.isDate(earliest, equalTo: referenceDate, toGranularity: .month) {
            await store.ensureMonth(earliest)
        }
    }

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FUEL OVER TIME")
                .font(.community(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(timeOfDay.accent)
            Text("Is it holding together?")
                .font(.community(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("One day tells you very little. A fortnight tells you whether anything is actually steady.")
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
    }

    private func chart(timeOfDay: HomeTimeOfDay) -> some View {
        Chart {
            ForEach(days) { day in
                if day.wasLogged {
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Calories", day.calories)
                    )
                    .foregroundStyle(
                        // Over the goal reads differently from under it, and
                        // the chart should not need a legend to say which.
                        day.calories > goal * 1.1 ? RepbaseDesign.warning : timeOfDay.accent
                    )
                    .cornerRadius(4)
                }
            }
            if goal > 0 {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(timeOfDay.canvasSecondaryText.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("goal \(Int(goal)) kcal")
                            .font(.community(.caption2))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: window == .week ? 1 : 7)) { value in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Daily calories against your goal")
    }

    private func summary(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 20) {
            stat("AVERAGE", "\(Int(average)) kcal", timeOfDay: timeOfDay)
            stat("ON TARGET", "\(onTarget) of \(logged.count)", timeOfDay: timeOfDay)
            stat("DAYS LOGGED", "\(logged.count) of \(days.count)", timeOfDay: timeOfDay)
        }
    }

    /// What the numbers above mean, said once, in a sentence.
    ///
    /// Two different failures look the same on the chart: eating off target,
    /// and not writing it down. They need opposite responses, so the page
    /// says which one it is seeing rather than leaving it to be inferred.
    private var reading: String {
        let missed = days.count - logged.count
        if missed > days.count / 2 {
            return "Most days in this window have nothing logged, so the average is speaking for a handful of days rather than the period."
        }
        if goal <= 0 { return "Set a calorie goal to see how these days compare against it." }
        if onTarget >= logged.count / 2 {
            return "More than half the logged days landed within a tenth of your goal."
        }
        return average > goal
            ? "The logged days average above your goal."
            : "The logged days average below your goal."
    }

    private func macros(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reading)
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("Days with nothing logged are left out of the average rather than counted as zero.")
                .font(.community(.caption))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .repbaseCard(contentPadding: 0, cornerRadius: 16)
    }

    private func stat(_ label: String, _ value: String, timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.community(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            Text(value)
                .font(.community(.title3, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func empty(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing logged in this window")
                .font(.community(.headline))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("Log a few days of meals and this will show how they compare with each other and with your goal.")
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .repbaseCard(contentPadding: 0, cornerRadius: 16)
    }
}
