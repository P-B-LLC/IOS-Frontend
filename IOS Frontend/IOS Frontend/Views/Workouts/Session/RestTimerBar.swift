//
//  RestTimerBar.swift
//  IOS Frontend
//
//  The rest countdown, docked at the bottom of a lifting session.
//

import SwiftUI

/// Shows the rest in progress and its controls, or a way to start one.
///
/// Drawn from the timer's end date on every tick, never from a counter it
/// keeps itself, so it is right the moment the screen comes back after the
/// phone was locked or another app was open.
struct RestTimerBar: View {
    let timer: RestTimer?
    /// The rest to offer when none is running: the focused exercise's.
    let suggestedSeconds: Int
    @Environment(WorkoutStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finishedRest: RestTimer?
    private let phase = WorkoutVisualPhase.focus

    var body: some View {
        Group {
            if let timer {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    content(timer, now: context.date)
                }
                .task(id: timer) {
                    await announceFinish(of: timer)
                }
            } else if suggestedSeconds > 0 {
                startButton
            }
        }
        .sensoryFeedback(.success, trigger: finishedRest)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: timer?.id)
    }

    /// Waits for the end date and marks the moment, for the haptic. The
    /// notification covers the same moment when the app is not in front.
    private func announceFinish(of timer: RestTimer) async {
        guard let endsAt = timer.endsAt else { return }
        do {
            while !Task.isCancelled {
                let wait = endsAt.timeIntervalSinceNow
                guard wait > 0 else { break }
                try await Task.sleep(for: .seconds(wait))
            }
        } catch { return }
        guard !Task.isCancelled, timer.phase() == .finished,
              !timer.isFinishedBannerExpired() else { return }
        finishedRest = timer
    }

    @ViewBuilder
    private func content(_ timer: RestTimer, now: Date) -> some View {
        if timer.isFinishedBannerExpired(at: now) {
            // Do not flash an old completion notice while the store reconciles
            // a restored checkpoint or resumes its suspended deadline task.
            if suggestedSeconds > 0 { startButton }
        } else if timer.phase(at: now) == .finished {
            RestCompletionBanner(progress: timer.finishedBannerProgress(at: now)) {
                store.dismissFinishedRest(matching: timer)
            }
        } else {
            countdownContent(timer, now: now)
        }
    }

    private func countdownContent(_ timer: RestTimer, now: Date) -> some View {
        let state = timer.phase(at: now)
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle().stroke(phase.cardBorder, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: now))
                        .stroke(phase.accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: state == .paused ? "pause.fill" : "timer")
                        .font(.community(.caption, weight: .bold))
                        .foregroundStyle(phase.accent)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: state))
                        .font(.community(.caption2, weight: .bold))
                        .foregroundStyle(phase.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(RestTimer.clockText(timer.remaining(at: now)))
                        .font(.community(.title2, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(1)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 4)

                Group {
                    controlButton("-15", label: "Subtract 15 seconds") { store.adjustRest(by: -15) }
                    controlButton(state == .paused ? "play.fill" : "pause.fill",
                                  label: state == .paused ? "Resume rest" : "Pause rest",
                                  isSymbol: true, prominent: true) { store.toggleRestPause() }
                    controlButton("+15", label: "Add 15 seconds") { store.adjustRest(by: 15) }
                    Menu {
                        Button { store.resetRest() } label: { Label("Restart rest", systemImage: "arrow.counterclockwise") }
                        Button(role: .destructive) { store.skipRest() } label: { Label("Skip rest", systemImage: "forward.end.fill") }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.community(.subheadline, weight: .bold))
                            .frame(width: 38, height: 44)
                    } primaryAction: {
                        store.skipRest()
                    }
                    .accessibilityLabel("Skip rest")
                    .accessibilityHint("Double-tap to skip. Hold for Restart.")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(phase.accent.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: phase.shadow, radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
    }

    private func title(for state: RestTimer.Phase) -> LocalizedStringKey {
        switch state {
        case .running: "RESTING"
        case .paused: "PAUSED"
        case .finished: "REST IS OVER"
        }
    }

    private func controlButton(
        _ content: String,
        label: LocalizedStringKey,
        isSymbol: Bool = false,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isSymbol {
                    Image(systemName: content).font(.community(.subheadline, weight: .bold))
                } else {
                    Text(verbatim: content).font(.community(.caption, weight: .bold)).monospacedDigit()
                }
            }
            .foregroundStyle(prominent ? phase.onPrimaryAction : phase.primaryText)
            .frame(width: prominent ? 44 : 38, height: 44)
            .background {
                if prominent { Circle().fill(phase.primaryActionSurface).frame(width: 40, height: 40) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var startButton: some View {
        Button { store.startRest(seconds: suggestedSeconds) } label: {
            Label("Start rest · \(RestDurationOptions.label(suggestedSeconds))", systemImage: "timer")
                .font(.community(.subheadline, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(phase.accent)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(phase.cardBorder, lineWidth: 1) }
    }
}

/// The approved compact completion notice. It never owns the timer lifetime:
/// the store expires the persisted rest, while this view only draws its deadline.
struct RestCompletionBanner: View {
    let progress: Double
    let dismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.community(.title2, weight: .semibold))
                    .foregroundStyle(PlannerStyle.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("REST IS OVER")
                        .font(.community(.caption2, weight: .bold))
                        .foregroundStyle(PlannerStyle.success)
                    Text("Time for your next set")
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.community(.footnote, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            ProgressView(value: progress)
                .tint(PlannerStyle.success)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(PlannerStyle.successSoft, in: RoundedRectangle(cornerRadius: RepbaseTactileDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: RepbaseTactileDesign.cardRadius)
                .strokeBorder(PlannerStyle.success.opacity(contrast == .increased ? 0.7 : 0.25), lineWidth: 1)
        }
        .accessibilityIdentifier("workout.rest.complete")
    }
}
