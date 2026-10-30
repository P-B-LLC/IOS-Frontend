//
//  WorkoutLiveActivityWidget.swift
//  RytivoWorkoutActivity
//
//  The Lock Screen banner and Dynamic Island for a lifting session.
//
//  Everything shown is in the activity's state, written by the app in the
//  language chosen inside Rytivo. Countdowns are drawn from dates, so the
//  system keeps them running with the app suspended. A rest that runs out
//  while nothing can update the activity is caught by its stale date: past
//  it, `isStale` is true and the view says the rest is over.
//
//  On a locked iPhone with the Always-On display, the Lock Screen dims and
//  the system stops redrawing every second: a countdown with more than a
//  minute left is shown as "1:--" and only its minutes move. That is the
//  system's doing and nothing can turn it off, but it read as a broken
//  timer. While the screen is dimmed the rest says when it ends instead --
//  "Ends at 9:41" -- which is exact and needs no redrawing at all.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum Palette {
    static let accent = Color(red: 0xF8 / 255, green: 0x67 / 255, blue: 0x22 / 255)
    static let success = Color(red: 0x78 / 255, green: 0x91 / 255, blue: 0x82 / 255)
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            let view = Presentation(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.setTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeadlineFigure(view: view)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(view.isResting ? Palette.accent : .primary)
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        view.progress
                        view.controls
                    }
                }
            } compactLeading: {
                Image(systemName: view.isResting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(Palette.accent)
            } compactTrailing: {
                view.compactFigure
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(view.isResting ? Palette.accent : .primary)
            } minimal: {
                if view.isResting {
                    view.compactFigure
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(Palette.accent)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(Palette.accent)
                }
            }
            .keylineTint(Palette.accent)
        }
    }
}

/// The parts both presentations draw, worked out once from the state.
private struct Presentation {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    var state: WorkoutActivityAttributes.ContentState { context.state }

    /// A rest whose end date has passed is over, even though nothing has been
    /// able to say so: the activity is stale exactly then.
    var restIsOver: Bool {
        state.phase == .resting && (context.isStale || (state.restEndsAt ?? .distantFuture) <= Date())
    }
    var isResting: Bool { state.phase == .resting && !restIsOver }
    var isPaused: Bool { state.phase == .paused }

    @ViewBuilder var compactFigure: some View {
        if isResting, let range = state.restRange {
            Text(timerInterval: range, countsDown: true, showsHours: false)
                .multilineTextAlignment(.trailing)
        } else if isPaused, let left = state.restPausedRemaining {
            Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text("\(state.loggedSets)/\(state.totalSets)")
        }
    }

    @ViewBuilder var progress: some View {
        if isResting, let range = state.restRange {
            ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(Palette.accent)
        } else if isPaused, let left = state.restPausedRemaining, let total = state.restTotalSeconds, total > 0 {
            ProgressView(value: max(0, total - left), total: total)
                .tint(Palette.accent.opacity(0.6))
        } else {
            ProgressView(value: Double(state.loggedSets), total: Double(max(state.totalSets, 1)))
                .tint(Palette.success)
        }
    }

    @ViewBuilder var controls: some View {
        HStack(spacing: 8) {
            if (isResting || isPaused), let restID = state.restID {
                Button(intent: ToggleRestTimerIntent(sessionID: state.sessionID, restID: restID)) {
                    Label(isPaused ? state.labels.resume : state.labels.pause,
                          systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(Palette.accent)
                Button(intent: AddRestTimeIntent(sessionID: state.sessionID, restID: restID, seconds: 15)) {
                    Text(state.labels.addTime)
                        .frame(maxWidth: .infinity)
                }
                Button(intent: SkipRestTimerIntent(sessionID: state.sessionID, restID: restID)) {
                    Label(state.labels.skip, systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
            } else if state.phase == .done {
                Label(state.labels.workoutDone, systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.success)
                    .frame(maxWidth: .infinity)
            } else if state.canCompleteSet, let exerciseID = state.exerciseID, let setID = state.setID {
                Button(intent: CompleteWorkoutSetIntent(sessionID: state.sessionID, exerciseID: exerciseID, setID: setID)) {
                    Label(state.labels.completeSet, systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Palette.success)
            } else {
                Text(state.labels.openToContinue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }
}

/// The big figure: the countdown while resting, what is left while paused,
/// and the sets otherwise.
private struct HeadlineFigure: View {
    let view: Presentation
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if view.isResting, let range = view.state.restRange {
            if isLuminanceReduced {
                // See the note at the top of the file: a dimmed Lock Screen
                // cannot tick seconds, so the end time stands in for them.
                Text(range.upperBound, style: .time)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(timerInterval: range, countsDown: true, showsHours: false)
                    .multilineTextAlignment(.trailing)
            }
        } else if view.isPaused, let left = view.state.restPausedRemaining {
            Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text("\(view.state.loggedSets)/\(view.state.totalSets)")
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    private var view: Presentation { Presentation(context: context) }
    private var state: WorkoutActivityAttributes.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "dumbbell.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.accent)
                Text(context.attributes.workoutName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(context.attributes.startedAt, style: .timer)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 64, alignment: .leading)
                Spacer(minLength: 4)
                Text(state.progressText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let badge = state.setBadge {
                            Text(badge)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 5))
                        }
                        Text(state.setTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    if let target = state.targetText {
                        Text(target)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Palette.accent)
                    }
                    if let previous = state.previousText {
                        Text(previous)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if view.isResting || view.isPaused {
                        Text(view.isPaused
                             ? state.labels.restPaused
                             : isLuminanceReduced ? (state.labels.restEndsAt ?? state.labels.rest) : state.labels.rest)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else if view.restIsOver {
                        Text(state.labels.restOver)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.success)
                    }
                    HeadlineFigure(view: view)
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(view.isResting ? Palette.accent : .primary)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }

            view.progress

            view.controls

            if let next = state.nextText, !(view.isResting || view.isPaused) {
                Text(next)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}
