import SwiftUI

/// Presentation shared only by the five reviewed Sunrise pages.
enum RytivoSunriseDesign {
    static let surface = RepbaseTactileDesign.surface
    static let ink = RepbaseTactileDesign.ink
    static let secondary = RepbaseTactileDesign.secondaryText
    static let border = RepbaseTactileDesign.border
    static let sage = RepbaseTactileDesign.success
    static let sageTint = RepbaseTactileDesign.successTint
}

struct RytivoSunriseCard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var tint: Color = HomeSunriseStyle.heroTint
    var radius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [RytivoSunriseDesign.surface, tint],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(contrast == .increased ? RytivoSunriseDesign.secondary
                                  : RytivoSunriseDesign.border, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.035), radius: 6, y: 3)
            .allowsHitTesting(false)
    }
}

/// All subcategories use the approved image for their existing sport group.
/// Custom/unknown sports keep a neutral backdrop rather than implying a sport.
enum TrainingPhoto {
    static func asset(for activity: WorkoutActivity?) -> String? {
        guard let activity else { return nil }
        switch activity.category {
        case .strength: return "TrainingStrength"
        case .cardio: return "TrainingCardio"
        case .racket: return "TrainingRacket"
        case .team: return "TrainingTeam"
        case .combat: return "TrainingCombat"
        case .mindBody: return "TrainingMindBody"
        case .outdoors: return "TrainingOutdoors"
        case .other: return nil
        }
    }
}

struct RytivoPhotoBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    let asset: String?
    var radius: CGFloat = 24
    /// Home's focus cards expose more of the photo. Other existing call sites
    /// keep their original readability treatment until separately reviewed.
    var emphasizesPhoto = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: 0x292D29)
                if let asset {
                    Image(asset).resizable().interpolation(.high).scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                photoScrim
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var photoScrim: LinearGradient {
        guard emphasizesPhoto, asset != nil else {
            return LinearGradient(colors: [.black.opacity(0.60), .black.opacity(0.78)],
                                  startPoint: .top, endPoint: .bottom)
        }
        // Protect the small top label and the lower text/actions, leaving a
        // brighter window across the photograph instead of dimming it evenly.
        // Extra-large text may occupy that window, so use the stronger scrim.
        let stronger = contrast == .increased || typeSize.isAccessibilitySize
        return LinearGradient(stops: [
            .init(color: .black.opacity(stronger ? 0.68 : 0.56), location: 0),
            .init(color: .black.opacity(stronger ? 0.68 : 0.56), location: 0.18),
            .init(color: .black.opacity(stronger ? 0.60 : 0.24), location: 0.32),
            .init(color: .black.opacity(stronger ? 0.68 : 0.54), location: 0.48),
            .init(color: .black.opacity(stronger ? 0.80 : 0.68), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    func sunriseCard(tint: Color = HomeSunriseStyle.heroTint, radius: CGFloat = 24) -> some View {
        background(RytivoSunriseCard(tint: tint, radius: radius))
    }
}
