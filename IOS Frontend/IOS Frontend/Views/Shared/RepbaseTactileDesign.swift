import SwiftUI

/// Opt-in tokens for the approved layered Home. Other screens adopt these
/// after their own Figma review; existing app-wide colors remain unchanged.
enum RepbaseTactileDesign {
    static let pageInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 32
    static let cardRadius: CGFloat = 28
    static let sheetOverlap: CGFloat = 24

    static let surface = Color("TactileSurface")
    static let cardTint = Color("TactileCardTint")
    static let weekBackdrop = Color("TactileWeekBackdrop")
    static let ink = Color("TactileInk")
    static let secondaryText = Color("TactileSecondaryText")
    static let border = Color("TactileBorder")
    static let accent = Color("TactileAccent")
    static let accentText = Color("TactileAccentText")
    static let success = Color("TactileSuccess")
    static let successTint = Color("TactileSuccessTint")
}

enum RepbaseTactileTone {
    case warm, movement
}

struct RepbaseTactileCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityContrast) private var contrast
    var tone: RepbaseTactileTone = .warm
    var cornerRadius: CGFloat = RepbaseTactileDesign.cardRadius

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(LinearGradient(
                colors: [RepbaseTactileDesign.surface,
                         tone == .movement ? RepbaseTactileDesign.successTint : RepbaseTactileDesign.cardTint],
                startPoint: .top, endPoint: .bottom
            ))
            // Only the background shape casts shadows, not a rasterized copy
            // of every label, image and progress update in the card.
            .shadow(color: RepbasePalette.ink.opacity(colorScheme == .dark ? 0.40 : 0.11),
                    radius: 11, x: 0, y: 9)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.07),
                    radius: 2, x: 0, y: 1)
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? RepbaseTactileDesign.secondaryText
                        : (colorScheme == .dark ? RepbaseTactileDesign.border : Color.white.opacity(0.82)),
                    lineWidth: 1
                )
            }
            .allowsHitTesting(false)
    }
}

struct RepbaseTactileSheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: RepbaseTactileDesign.cardRadius,
            bottomLeadingRadius: 0, bottomTrailingRadius: 0,
            topTrailingRadius: RepbaseTactileDesign.cardRadius,
            style: .continuous
        )
        .fill(RepbaseTactileDesign.surface)
        .shadow(color: RepbasePalette.ink.opacity(colorScheme == .dark ? 0.40 : 0.13),
                radius: 9, x: 0, y: -6)
        .allowsHitTesting(false)
    }
}

enum RepbaseTactileActionTone {
    case accent, neutral
}

struct RepbaseTactileControlBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityContrast) private var contrast
    var tone: RepbaseTactileActionTone = .neutral
    var cornerRadius: CGFloat = 100

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(tone == .accent ? RepbaseTactileDesign.accent : RepbaseTactileDesign.surface)
            .overlay {
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.26), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? RepbaseTactileDesign.secondaryText
                        : (colorScheme == .dark ? RepbaseTactileDesign.border : Color.white.opacity(0.8)),
                    lineWidth: 1
                )
            }
            .shadow(color: RepbasePalette.ink.opacity(colorScheme == .dark ? 0.65 : 0.14),
                    radius: 0, x: 0, y: 3)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.08),
                    radius: 2, x: 0, y: 1)
            .allowsHitTesting(false)
    }
}

/// A label, not a nested button: Next up keeps its existing whole-card action.
struct RepbaseTactileActionLabel: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let title: LocalizedStringKey
    var tone: RepbaseTactileActionTone = .neutral

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.community(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "arrow.right")
                .font(.system(size: 18))
                .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
                .accessibilityHidden(true)
        }
        .foregroundStyle(tone == .accent ? RepbasePalette.ink : RepbaseTactileDesign.ink)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(RepbaseTactileControlBackground(tone: tone))
        .contentShape(Capsule())
    }
}

struct RepbaseTactilePressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.87 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RepbaseTactileProgressTrack: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 10

    private var fraction: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(RepbaseTactileDesign.border)
                    .overlay {
                        Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                            .clipShape(Capsule())
                    }
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.76), tint],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: max(0, proxy.size.width) * fraction)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct RepbaseTactileProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [RepbaseTactileDesign.surface, RepbaseTactileDesign.successTint],
                startPoint: .top, endPoint: .bottom
            ))
            Circle().strokeBorder(RepbaseTactileDesign.border, lineWidth: 1)
            Circle().stroke(RepbaseTactileDesign.border.opacity(0.65), lineWidth: 4)
                .padding(5)
            Circle()
                .trim(from: 0, to: progress.isFinite ? min(max(progress, 0), 1) : 0)
                .stroke(LinearGradient(colors: [RepbasePalette.sage, RepbaseTactileDesign.success],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(5)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

extension View {
    func repbaseTactileCard(tone: RepbaseTactileTone = .warm) -> some View {
        background(RepbaseTactileCardBackground(tone: tone))
    }
}
