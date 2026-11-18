import SwiftUI

/// Approved Sunrise colors, shared by the five reviewed main pages.
/// Asset variants resolve with the existing appearance preference.
enum HomeSunriseStyle {
    static let backdrop = Color("SunriseBackdrop")
    static let heroTint = Color("SunriseHeroTint")
    static let workoutTint = Color("SunriseWorkoutTint")
    static let datumTint = Color("SunriseDatumTint")
    static let datumBase = Color("SunriseDatumBase")

    static var backdropGradient: LinearGradient {
        LinearGradient(colors: [backdrop, heroTint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct HomeSunriseGlow: View {
    var body: some View {
        // Exact 160 × 160 light/dark exports from the approved Figma layer.
        Image("HomeSunriseGlow")
            .renderingMode(.original)
            .frame(width: 160, height: 160)
            // SwiftUI mirrors horizontal offsets in a right-to-left layout.
            // Together with topTrailing alignment this stays off the edge.
            .offset(x: 48)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct HomeSunriseWeekBackground: View {
    var body: some View {
        RepbaseTactileCardBackground(cornerRadius: 24, tint: HomeSunriseStyle.heroTint)
    }
}

struct HomeSunriseCardBackground: View {
    var isWorkout = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RepbaseTactileDesign.cardRadius, style: .continuous)
                .fill(HomeSunriseStyle.datumTint)
                .padding(.horizontal, 6)
                .offset(y: 8)
            RepbaseTactileCardBackground(
                tint: isWorkout ? HomeSunriseStyle.workoutTint : HomeSunriseStyle.heroTint
            )
        }
        .allowsHitTesting(false)
    }
}

struct HomeSunriseTimeBadge: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let displayTime: String?

    private var fullTime: String {
        displayTime ?? String(localized: "No time set", bundle: .app, locale: .app)
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            Text(fullTime)
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(RepbaseTactileDesign.accentText)
        } else {
            face
                .frame(width: 76, height: 68)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                    ZStack {
                        shape.fill(HomeSunriseStyle.datumBase).offset(y: 4)
                        shape.fill(LinearGradient(
                            colors: [RepbaseTactileDesign.surface, HomeSunriseStyle.datumTint],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay {
                            shape.strokeBorder(contrast == .increased
                                ? RepbaseTactileDesign.secondaryText
                                : (colorScheme == .dark ? RepbaseTactileDesign.border : Color.white), lineWidth: 1)
                        }
                        .shadow(color: RepbasePalette.ink.opacity(0.11), radius: 11, x: 0, y: 9)
                    }
                }
                .padding(.bottom, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fullTime))
        }
    }

    private var face: some View {
        let parts = HomeSunriseClockParts(fullTime, locale: .app)
        return VStack(spacing: 0) {
            Text(parts.clock)
                .font(.community(size: displayTime == nil ? 13 : 24,
                                 weight: displayTime == nil ? .semibold : .bold))
                .foregroundStyle(RepbaseTactileDesign.ink)
                .lineLimit(displayTime == nil ? 3 : 1)
                .minimumScaleFactor(0.7)
            if let period = parts.period {
                Text(period)
                    .font(.community(size: 13, weight: .semibold))
                    .foregroundStyle(RepbaseTactileDesign.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 4)
    }
}

struct HomeSunriseExerciseBadge: View {
    let count: Int

    var body: some View {
        ZStack {
            // Keep the SVGs' original root sizes. The face's exported shadow
            // extends 22 pt horizontally and 13 pt above its 88 × 84 face.
            Image("HomeSunriseCountBase").renderingMode(.original)
                .frame(width: 88, height: 84).offset(y: 2)
            Image("HomeSunriseCountFace").renderingMode(.original)
                .frame(width: 132, height: 128).offset(y: 7)
            VStack(spacing: 0) {
                Text(count.formatted(.number.locale(.app)))
                    .font(.community(size: 34, weight: .bold))
                    .foregroundStyle(RepbaseTactileDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(count == 1 ? LocalizedStringKey("exercise") : LocalizedStringKey("exercises"))
                    .font(.community(size: 13, weight: .semibold))
                    .foregroundStyle(RepbaseTactileDesign.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 88, height: 84)
            .offset(y: -2)
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) exercises"))
    }
}
