import CoreGraphics

/// A shape the cropper can cut to.
///
/// Every fixed one is a member of `PostPhotoRatio.allowed`, so what comes out
/// of the cropper is drawn at exactly the shape it was framed at rather than
/// snapped to something near it. `original` resolves to the nearest allowed
/// shape for that photo, which is what the app did before there was a choice.
enum PhotoCropShape: String, CaseIterable, Identifiable {
    case original
    case square
    case portrait
    case landscape
    case wide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "Original"
        case .square: "1:1"
        case .portrait: "4:5"
        case .landscape: "4:3"
        case .wide: "16:9"
        }
    }

    /// Width over height, or nil for "whatever the photo already is".
    var fixedRatio: CGFloat? {
        switch self {
        case .original: nil
        case .square: 1
        case .portrait: 4.0 / 5.0
        case .landscape: 4.0 / 3.0
        case .wide: 16.0 / 9.0
        }
    }

    /// The shape to cut this particular photo to.
    func ratio(for imagePixels: CGSize) -> CGFloat {
        fixedRatio ?? PostPhotoRatio.clamped(imagePixels)
    }
}

/// The arithmetic behind framing a photo, kept apart from the view.
///
/// Separated so it can be exercised. There is no XCTest target in this
/// project, and a crop that is subtly wrong is not something a screenshot
/// reliably shows -- an off-by-a-factor lands a plausible-looking picture of
/// the wrong part of the photo.
///
/// Everything here is in the photo's own pixels, and assumes an upright copy:
/// a photo from the library usually carries its rotation as an orientation
/// flag rather than in the pixels, and `CGImage.cropping` knows nothing about
/// that flag.
struct PhotoCropGeometry {
    /// The photo's pixels, rotation already applied.
    let imagePixels: CGSize
    /// The crop window on screen, in points.
    let cropPoints: CGSize

    /// Points per image pixel at zoom 1.
    ///
    /// `scaledToFill` covers the window, so this is whichever axis needs the
    /// most magnification. The square-only version this came from took it
    /// from the photo's shorter edge, which is the same number while the
    /// window is square and wrong the moment it is not -- a 16:9 window over
    /// an upright photo would have been left with a gap down both sides.
    var baseFactor: CGFloat {
        guard imagePixels.width > 0, imagePixels.height > 0 else { return 1 }
        return max(
            cropPoints.width / imagePixels.width,
            cropPoints.height / imagePixels.height
        )
    }

    func factor(at scale: CGFloat) -> CGFloat { baseFactor * scale }

    /// How large the photo is drawn at this zoom, in points.
    func displayedSize(at scale: CGFloat) -> CGSize {
        let f = factor(at: scale)
        return CGSize(width: imagePixels.width * f, height: imagePixels.height * f)
    }

    /// Keeps the photo covering the window.
    ///
    /// Without it the picture can be dragged clear of the crop entirely and
    /// the result is part photo, part nothing.
    func clampedOffset(_ proposed: CGSize, at scale: CGFloat) -> CGSize {
        let shown = displayedSize(at: scale)
        let limitX = max((shown.width - cropPoints.width) / 2, 0)
        let limitY = max((shown.height - cropPoints.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    /// The rectangle to cut, in the photo's own pixels.
    ///
    /// The window sits at the centre of the view; the photo's centre sits at
    /// that same point plus the offset. So the window's top-left, measured
    /// from the photo's top-left, is this -- in points, then divided back
    /// into pixels.
    ///
    /// Intersected with the photo rather than trusted: rounding at the edges
    /// of a clamped drag can put the rect a fraction outside, and `cropping`
    /// answers nil for a rect not wholly inside rather than clipping it.
    func cropRect(at scale: CGFloat, offset: CGSize) -> CGRect {
        let f = factor(at: scale)
        guard f > 0 else { return .zero }
        let shown = displayedSize(at: scale)
        return CGRect(
            x: (shown.width / 2 - cropPoints.width / 2 - offset.width) / f,
            y: (shown.height / 2 - cropPoints.height / 2 - offset.height) / f,
            width: cropPoints.width / f,
            height: cropPoints.height / f
        )
        .integral
        .intersection(CGRect(origin: .zero, size: imagePixels))
    }

    /// The largest window of `ratio` that fits inside `available`.
    ///
    /// The two insets differ because what they make room for differs. Across,
    /// it is only a margin. Down, it is the title, the shape chips, the hint
    /// and the button -- so insetting both by the same amount, as the first
    /// version did, left the window using barely half the width it could have
    /// on a screen with plenty to spare.
    static func cropWindow(
        ratio: CGFloat,
        in available: CGSize,
        horizontalInset: CGFloat,
        verticalInset: CGFloat
    ) -> CGSize {
        let widest = max(available.width - horizontalInset, 80)
        let tallest = max(available.height - verticalInset, 80)
        guard ratio > 0, ratio.isFinite else {
            return CGSize(width: widest, height: widest)
        }
        // As wide as it may be, unless that makes it too tall.
        let byWidth = CGSize(width: widest, height: widest / ratio)
        if byWidth.height <= tallest { return byWidth }
        return CGSize(width: tallest * ratio, height: tallest)
    }
}
