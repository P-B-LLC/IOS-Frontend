import SwiftUI

extension WorkoutType {
    var inkArtworkAsset: String {
        switch self {
        case .lifting: "WorkoutInkLifting"
        case .running: "WorkoutInkRunning"
        case .biking: "WorkoutInkBiking"
        case .swimming: "WorkoutInkSwimming"
        }
    }
}

struct WorkoutInkArtwork: View {
    let type: WorkoutType
    var size: CGFloat = 48
    var color: Color = RepbaseDesign.ink

    var body: some View {
        Image(type.inkArtworkAsset)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
