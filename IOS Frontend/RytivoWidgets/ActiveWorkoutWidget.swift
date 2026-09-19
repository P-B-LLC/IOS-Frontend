import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

struct ActiveWorkoutEntry: TimelineEntry {
    var date: Date
    var state: ActiveWorkoutWidgetState?
}

struct ActiveWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveWorkoutEntry { .init(date: .now, state: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ActiveWorkoutEntry) -> Void) {
        completion(.init(date: .now, state: ActiveWorkoutWidgetState.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveWorkoutEntry>) -> Void) {
        let now = Date()
        let state = ActiveWorkoutWidgetState.read()
        var entries = [ActiveWorkoutEntry(date: now, state: state)]
        if let state {
            let expiry = min(state.updatedAt.addingTimeInterval(3600), state.startedAt.addingTimeInterval(8 * 3600))
            if expiry > now { entries.append(.init(date: expiry, state: nil)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}

struct WorkoutControlView: View {
    let state: ActiveWorkoutWidgetState
    var stale = false
    private var blocked: Bool { stale || state.busy || state.finished }
    private func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "NunitoSans-Bold" : "NunitoSans-Regular", size: size)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(state.workout, systemImage: "dumbbell.fill").lineLimit(1)
                Spacer(minLength: 4)
                Text(state.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 80, alignment: .trailing)
            }.font(font(12, bold: true)).foregroundStyle(.orange)
            HStack {
                Text(state.exercise).font(font(15, bold: true)).lineLimit(1)
                Spacer(minLength: 4)
                Text(state.finished ? "\(state.logged)/\(state.total) sets" : "Set \(state.setNumber)/\(state.setCount)")
                    .font(font(10)).foregroundStyle(.secondary)
            }
            if state.finished || stale {
                Link(stale ? "Open Rytivo to refresh" : "Review & finish in Rytivo",
                     destination: URL(string: "rytivo://widget/activeWorkout")!)
                    .font(font(14, bold: true)).padding(.vertical, 12)
            } else {
                HStack(spacing: 8) {
                    adjustment(title: "kg", value: state.weight.isEmpty ? "—" : state.weight,
                               down: "weightDown", up: "weightUp", label: "weight")
                    adjustment(title: "reps", value: state.reps.isEmpty ? "—" : state.reps,
                               down: "repsDown", up: "repsUp", label: "repetitions")
                }
                HStack(spacing: 8) {
                    Link("Edit in app", destination: URL(string: "rytivo://widget/activeWorkout")!)
                        .font(font(11)).frame(minHeight: 44)
                    Spacer(minLength: 0)
                    Button(intent: WorkoutWidgetAction(revision: state.revision, action: "log")) {
                        Text(state.busy ? "Saving…" : "Log set")
                            .font(font(13, bold: true)).frame(minWidth: 100, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.orange.opacity(state.busy ? 0.5 : 1), in: Capsule())
                    .disabled(blocked)
                }
            }
            if let message = state.message {
                Text(message).font(font(10)).foregroundStyle(.red).lineLimit(2)
            }
        }
        .foregroundStyle(.primary)
        .privacySensitive()
    }
    private func adjustment(title: String, value: String, down: String, up: String, label: String) -> some View {
        HStack(spacing: 0) {
            control("minus", action: down, label: "Decrease \(label)")
            VStack(spacing: 0) {
                Text(value).font(font(14, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(font(9)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            control("plus", action: up, label: "Increase \(label)")
        }
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private func control(_ symbol: String, action: String, label: String) -> some View {
        Button(intent: WorkoutWidgetAction(revision: state.revision, action: action)) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(blocked).accessibilityLabel(label)
    }
}

struct ActiveWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.pbllc.rytivo.activeWorkout", provider: ActiveWorkoutProvider()) { entry in
            Group {
                if let state = entry.state {
                    WorkoutControlView(state: state)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("ACTIVE WORKOUT", systemImage: "dumbbell.fill").foregroundStyle(.orange)
                        Text("Your next set starts here.").bold()
                        Text("Open Rytivo to start or resume a lifting session.").foregroundStyle(.secondary)
                    }.font(.custom("NunitoSans-Regular", size: 13))
                }
            }
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "rytivo://widget/activeWorkout"))
        }
        .configurationDisplayName("Active workout")
        .description("Adjust kg and reps, log your current set, and follow your workout timer.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutControlView(state: context.state, stale: context.isStale)
                .padding(12)
                .widgetURL(URL(string: "rytivo://widget/activeWorkout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutControlView(state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer).monospacedDigit().frame(width: 55)
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
            .widgetURL(URL(string: "rytivo://widget/activeWorkout"))
        }
    }
}
