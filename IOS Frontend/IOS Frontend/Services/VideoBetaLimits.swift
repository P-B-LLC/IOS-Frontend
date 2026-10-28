import Foundation

nonisolated enum VideoBetaLimits {
    static let maximumBytes = 15 * 1024 * 1024

    static func validate(size: Int, seconds: Double, width: Double, height: Double, fps: Double) throws {
        guard size > 0, size <= maximumBytes else { throw ValidationError.size }
        guard seconds.isFinite, seconds > 0, seconds <= 30 else { throw ValidationError.duration }
        guard width.isFinite, height.isFinite, width >= 2, height >= 2,
              max(width, height) <= 1920, width * height <= 1920 * 1080 else {
            throw ValidationError.resolution
        }
        guard fps.isFinite, fps >= 0, fps <= 60 else { throw ValidationError.frameRate }
    }

    enum ValidationError: LocalizedError {
        case size, duration, resolution, frameRate, format
        var errorDescription: String? {
            switch self {
            case .size: String(localized: "Choose a video smaller than 15 MB.", bundle: .app, locale: .app)
            case .duration: String(localized: "Choose a video no longer than 30 seconds.", bundle: .app, locale: .app)
            case .resolution: String(localized: "Choose a video at 1080p or below.", bundle: .app, locale: .app)
            case .frameRate: String(localized: "Choose a video at 60 frames per second or below.", bundle: .app, locale: .app)
            case .format: String(localized: "Choose an MP4 or MOV video encoded with H.264 or HEVC.", bundle: .app, locale: .app)
            }
        }
    }
}
