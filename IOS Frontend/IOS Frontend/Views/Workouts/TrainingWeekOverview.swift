import SwiftUI

/// Lightweight server-derived feedback, not a readiness score or a prescription.
struct TrainingWeekOverview: View {
    let stats: TrainingStats
    private var theme: HomeTimeOfDay { .current }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("YOUR TRAINING WEEK", systemImage: "dumbbell.fill")
                    .font(.community(.caption2, weight: .bold)).tracking(1)
                    .foregroundStyle(theme.accent)
                Spacer()
                Image(systemName: stats.completedThisWeek > 0 ? "checkmark.seal" : "sun.max")
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
            }
            Text(stats.weeklyHeadline)
                .font(.community(.title2, weight: .bold)).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(stats.completedThisWeek)")
                    .font(.community(.largeTitle, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("session\(stats.completedThisWeek == 1 ? "" : "s") logged")
                    .font(.community(.subheadline)).foregroundStyle(theme.canvasSecondaryText)
            }
            if stats.weeklyGoal > 0 {
                ProgressView(value: stats.weeklyPlanProgress)
                    .tint(theme.accent)
                    .accessibilityLabel("Logged sessions compared with the weekly plan")
                    .accessibilityValue("\(stats.completedThisWeek) logged, \(stats.weeklyGoal) planned")
                Text("\(stats.weeklyGoal) planned this week · logged sessions can include unplanned workouts")
                    .font(.community(.caption)).foregroundStyle(theme.canvasSecondaryText)
            } else {
                Text("No sessions scheduled this week")
                    .font(.community(.caption)).foregroundStyle(theme.canvasSecondaryText)
            }
            Text(stats.weeklyEncouragement)
                .font(.community(.subheadline)).foregroundStyle(theme.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .foregroundStyle(theme.canvasPrimaryText)
        .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.canvasBorder, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: stats.completedThisWeek)
    }
}
