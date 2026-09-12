//
//  PhotoDecoding.swift
//  IOS Frontend
//
//  Turning picked photo data into an image, away from the main thread.
//
//  Both places that read a photo out of the system picker had the same shape:
//  await the bytes, then `UIImage(data:)`. That call looks cheap because it
//  is -- it parses the header and leaves the pixels alone. The decode happens
//  the first time something draws the image, which is on the main thread,
//  during whatever animation is running at the time. For a photograph off a
//  modern phone camera that is twelve megapixels of work in the middle of a
//  sheet presentation.
//

import UIKit

enum PhotoDecoding {
    /// A picked photo, with its pixels already decoded.
    ///
    /// `preparingForDisplay` is what forces the work to happen here instead
    /// of at the first draw. It answers nil for an image it cannot prepare,
    /// which is no reason to throw away one that decoded perfectly well, so
    /// the undecoded image is still returned in that case -- the pixels then
    /// land on the main thread as before, which is the old behaviour rather
    /// than a new failure.
    ///
    /// `@concurrent` is the part that moves it. Callers are main-actor
    /// isolated views, and an unstructured `Task {}` inside one inherits that
    /// isolation, so a plain `nonisolated` function would still have run on
    /// the main actor: `nonisolated` says the work does not need the main
    /// actor, not that it leaves it.
    @concurrent
    nonisolated static func decoded(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
    }
}
