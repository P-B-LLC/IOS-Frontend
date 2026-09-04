//
//  PhotoCropperView.swift
//  IOS Frontend
//
//  Choosing which part of a photo is kept, and at what shape.
//
//  A picked photo is almost never the shape a surface wants it, and almost
//  never framed on the thing it is of. Uploading it as it came meant the app
//  chose the crop, always from the middle: a photo taken at arm's length
//  became a picture of somebody's shoulder, and a plate of food shot upright
//  arrived as a strip through its middle.
//
//  One cropper for both callers. The profile picture asks for a square under
//  a circle and offers no choice of shape; a post offers five and draws a
//  rectangle. Everything between those two -- the drag, the zoom, the
//  clamping, and the arithmetic that turns all of it into a rectangle of
//  pixels -- is the same job, and was written twice for a while.
//

import SwiftUI
import UIKit

/// A photo waiting to be framed.
///
/// `fullScreenCover(item:)` needs an identity and `UIImage` has none, so this
/// carries one. A fresh id each time also means picking the same photo twice
/// in a row opens the cropper twice, rather than the second pick looking like
/// nothing happened.
struct PendingPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct PhotoCropperView: View {
    let image: UIImage
    /// The shapes offered. A single entry hides the picker entirely.
    var shapes: [PhotoCropShape] = PhotoCropShape.allCases
    /// Draws a circle over the window rather than a rectangle.
    var masksToCircle = false
    /// The longest edge written out, in pixels.
    ///
    /// The upload travels as base64 inside JSON, which costs a third again on
    /// top, so a 12-megapixel crop would be a several-megabyte request. 2048
    /// is still comfortably more than the widest phone this runs on, so the
    /// detail page has more to show than the screen can draw.
    var longestEdge: CGFloat = 2048
    let onCancel: () -> Void
    let onUse: (Data) -> Void

    /// Redrawn upright once, on the way in. See `PhotoCropGeometry`.
    private let upright: UIImage

    @State private var shape: PhotoCropShape
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    /// How far in the picture may be pushed. Past this a photo is guesswork
    /// rather than a subject, and the crop it writes out is mostly invention.
    private static let maximumScale: CGFloat = 6

    init(
        image: UIImage,
        shapes: [PhotoCropShape] = PhotoCropShape.allCases,
        masksToCircle: Bool = false,
        longestEdge: CGFloat = 2048,
        onCancel: @escaping () -> Void,
        onUse: @escaping (Data) -> Void
    ) {
        self.image = image
        self.shapes = shapes
        self.masksToCircle = masksToCircle
        self.longestEdge = longestEdge
        self.onCancel = onCancel
        self.onUse = onUse
        self.upright = Self.uprightCopy(of: image)
        _shape = State(initialValue: shapes.first ?? .original)
    }

    var body: some View {
        GeometryReader { geometry in
            let window = cropWindow(in: geometry.size)

            ZStack {
                Color.black.ignoresSafeArea()

                // Deliberately unclipped: the rest of the photo stays visible
                // and dimmed around the window, so it is clear what is being
                // left out rather than only what is being kept.
                Image(uiImage: upright)
                    .resizable()
                    .scaledToFill()
                    .frame(width: window.width, height: window.height)
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + windowRise)

                dimmedSurround(window: window)
                windowOutline(window: window)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(window: window))
            .simultaneousGesture(zoomGesture(window: window))
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { footer(window: window) }
            // Changing shape moves the window, so an offset that was legal
            // inside the old one can leave the new one uncovered.
            .onChange(of: shape) {
                let geometryNow = PhotoCropGeometry(
                    imagePixels: upright.size,
                    cropPoints: cropWindow(in: geometry.size)
                )
                offset = geometryNow.clampedOffset(offset, at: scale)
                committedOffset = offset
            }
        }
        .background(Color.black)
    }

    // MARK: - The window

    /// How far above the screen's centre the window sits.
    ///
    /// The footer carries the chips, a hint and a button; the header carries
    /// one line. Centred on the screen, the window therefore sits low, with
    /// an obvious band of black above it and almost none below. This lifts it
    /// to the middle of the space actually left over.
    private var windowRise: CGFloat {
        shapes.count > 1 ? -46 : -30
    }

    private func cropWindow(in available: CGSize) -> CGSize {
        PhotoCropGeometry.cropWindow(
            ratio: shape.ratio(for: upright.size),
            in: available,
            // Across: a margin, so the window is not flush to the edges.
            horizontalInset: 32,
            // Down: the title above, and the chips, hint and button below.
            // More when there are chips, because there is a row more to fit.
            verticalInset: shapes.count > 1 ? 330 : 260
        )
    }

    private func geometry(window: CGSize) -> PhotoCropGeometry {
        PhotoCropGeometry(imagePixels: upright.size, cropPoints: window)
    }

    // MARK: - Gestures

    private func dragGesture(window: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = geometry(window: window).clampedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    at: scale
                )
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func zoomGesture(window: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = committedScale * value.magnification
                scale = min(max(proposed, 1), Self.maximumScale)
                offset = geometry(window: window).clampedOffset(offset, at: scale)
            }
            .onEnded { _ in
                committedScale = scale
                committedOffset = offset
            }
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

    private func windowOutline(window: CGSize) -> some View {
        Group {
            if masksToCircle {
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            } else {
                Rectangle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            }
        }
        .frame(width: window.width, height: window.height)
        .offset(y: windowRise)
        .allowsHitTesting(false)
    }

    /// Dims everything outside the window.
    ///
    /// `compositingGroup` is load-bearing: `destinationOut` punches a hole in
    /// what it is composited against, and without a group of its own that is
    /// whatever happens to be behind the whole view.
    private func dimmedSurround(window: CGSize) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .mask {
                Rectangle()
                    .overlay {
                        Group {
                            if masksToCircle {
                                Circle()
                            } else {
                                Rectangle()
                            }
                        }
                        .frame(width: window.width, height: window.height)
                        .offset(y: windowRise)
                        .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private func footer(window: CGSize) -> some View {
        VStack(spacing: 14) {
            if shapes.count > 1 { shapePicker }

            Text("Drag to move, pinch to zoom.")
                .font(.community(.footnote))
                .foregroundStyle(Color.white.opacity(0.7))

            Button {
                if let data = croppedData(window: window) { onUse(data) }
            } label: {
                Text("Use photo")
                    .font(.community(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(Color.black)
            }
            .padding(.horizontal, 26)
        }
        .padding(.bottom, 28)
    }

    private var shapePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shapes) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { shape = option }
                    } label: {
                        Text(option.label)
                            .font(.community(.footnote, weight: .semibold))
                            .foregroundStyle(shape == option ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(
                                    shape == option
                                        ? AnyShapeStyle(.white)
                                        : AnyShapeStyle(.white.opacity(0.18))
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Writing it out

    /// What is under the window, as JPEG.
    ///
    /// Worked out in the photo's own pixels rather than by screenshotting the
    /// view: what is uploaded should be the resolution the user picked, not
    /// the couple of hundred points it happened to be shown at.
    private func croppedData(window: CGSize) -> Data? {
        guard let source = upright.cgImage else { return nil }
        let crop = geometry(window: window).cropRect(at: scale, offset: offset)
        guard !crop.isNull, crop.width >= 1, crop.height >= 1,
              let cut = source.cropping(to: crop) else { return nil }

        // Bounded on the way out, keeping the shape that was framed.
        let cutSize = CGSize(width: CGFloat(cut.width), height: CGFloat(cut.height))
        let shrink = min(1, longestEdge / max(cutSize.width, cutSize.height))
        let output = CGSize(
            width: max((cutSize.width * shrink).rounded(), 1),
            height: max((cutSize.height * shrink).rounded(), 1)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: output, format: format).image { _ in
            UIImage(cgImage: cut).draw(in: CGRect(origin: .zero, size: output))
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

#if DEBUG
/// Opens the cropper on a generated picture.
///
/// The real route in is the system photo picker, which a script cannot drive,
/// so without this the cropper could only be built and never looked at. The
/// picture is deliberately landscape and deliberately not symmetrical, so a
/// crop taken from the wrong place is visible rather than plausible.
struct PhotoCropperPreview: View {
    /// `cropper` draws the post configuration, `cropper-avatar` the profile
    /// one. Both callers are worth looking at: they differ in the mask, the
    /// chips and the window's size, which is most of what there is to see.
    var body: some View {
        if ProcessInfo.processInfo.environment["REPBASE_SOCIAL_PREVIEW"] == "cropper-avatar" {
            ProfilePhotoCropperView(image: Self.sample, onCancel: {}, onUse: { _ in })
        } else {
            PhotoCropperView(image: Self.sample, onCancel: {}, onUse: { _ in })
        }
    }

    private static var sample: UIImage {
        let size = CGSize(width: 1200, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // A grid, so which part was kept is countable rather than guessed.
            UIColor(white: 1, alpha: 0.18).setStroke()
            let path = UIBezierPath()
            for x in stride(from: 0, through: size.width, by: 100) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 100) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            path.lineWidth = 2
            path.stroke()
            // One corner marked, so an accidental flip or rotation shows.
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: size.width - 160, y: size.height - 100, width: 160, height: 100))
        }
    }
}
#endif
