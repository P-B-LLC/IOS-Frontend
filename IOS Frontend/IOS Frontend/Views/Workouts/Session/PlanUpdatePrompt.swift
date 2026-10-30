//
//  PlanUpdatePrompt.swift
//  IOS Frontend
//
//  Asked at Finish, only when the session was reshaped: keep the changes for
//  next time, or only for today?
//

import SwiftUI

/// Whether a reshaped session should become the saved workout's plan.
///
/// Both answers save today's workout exactly as it was trained; the question
/// is only about the plan. Each option says what it does to next time, and the
/// changes are listed, because "update routine?" on its own is the question
/// people learn to dismiss and then regret.
struct PlanUpdatePrompt: View {
    let workoutName: String
    let changes: [WorkoutStructureChange]
    let onUpdate: () -> Void
    let onKeep: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let phase = WorkoutVisualPhase.focus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(phase.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keep today’s changes for next time?")
                        .font(.community(.title2, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You changed “\(workoutName)” during this workout:")
                        .font(.community(.subheadline))
                        .foregroundStyle(phase.secondaryText)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(Self.descriptions(changes).prefix(6).enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.community(.subheadline))
                    }
                    if Self.descriptions(changes).count > 6 {
                        Text("and \(Self.descriptions(changes).count - 6) more changes")
                            .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                    }
                }

                VStack(spacing: 10) {
                    option(
                        title: "Update saved workout",
                        detail: "Next time, \(workoutName) opens with today’s exercises, order, sets and rests.",
                        prominent: true,
                        action: { dismiss(); onUpdate() }
                    )
                    option(
                        title: "Only this workout",
                        detail: "Today is saved as you trained it. \(workoutName) stays as it was.",
                        prominent: false,
                        action: { dismiss(); onKeep() }
                    )
                }
                Button("Keep training") { dismiss() }
                    .font(.community(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                Text("Either way, the weights and reps you logged are saved to your history.")
                    .font(.community(.caption))
                    .foregroundStyle(phase.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func option(title: LocalizedStringKey, detail: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.community(.headline))
                Text(detail)
                    .font(.community(.caption))
                    .opacity(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .foregroundStyle(prominent ? phase.onPrimaryAction : phase.primaryText)
            .background(
                prominent ? phase.primaryActionSurface : phase.cardBorder.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    /// One plain sentence per change, merged so a reorder is said once.
    static func descriptions(_ changes: [WorkoutStructureChange]) -> [String] {
        var lines: [String] = []
        for change in changes {
            let line: String
            switch change {
            case .added(let name): line = String(localized: "Added \(name)", bundle: .app, locale: .app, comment: "A change to a workout: an exercise was added")
            case .removed(let name): line = String(localized: "Removed \(name)", bundle: .app, locale: .app, comment: "A change to a workout: an exercise was removed")
            case .reordered: line = String(localized: "Changed the order of exercises", bundle: .app, locale: .app)
            case .sets(let name): line = String(localized: "Changed the number of sets for \(name)", bundle: .app, locale: .app)
            case .setTypes(let name): line = String(localized: "Changed set kinds for \(name)", bundle: .app, locale: .app, comment: "Set kinds are warm-up, drop, failure and normal sets")
            case .rest(let name): line = String(localized: "Changed the rest for \(name)", bundle: .app, locale: .app)
            case .superset(let name): line = String(localized: "Changed the superset for \(name)", bundle: .app, locale: .app)
            }
            if !lines.contains(line) { lines.append(line) }
        }
        return lines
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(WorkoutVisualPhase.focus.accent)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
