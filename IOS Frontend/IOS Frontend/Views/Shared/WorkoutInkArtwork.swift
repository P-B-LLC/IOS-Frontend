import SwiftUI

/// The centralized semantic activity icon set.
///
/// Artwork is extracted from the approved reference sheet committed under
/// `DesignReferences/activity-icon-reference.png`. Keeping semantic names here
/// prevents individual features from drifting back to unrelated SF Symbols.
enum ActivityIconKind: String, CaseIterable, Sendable {
    case lifting
    case running
    case biking
    case swimming
    case treadmill
    case stationaryBike
    case stairMaster
    case elliptical
    case rower
    case assaultBike
    case skiErg
    case otherCardio
    case cardio
    case runningShoe
    case bikeGear

    var assetName: String {
        switch self {
        case .lifting: "ActivityLifting"
        case .running: "ActivityRunning"
        case .biking: "ActivityBiking"
        case .swimming: "ActivitySwimming"
        case .treadmill: "ActivityTreadmill"
        case .stationaryBike: "ActivityStationaryBike"
        case .stairMaster: "ActivityStairMaster"
        case .elliptical: "ActivityElliptical"
        case .rower: "ActivityRower"
        case .assaultBike: "ActivityAssaultBike"
        case .skiErg: "ActivitySkiErg"
        case .otherCardio: "ActivityOtherCardio"
        case .cardio: "ActivityCardio"
        case .runningShoe: "RepbaseSpeedSole"
        case .bikeGear: "ActivityBikeGear"
        }
    }
}

struct ActivityIconArtwork: View {
    let kind: ActivityIconKind
    var size: CGFloat = 24
    var color: Color = RepbaseDesign.ink

    @ViewBuilder
    var body: some View {
        if kind == .swimming {
            // The extracted artwork read as a person reclining rather than a
            // swimmer at selector size. This system glyph keeps the pool and
            // swimming stroke visible even in the compact workout picker.
            Image(systemName: "figure.pool.swim")
                .font(.system(size: size * 0.82, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(kind.assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
                // The reference-sheet exports contain generous transparent
                // margins. Compensate visually while retaining the original
                // layout frame and tap target.
                .scaleEffect(1.65)
                .accessibilityHidden(true)
        }
    }
}

extension WorkoutType {
    var activityIcon: ActivityIconKind {
        switch self {
        case .lifting: .lifting
        case .running: .running
        case .biking: .biking
        case .swimming: .swimming
        }
    }
}

extension CardioMachine {
    var activityIcon: ActivityIconKind {
        switch self {
        case .treadmill: .treadmill
        case .stationaryBike: .stationaryBike
        case .stairMaster: .stairMaster
        case .elliptical: .elliptical
        case .rowingMachine: .rower
        case .assaultBike: .assaultBike
        case .skiErg: .skiErg
        case .other: .otherCardio
        }
    }
}

extension GearKind {
    var activityIcon: ActivityIconKind {
        switch self {
        case .shoe: .runningShoe
        case .bike: .bikeGear
        }
    }
}

/// Compatibility wrapper retained for existing workout-artwork call sites.
/// The former hand-drawn Canvas figures are intentionally gone.
struct WorkoutInkArtwork: View {
    let type: WorkoutType
    var size: CGFloat = 48
    var color: Color = RepbaseDesign.ink

    var body: some View {
        ActivityIconArtwork(kind: type.activityIcon, size: size, color: color)
    }
}
