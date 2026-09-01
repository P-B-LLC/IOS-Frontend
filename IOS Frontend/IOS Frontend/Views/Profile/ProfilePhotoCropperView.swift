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

import PhotosUI
import SwiftUI
import UIKit

/// A photo waiting to be framed.
///
/// `fullScreenCover(item:)` needs an identity and `UIImage` has none, so this
/// carries one. A fresh id each time also means picking the same photo twice
/// in a row opens the cropper twice, rather than the second pick looking like
/// nothing happened.
struct PendingProfilePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfilePhotoCropperView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onUse: (Data) -> Void

    /// Redrawn upright once, on the way in.
    ///
    /// A photo from the library usually carries its rotation as an orientation
    /// flag rather than in the pixels, and `CGImage.cropping` knows nothing
    /// about that flag -- it would cut from the unrotated pixels and hand back
    /// a crop of the wrong part of the wrong side. Everything below assumes
    /// this upright copy, whose `size` is therefore in pixels.
    private let upright: UIImage

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    /// How far in the picture may be pushed. Past this a photo is guesswork
    /// rather than a face, and the crop it writes out is mostly invention.
    private static let maximumScale: CGFloat = 6

    init(
        image: UIImage,
        onCancel: @escaping () -> Void,
        onUse: @escaping (Data) -> Void
    ) {
        self.image = image
        self.onCancel = onCancel
        self.onUse = onUse
        self.upright = Self.uprightCopy(of: image)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = cropSide(in: geometry.size)

            ZStack {
                Color.black.ignoresSafeArea()

                // Deliberately unclipped: the rest of the photo stays visible
                // and dimmed around the circle, so it is clear what is being
                // left out rather than only what is being kept.
                Image(uiImage: upright)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .scaleEffect(scale)
                    .offset(offset)

                dimmedSurround(side: side)

                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = clamped(
                            CGSize(
                                width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height
                            ),
                            scale: scale,
                            side: side
                        )
                    }
                    .onEnded { _ in committedOffset = offset }
                    .simultaneously(
                        with: MagnifyGesture()
                            .onChanged { value in
                                let proposed = committedScale * value.magnification
                                scale = min(max(proposed, 1), Self.maximumScale)
                                // Re-clamped as it zooms: pulling back out
                                // would otherwise leave the picture parked off
                                // to one side with a gap under the circle.
                                offset = clamped(offset, scale: scale, side: side)
                            }
                            .onEnded { _ in
                                committedScale = scale
                                committedOffset = offset
                            }
                    )
            )
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { footer(side: side) }
        }
        .background(Color.black)
        .statusBarHidden()
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.community(.headline))
                .foregroundStyle(Color.white)
            Spacer()
            Text("Move and scale")
                .font(.community(.subheadline, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer()
            // Balances the title against Cancel without a second control.
            Text("Cancel")
                .font(.community(.headline))
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func footer(side: CGFloat) -> some View {
        VStack(spacing: 14) {
            Text("Drag to move, pinch to zoom.")
                .font(.community(.footnote))
                .foregroundStyle(Color.white.opacity(0.7))

            Button {
                if let data = croppedData(side: side) { onUse(data) }
            } label: {
                Text("Use photo")
                    .font(.community(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(Color.black)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 28)
    }

    private func dimmedSurround(side: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .mask {
                Rectangle()
                    .overlay {
                        Circle()
                            .frame(width: side, height: side)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - The geometry

    private func cropSide(in size: CGSize) -> CGFloat {
        max(min(size.width, size.height) - 56, 120)
    }

    /// Points per pixel of the upright photo, at the current zoom.
    ///
    /// `scaledToFill` into a square sizes the photo by its *shorter* edge, so
    /// that is what the base factor is taken from; anything else leaves the
    /// square with a gap along one axis at zoom 1.
    private func pointsPerPixel(scale: CGFloat, side: CGFloat) -> CGFloat {
        let shortest = min(upright.size.width, upright.size.height)
        guard shortest > 0 else { return 1 }
        return (side / shortest) * scale
    }

    /// Keeps the photo covering the circle.
    ///
    /// Without this the picture can be dragged clear of the crop entirely and
    /// the result is part photo, part nothing.
    private func clamped(_ proposed: CGSize, scale: CGFloat, side: CGFloat) -> CGSize {
        let factor = pointsPerPixel(scale: scale, side: side)
        let width = upright.size.width * factor
        let height = upright.size.height * factor
        let limitX = max((width - side) / 2, 0)
        let limitY = max((height - side) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    // MARK: - Writing it out

    /// The square under the circle, as JPEG.
    ///
    /// The crop is worked out in the photo's own pixels rather than by
    /// screenshotting the view: what is uploaded should be the resolution the
    /// user picked, not the couple of hundred points it happened to be shown
    /// at.
    private func croppedData(side: CGFloat) -> Data? {
        guard let source = upright.cgImage else { return nil }

        let factor = pointsPerPixel(scale: scale, side: side)
        guard factor > 0 else { return nil }

        let width = upright.size.width * factor
        let height = upright.size.height * factor
        // The crop square sits at the centre of the view; the photo's centre
        // sits at that same point plus the offset. So the square's top-left,
        // measured from the photo's top-left, is this -- in points, then
        // divided back into pixels.
        let originX = (width / 2 - side / 2 - offset.width) / factor
        let originY = (height / 2 - side / 2 - offset.height) / factor
        let sideInPixels = side / factor

        let bounds = CGRect(
            origin: .zero,
            size: CGSize(width: upright.size.width, height: upright.size.height)
        )
        // Intersected rather than trusted: rounding at the edges of a clamped
        // drag can put the rect a fraction outside, and `cropping` answers nil
        // for a rect that is not wholly inside rather than clipping it.
        let crop = CGRect(
            x: originX, y: originY, width: sideInPixels, height: sideInPixels
        )
        .integral
        .intersection(bounds)

        guard !crop.isNull, crop.width >= 1, crop.height >= 1,
              let cut = source.cropping(to: crop) else { return nil }

        // Squared off and bounded on the way out. The upload travels as base64
        // inside JSON, which costs a third again on top, so a 12-megapixel
        // crop would be a several-megabyte request to draw something the app
        // never shows above a couple of hundred points.
        let output = min(CGFloat(cut.width), 1024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = CGSize(width: output, height: output)
        let rendered = UIGraphicsImageRenderer(size: square, format: format).image { _ in
            UIImage(cgImage: cut).draw(in: CGRect(origin: .zero, size: square))
        }
        return rendered.jpegData(compressionQuality: 0.9)
    }

    /// A copy whose pixels are the right way up, at scale 1.
    ///
    /// Scale as well as orientation, because `size` is in points: on a
    /// two-times image it is half the pixels there actually are, and redrawing
    /// at that size would quietly throw away half the resolution before the
    /// crop ever happened. Afterwards `size` and pixels are the same thing,
    /// which is what the crop arithmetic assumes.
    private static func uprightCopy(of image: UIImage) -> UIImage {
        guard image.imageOrientation != .up || image.scale != 1 else { return image }

        let pixels = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Left non-opaque: a PNG with transparency would otherwise be flattened
        // onto black here, before anyone has decided what sits behind it.
        format.opaque = false
        return UIGraphicsImageRenderer(size: pixels, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixels))
        }
    }
}
