//
//  RemoteImage.swift
//  IOS Frontend
//
//  A photo from the server, fetched once and shrunk before it is drawn.
//
//  `AsyncImage` does neither. It keeps nothing, so every rebuild of the view
//  around it starts the download again — and the feed sits inside a
//  `TimelineView` that rebuilds once a minute, so a card's photo was being
//  pulled down repeatedly and cancelled halfway each time. It also decodes at
//  full size: the post photos on this server are two to four megabytes, which
//  is a 4000-pixel image being decoded on the main thread to fill a box 200
//  points tall.
//
//  So: one download per URL per launch, decoded straight to the size actually
//  needed, off the main thread.
//

import SwiftUI
import ImageIO
import UIKit

/// Decoded images, kept for as long as the system will allow.
///
/// `NSCache` rather than a dictionary: it empties itself under memory
/// pressure, which a feed of photographs will eventually cause.
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let images = NSCache<NSString, UIImage>()
    private var generation = UUID()

    func clear() {
        generation = UUID()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        images.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()
    }
    /// Downloads already running, so two cards showing the same photo make
    /// one request rather than two.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        images.countLimit = 120
    }

    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        images.object(forKey: Self.key(url, maxPixel) as NSString)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let generation = self.generation
        let key = Self.key(url, maxPixel)
        if let hit = images.object(forKey: key as NSString) { return hit }
        if let running = inFlight[key] {
            let result = await running.value
            guard self.generation == generation, !Task.isCancelled else { return nil }
            return result
        }

        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let shrunk = Self.downsample(data, maxPixel: maxPixel) else {
                return nil
            }
            return shrunk
        }
        inFlight[key] = task
        let result = await task.value
        guard self.generation == generation, !Task.isCancelled else { return nil }
        inFlight[key] = nil
        if let result { images.setObject(result, forKey: key as NSString) }
        return result
    }

    /// Decodes at the size being drawn rather than the size that was uploaded.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` never builds the full-size bitmap,
    /// so a four-megabyte photograph costs what a small one costs.
    private nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func key(_ url: URL, _ maxPixel: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(maxPixel))"
    }
}

/// A photo from the server, sized for where it is being shown.
struct RemoteImage<Placeholder: View, Failure: View>: View {
    let url: URL
    /// The largest edge, in pixels, the decoded image needs. Screen points
    /// times the screen scale.
    var maxPixel: CGFloat = 900
    /// Called with the decoded size once there is one, cache hits included.
    ///
    /// Lets a caller draw the photo at the shape it was posted at. Nothing
    /// else can: the contract carries no dimensions for an uploaded image,
    /// so the only place the ratio is known is here, after the bytes land.
    var onNaturalSize: ((CGSize) -> Void)?

    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @State private var image: UIImage?
    @State private var hasFinished = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if hasFinished {
                failure()
            } else {
                placeholder()
            }
        }
        // Keyed on the URL so a recycled row showing a different post does not
        // keep the previous one's photo.
        .task(id: url) {
            // A cache hit is taken synchronously, which is what stops the
            // photo flashing away and back on every minute-tick rebuild.
            if let hit = RemoteImageCache.shared.cached(url, maxPixel: maxPixel) {
                image = hit
                hasFinished = true
                onNaturalSize?(hit.size)
                return
            }
            image = nil
            hasFinished = false
            let loaded = await RemoteImageCache.shared.image(for: url, maxPixel: maxPixel)
            image = loaded
            hasFinished = true
            if let loaded { onNaturalSize?(loaded.size) }
        }
    }
}
