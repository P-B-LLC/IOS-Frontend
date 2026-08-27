import SwiftUI

/// The centralized semantic activity icon set.
///
/// The approved activity system uses native SF Symbols so every mark stays
/// crisp at compact, card, and hero sizes while inheriting the surrounding
/// light- or dark-mode color.
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

    var systemName: String {
        switch self {
        case .lifting: "figure.strengthtraining.traditional"
        case .running: "figure.run"
        case .biking: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .treadmill: "figure.run.treadmill"
        case .stationaryBike: "figure.indoor.cycle"
        case .stairMaster: "figure.stair.stepper"
        case .elliptical: "figure.elliptical"
        case .rower: "figure.indoor.rowing"
        case .assaultBike: "figure.highintensity.intervaltraining"
        case .skiErg: "figure.skiing.crosscountry"
        case .otherCardio: "figure.mixed.cardio"
        case .cardio: "waveform.path.ecg"
        case .runningShoe: "shoe.2.fill"
        case .bikeGear: "bicycle"
        }
    }

    /// Figure symbols carry different visual bounds. These small optical
    /// corrections make them feel like one family without raster scaling.
    func pointSize(in frameSize: CGFloat) -> CGFloat {
        switch self {
        case .runningShoe, .bikeGear:
            frameSize * 0.72
        case .swimming, .rower, .cardio:
            frameSize * 0.78
        default:
            frameSize * 0.84
        }
    }
}

struct ActivityIconArtwork: View {
    let kind: ActivityIconKind
    var size: CGFloat = 24
    var color: Color = RepbaseDesign.ink

    var body: some View {
        Image(systemName: kind.systemName)
            .font(.system(size: kind.pointSize(in: size), weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
