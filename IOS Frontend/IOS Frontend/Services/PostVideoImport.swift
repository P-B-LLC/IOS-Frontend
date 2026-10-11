import AVFoundation
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct PostVideoDraft: Transferable, Sendable {
    let fileURL: URL
    let contentType: String
    let sizeBytes: Int

    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rytivo-video-drafts", isDirectory: true)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= VideoBetaLimits.maximumBytes else { throw VideoBetaLimits.ValidationError.size }
            let ext = received.file.pathExtension.lowercased()
            guard ["mp4", "mov", "m4v"].contains(ext) else { throw VideoBetaLimits.ValidationError.format }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let oldDrafts = (try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])) ?? []
            for file in oldDrafts {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == true, let modified = values?.contentModificationDate,
                   modified < Date().addingTimeInterval(-86_400) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PostVideoDraft(fileURL: destination, contentType: ext == "mov" ? "video/quicktime" : "video/mp4", sizeBytes: size)
        }
    }

    func validate() async throws {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else { throw VideoBetaLimits.ValidationError.format }
        let dimensions = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let formats = try await track.load(.formatDescriptions)
        guard !formats.isEmpty, formats.allSatisfy({
            let codec = CMFormatDescriptionGetMediaSubType($0)
            return codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC
        }) else { throw VideoBetaLimits.ValidationError.format }
        try VideoBetaLimits.validate(size: sizeBytes, seconds: duration.seconds,
                                    width: abs(dimensions.width), height: abs(dimensions.height), fps: Double(fps))
        try Task.checkCancellation()
    }

    func discard() {
        guard fileURL.deletingLastPathComponent().standardizedFileURL == Self.directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
