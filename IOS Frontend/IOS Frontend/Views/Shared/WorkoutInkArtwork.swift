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

    var body: some View {
        Image(type.inkArtworkAsset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .accessibilityHidden(true)
    }
}
