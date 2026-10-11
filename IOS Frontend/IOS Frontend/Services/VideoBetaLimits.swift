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
            case .size: "Choose a video smaller than 15 MB."
            case .duration: "Choose a video no longer than 30 seconds."
            case .resolution: "Choose a video at 1080p or below."
            case .frameRate: "Choose a video at 60 frames per second or below."
            case .format: "Choose an MP4 or MOV video encoded with H.264 or HEVC."
            }
        }
    }
}
