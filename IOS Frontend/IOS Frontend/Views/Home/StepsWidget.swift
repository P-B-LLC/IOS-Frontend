//
//  StepsWidget.swift
//  IOS Frontend
//
//  Steps from Apple Health, as the server holds them.
//
//  The card appears only when there are steps to draw. Asking for Health
//  access is Apple's sheet and nothing else: a card explaining that Health has
//  not answered, or offering a button to ask, is still a card on the screen,
//  and the screen is not where that conversation belongs.
//

import SwiftUI

struct StepsWidget: View {
    /// Whether to say something when there are no steps.
    ///
    /// Home stays quiet: a card there explaining that Health has not answered
    /// is noise on a page nobody opened to think about Health. The workout
    /// page is where steps are the point, so there it says how to turn them
    /// on rather than leaving a gap.
    var explainsWhenEmpty: Bool = false
    /// The training dashboard uses the glanceable single-row treatment. Home
    /// keeps the seven-day history card.
    var compact: Bool = false

    @Environment(ActivityStore.self) private var store
    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        if store.week.isEmpty == false {
            if compact { compactCard } else { card.padding(.top, 22) }
        } else if explainsWhenEmpty, store.isHealthSupported {
            connectCard
                .padding(.top, 22)
        }
    }

    private var compactCard: some View {
        let goal = 8_000
        let steps = store.stepsToday ?? 0
        let progress = min(Double(steps) / Double(goal), 1)
        let remaining = max(goal - steps, 0)
        let currentMarker = min(Int(progress * 8), 7)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TODAY'S MOVEMENT")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(RepbaseDesign.success)

                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(steps.formatted(.number))
                            .font(.title.weight(.bold))
                            .contentTransition(.numericText())
                        Text("steps today")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(timeOfDay.secondaryText)
                    }

                    Text(remaining == 0 ? "Daily goal reached" : "\(remaining.formatted(.number)) more to reach your goal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RepbaseDesign.success)
                }

                Spacer(minLength: 10)

                Text("\(goal / 1_000)K GOAL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RepbaseDesign.success)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RepbasePalette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ZStack {
                Capsule()
                    .fill(RepbaseDesign.success.opacity(0.55))
                    .frame(height: 4)

                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(markerColor(at: index, currentMarker: currentMarker))
                            .frame(width: 20, height: 20)
                            .overlay {
                                if index == currentMarker {
                                    Circle()
                                        .stroke(RepbaseDesign.accent.opacity(0.32), lineWidth: 4)
                                        .frame(width: 28, height: 28)
                                }
                            }

                        if index < 7 { Spacer(minLength: 0) }
                    }
                }
            }
            .frame(height: 28)
            .padding(.top, 7)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .background(
            Color(hex: 0xDDE8E1),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .task { await store.refresh() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(steps.formatted(.number)) steps today, \(progress.formatted(.percent)) of goal")
    }

    private func markerColor(at index: Int, currentMarker: Int) -> Color {
        if index < currentMarker { return RepbaseDesign.success }
        if index == currentMarker { return RepbaseDesign.accent }
        return RepbasePalette.paper
    }

    /// Shown when there are no steps to draw.
    ///
    /// Tappable only before Apple's sheet has been shown. Afterwards iOS shows
    /// nothing at all on a second request, so a button would be a control that
    /// visibly does nothing; the text points at Settings instead.
    @ViewBuilder
    private var connectCard: some View {
        if store.hasAskedHealth {
            connectBody(
                message: "No steps from Health yet. Turn Repbase on under Settings, Privacy & Security, Health.",
                action: nil
            )
        } else {
            connectBody(
                message: "Connect to Apple Health to see steps.",
                action: { Task { await store.connectHealth() } }
            )
        }
    }

    private func connectBody(
        message: String,
        action: (() -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 28, height: 28)
                .background(
                    timeOfDay.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            Text(message)
                .font(.footnote)
                .foregroundStyle(timeOfDay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if store.isRequestingHealthAccess {
                ProgressView().controlSize(.small)
            } else if action != nil {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(timeOfDay.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
        .task {
            // The card with steps in it refreshes on appear; this one has to
            // as well, or access granted in Settings would never be noticed
            // and the card would keep asking for something already given.
            await store.refresh()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            todayCount
            weekStrip
            importNote
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

    /// What the last import did, when it did anything.
    ///
    /// The skipped line is worth saying out loud. A run tracked in Repbase and
    /// recorded by the Watch is one run, and silently dropping the duplicate
    /// would look like the import missing workouts rather than declining to
    /// count them twice.
    @ViewBuilder
    private var importNote: some View {
        if let summary = store.lastImport,
           summary.imported > 0 || summary.skippedOverlapping > 0 {
            VStack(alignment: .leading, spacing: 3) {
                if summary.imported > 0 {
                    Text("\(summary.imported) \(workoutWord(summary.imported)) brought in from Health")
                }
                if summary.skippedOverlapping > 0 {
                    Text("\(summary.skippedOverlapping) \(workoutWord(summary.skippedOverlapping)) skipped, already recorded here")
                }
            }
            .font(.caption)
            .foregroundStyle(timeOfDay.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func workoutWord(_ count: Int) -> String {
        count == 1 ? "workout" : "workouts"
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
