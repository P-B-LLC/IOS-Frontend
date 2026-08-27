import CoreGraphics

/// The shape a posted photo is drawn at.
///
/// Every surface that shows one asks here, because the two that existed
/// disagreed: the feed card forced a 176pt band and the composer preview
/// forced 190pt, so the crop somebody approved before posting was not the
/// crop anybody else saw. Both threw the photo's own shape away entirely --
/// a portrait plate of food arrived as a letterboxed strip through its
/// middle.
///
/// The ratio is clamped rather than taken as given. Unbounded, a panorama
/// draws as a sliver and a screenshot of a phone screen pushes the post
/// under it off the bottom of the display. The bounds are the ones photo
/// feeds have settled on: 4:5 upright, 16:9 wide.
enum PostPhotoRatio {
    /// Tallest allowed, as width over height.
    static let narrowest: CGFloat = 4.0 / 5.0
    /// Widest allowed, as width over height.
    static let widest: CGFloat = 16.0 / 9.0

    /// What to reserve before the photo has loaded.
    ///
    /// A guess, and it has to be: no dimensions reach the app before the
    /// image data does. Sitting between the two bounds keeps the settle to
    /// the smallest movement available in either direction.
    static let unloaded: CGFloat = 4.0 / 3.0

    /// `size` as a drawable ratio, or `unloaded` if it says nothing useful.
    static func clamped(_ size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return unloaded }
        return clamped(size.width / size.height)
    }

    static func clamped(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return unloaded }
        return min(max(ratio, narrowest), widest)
    }
}
