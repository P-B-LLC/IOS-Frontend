//
//  ProfilePhotoCropperView.swift
//  IOS Frontend
//
//  Choosing which part of a photo becomes the profile picture.
//
//  A picked photo is almost never square and almost never framed on the face.
//  Uploading it as it came meant the app chose the crop, always from the
//  middle, and a photo taken at arm's length became a picture of somebody's
//  shoulder. This is the step in between: the picture under a circle, moved
//  and zoomed until it looks right, and only then uploaded.
//
//  The mask is a circle because that is how every avatar in the app is drawn.
//  What is written out is the square around that circle: the corners cost
//  little and any square surface added later has something to show.
//
//  The framing itself now lives in `PhotoCropperView`, which post photos use
//  as well. This is the square, circular, no-choice-of-shape configuration of
//  it -- the two had the same drag, the same zoom, the same clamping and the
//  same pixel arithmetic, written out twice.
//

import SwiftUI
import UIKit

/// A photo waiting to be framed.
///
/// Kept as its own type rather than folded into `PendingPhoto` because
/// `fullScreenCover(item:)` at the call site is typed on it, and the two
/// callers should be able to present their croppers independently.
struct PendingProfilePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfilePhotoCropperView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onUse: (Data) -> Void

    var body: some View {
        PhotoCropperView(
            image: image,
            // No choice offered: an avatar is drawn in a circle everywhere in
            // the app, so any other shape would be cropped again on the way
            // to the screen and the choice would be a lie.
            shapes: [.square],
            masksToCircle: true,
            // Smaller than a post photo keeps. An avatar is drawn at 38 points
            // in a feed row and a couple of hundred at its largest, so beyond
            // this the extra pixels are only upload.
            longestEdge: 1024,
            onCancel: onCancel,
            onUse: onUse
        )
    }
}
