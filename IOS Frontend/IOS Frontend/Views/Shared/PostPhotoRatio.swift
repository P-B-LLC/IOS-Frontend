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
/// A photo is drawn at the nearest of a fixed set of shapes rather than at
/// whatever it happens to be. Two reasons. Unbounded, a panorama draws as a
/// sliver and a screenshot of a phone screen pushes the post under it off the
/// bottom of the display. And a feed of arbitrary shapes reads as untidy in a
/// way that is hard to name and easy to see -- every card starting at a
/// different offset from the one above it.
///
/// The set is the standard camera and phone shapes in both orientations, so
/// in practice a photo snaps to itself and nothing is cropped. Every photo in
/// the database on the day this was written -- 3:4, 4:3 and 3:2 -- lands
/// exactly on a member of it.
enum PostPhotoRatio {
    /// Every shape a photo may be drawn at, tallest first, as width / height.
    ///
    /// Bounded at 3:4 rather than Instagram's 4:5 because a phone camera in
    /// portrait shoots 3:4, and cropping the top off every upright photo
    /// taken on the device the app runs on is the wrong default. Bounded at
    /// 16:9 at the wide end for the panorama reason above.
    static let allowed: [CGFloat] = [
        3.0 / 4.0,      // 0.750  portrait, as a phone camera shoots it
        4.0 / 5.0,      // 0.800  portrait, the usual feed shape
        1.0,            // 1.000  square
        5.0 / 4.0,      // 1.250  landscape
        4.0 / 3.0,      // 1.333  landscape, as a phone camera shoots it
        3.0 / 2.0,      // 1.500  landscape, as most cameras shoot it
        16.0 / 9.0,     // 1.778  wide
    ]

    /// Tallest allowed, as width over height.
    static let narrowest: CGFloat = 3.0 / 4.0
    /// Widest allowed, as width over height.
    static let widest: CGFloat = 16.0 / 9.0

    /// What to reserve before the photo has loaded.
    ///
    /// A guess, and it has to be: no dimensions reach the app before the
    /// image data does. 4:3 is both a member of the set and near the middle
    /// of it, so the settle when the real shape arrives is small in either
    /// direction and lands on a shape rather than between two.
    static let unloaded: CGFloat = 4.0 / 3.0

    /// `size` as a drawable shape, or `unloaded` if it says nothing useful.
    static func clamped(_ size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return unloaded }
        return clamped(size.width / size.height)
    }

    /// The allowed shape closest to `ratio`.
    ///
    /// Clamped into range first, then snapped. Doing it the other way round
    /// would let a panorama pick the widest member by nearness and a sliver
    /// pick the tallest, which is the same answer -- but only by accident,
    /// and only while the set stays symmetrical about the middle.
    static func clamped(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return unloaded }
        let bounded = min(max(ratio, narrowest), widest)
        var nearest = unloaded
        var closest = CGFloat.greatestFiniteMagnitude
        for candidate in allowed {
            let distance = abs(candidate - bounded)
            if distance < closest {
                closest = distance
                nearest = candidate
            }
        }
        return nearest
    }
}
