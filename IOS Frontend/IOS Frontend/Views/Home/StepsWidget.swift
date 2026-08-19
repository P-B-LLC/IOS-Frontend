//
//  StepsWidget.swift
//  IOS Frontend
//
//  Steps from Apple Health, as the server holds them.
//

import SwiftUI

struct StepsWidget: View {
    @Environment(ActivityStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch store.availability {
            case .unsupported:
                message("This device does not have Apple Health.")
            case .notConnected:
                connectPrompt
            case .connected:
                if store.week.isEmpty {
                    message(
                        "Nothing from Health yet. If you expected steps here, check Repbase under Settings, Health, Data Access."
                    )
                } else {
                    todayCount
                    weekStrip
                }
            }

            if let error = store.persistenceError {
                message(error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(timeOfDay.primaryText)
        .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task {
            // Health backfills: a watch that synced late changes yesterday's
            // total too, so returning to Home asks again rather than trusting
            // whatever was true when the app launched.
            await store.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 28, height: 28)
                .background(
                    timeOfDay.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            Text("Steps")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            if store.isSyncing {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var todayCount: some View {
        if let steps = store.stepsToday {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(steps.formatted(.number))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("today")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(timeOfDay.secondaryText)
            }
        } else {
            // The server has days, but not this one. Saying "0" would claim
            // the user has not moved; they may simply not have carried their
            // phone yet today.
            Text("No steps recorded today yet")
                .font(.footnote.weight(.medium))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private var weekStrip: some View {
        let peak = max(store.weekPeak ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(lastSevenDays, id: \.self) { day in
                let steps = store.week.first { $0.day == day }?.steps
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            steps == nil
                                ? timeOfDay.accent.opacity(0.10)
                                : timeOfDay.accent.opacity(isToday(day) ? 1 : 0.45)
                        )
                        .frame(
                            height: max(
                                4,
                                CGFloat(steps ?? 0) / CGFloat(peak) * 54
                            )
                        )
                    Text(weekdayInitial(day))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 74, alignment: .bottom)
        .accessibilityLabel(weekAccessibilityLabel)
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring in the steps and workouts your iPhone or Apple Watch already records.")
                .font(.footnote)
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await store.connectHealth() }
            } label: {
                HStack(spacing: 6) {
                    if store.isRequestingHealthAccess {
                        ProgressView().controlSize(.small)
                    }
                    Text("Connect Apple Health")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    timeOfDay.accent.opacity(0.14),
                    in: Capsule()
                )
                .foregroundStyle(timeOfDay.accent)
            }
            .buttonStyle(.plain)
            .disabled(store.isRequestingHealthAccess)

            if let error = store.healthErrorMessage {
                message(error)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(timeOfDay.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Days

    /// The seven days ending today, oldest first. Built from the calendar
    /// rather than from what came back, so a day with no steps still gets a
    /// column and the strip does not silently shorten.
    private var lastSevenDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<ActivityStore.historyDays)
            .reversed()
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }

    private func weekdayInitial(_ day: Date) -> String {
        let index = Calendar.current.component(.weekday, from: day) - 1
        let symbols = Calendar.current.veryShortWeekdaySymbols
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private var weekAccessibilityLabel: String {
        let counted = store.week.count
        guard counted > 0 else { return "No steps in the last seven days" }
        let total = store.week.reduce(0) { $0 + $1.steps }
        return "\(total.formatted(.number)) steps across \(counted) of the last seven days"
    }
}
