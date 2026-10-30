//
//  WorkoutUnitControls.swift
//  IOS Frontend
//
//  The kg/lb switch and the rest-length menu, shared by every workout screen.
//

import SwiftUI

/// A two-position kg | lb switch.
///
/// Tapping changes what this and every other workout screen shows, at once
/// and without leaving the screen; the account's default is left alone, so
/// the next session opens in it again. Holding it offers to make the choice
/// the default instead. Only the display changes: stored weights stay in
/// kilograms, so switching back and forth never moves a recorded number.
struct WeightUnitToggle: View {
    @Environment(WorkoutStore.self) private var store
    var compact = false

    private var preferences: WorkoutPreferences { store.preferences }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkoutWeightUnit.allCases) { unit in
                let selected = preferences.weightUnit == unit
                Button {
                    withAnimation(.snappy(duration: 0.2)) { preferences.useTemporarily(unit) }
                } label: {
                    Text(unit.label)
                        .font(.community(compact ? .caption2 : .caption, weight: .bold))
                        .foregroundStyle(selected ? WorkoutVisualPhase.focus.onPrimaryAction : WorkoutVisualPhase.focus.secondaryText)
                        .padding(.horizontal, compact ? 8 : 11)
                        .frame(minHeight: compact ? 26 : 30)
                        .background {
                            if selected {
                                Capsule().fill(WorkoutVisualPhase.focus.primaryActionSurface)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unit.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(WorkoutVisualPhase.focus.cardBorder.opacity(0.55), in: Capsule())
        // A 44-point target around a smaller drawn control.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .sensoryFeedback(.selection, trigger: preferences.weightUnit)
        .contextMenu {
            ForEach(WorkoutWeightUnit.allCases) { unit in
                Button {
                    Task { await preferences.makeDefault(unit, using: store) }
                } label: {
                    Label(
                        unit == .metric ? "Make kilograms my default" : "Make pounds my default",
                        systemImage: preferences.defaultWeightUnit == unit ? "checkmark" : "scalemass"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight unit")
        .accessibilityHint("Changes how weights are shown. Your recorded weights do not change.")
    }
}

/// Picks how long to rest after each set: the default, off, or a length.
struct RestDurationMenu<Label: View>: View {
    /// Nil means "use the default".
    let selection: Int?
    let defaultSeconds: Int
    var allowsDefault = true
    let onSelect: (Int?) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if allowsDefault {
                Button {
                    onSelect(nil)
                } label: {
                    if selection == nil {
                        SwiftUI.Label("Default (\(RestDurationOptions.label(defaultSeconds)))", systemImage: "checkmark")
                    } else {
                        Text("Default (\(RestDurationOptions.label(defaultSeconds)))")
                    }
                }
                Divider()
            }
            ForEach(RestDurationOptions.seconds, id: \.self) { seconds in
                Button {
                    onSelect(seconds)
                } label: {
                    if selection == seconds {
                        SwiftUI.Label(RestDurationOptions.label(seconds), systemImage: "checkmark")
                    } else {
                        Text(RestDurationOptions.label(seconds))
                    }
                }
            }
        } label: {
            label()
        }
    }
}

/// "Rest 1:30" with a timer glyph, for a card or a row.
struct RestChip: View {
    let seconds: Int?
    let defaultSeconds: Int
    var phase: WorkoutVisualPhase = .focus

    private var effective: Int { seconds ?? defaultSeconds }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: effective > 0 ? "timer" : "timer.slash")
                .font(.community(.caption2, weight: .semibold))
            Text(effective > 0 ? "Rest \(RestDurationOptions.label(effective))" : "No rest timer")
                .font(.community(.caption, weight: .semibold))
                .monospacedDigit()
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(seconds == nil ? phase.secondaryText : phase.accent)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(phase.accent.opacity(seconds == nil ? 0.06 : 0.12), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effective > 0 ? "Rest after each set, \(RestDurationOptions.label(effective))" : "No rest timer")
        .accessibilityHint("Changes how long to rest after each set")
    }
}

/// The colour that marks one superset, so the exercises in it read as a
/// group and two supersets in one workout are never confused.
enum SupersetPalette {
    static func color(for group: Int) -> Color {
        let colors: [Color] = [
            RepbasePalette.caramel,
            Color(hex: 0x4F7CAC),
            RepbasePalette.sage,
            Color(hex: 0x9A6FB0),
            Color(hex: 0xC4A23A)
        ]
        return colors[(max(group, 1) - 1) % colors.count]
    }
}

/// The badge in a set row's first column, coloured by what the set is for.
struct SetTypeBadge: View {
    let type: WorkoutSetType
    let label: String
    var isCurrent = false
    var isLogged = false

    static func tint(for type: WorkoutSetType) -> Color {
        switch type {
        case .normal: return Color.primary
        case .warmup: return Color(hex: 0xC4A23A)
        case .drop: return Color(hex: 0x4F7CAC)
        case .failure: return RepbaseDesign.danger
        }
    }

    var body: some View {
        Text(label)
            .font(.community(.subheadline, weight: .bold).monospacedDigit())
            .foregroundStyle(type == .normal ? (isLogged ? RepbaseDesign.success : Color.primary) : Self.tint(for: type))
            .frame(width: 34, height: 30)
            .background(
                (type == .normal ? Color.primary.opacity(isCurrent ? 0.08 : 0.04) : Self.tint(for: type).opacity(0.14)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
