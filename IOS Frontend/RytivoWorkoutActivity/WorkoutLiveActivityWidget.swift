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
                    .padding(.top, 4)
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

    /// One filled button for what is most likely next and quiet ones beside
    /// it, as the system's own controls do. Every button used to be filled,
    /// the two without a tint in system blue, so three equal shouts sat
    /// under the timer.
    @ViewBuilder var controls: some View {
        HStack(spacing: 8) {
            if (isResting || isPaused), let restID = state.restID {
                Button(intent: ToggleRestTimerIntent(sessionID: state.sessionID, restID: restID)) {
                    Label(isPaused ? state.labels.resume : state.labels.pause,
                          systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                Button(intent: AddRestTimeIntent(sessionID: state.sessionID, restID: restID, seconds: 15)) {
                    Text(state.labels.addTime)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                Button(intent: SkipRestTimerIntent(sessionID: state.sessionID, restID: restID)) {
                    Label(state.labels.skip, systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
            } else if state.phase == .done {
                Label(state.labels.workoutDone, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Palette.success)
                    .frame(maxWidth: .infinity)
            } else if state.canCompleteSet, let exerciseID = state.exerciseID, let setID = state.setID {
                Button(intent: CompleteWorkoutSetIntent(sessionID: state.sessionID, exerciseID: exerciseID, setID: setID)) {
                    Label(state.labels.completeSet, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.success)
            } else {
                Text(state.labels.openToContinue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
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

    /// The system gives this banner at most 160 points of height and cuts
    /// off whatever does not fit, top and bottom alike. The earlier layout
    /// needed about 190 -- a header, four lines, the bar, the buttons and a
    /// "next" line -- so the header sat on the banner's edge and the buttons
    /// were sliced through. This one needs about 150 with the margins the
    /// system's own banners use, and text is held at the default size so a
    /// larger setting cannot push it back over.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .center, spacing: 12) {
                details
                Spacer(minLength: 8)
                figure
            }

            view.progress
                .padding(.bottom, 2)

            view.controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "dumbbell.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.accent)
            Text(context.attributes.workoutName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(context.attributes.startedAt, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: 56, alignment: .leading)
            Spacer(minLength: 4)
            Text(state.progressText)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Three lines: the exercise; the set with what it aims at; and last
    /// time's numbers, or what comes next when there are none.
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.exerciseName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                if let badge = state.setBadge {
                    Text(badge)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(state.setTitle)
                    .font(.footnote.weight(.medium))
                if let target = state.targetText {
                    Text(verbatim: "·")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(target)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.accent)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            if let line = state.previousText ?? (view.isResting || view.isPaused ? nil : state.nextText) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var figure: some View {
        VStack(alignment: .trailing, spacing: 0) {
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
                .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(view.isResting ? Palette.accent : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 112, alignment: .trailing)
        }
    }
}
