import AVKit
import SwiftUI

/// Creating the player is a deliberate action, never a side effect of feed rendering.
struct PostVideoView: View {
    let postID: Int
    let video: PostVideoMedia
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var failure: String?
    @State private var refreshed: PostVideoMedia?
    @State private var observation: NSKeyValueObservation?
    @State private var requestGeneration = UUID()

    private var current: PostVideoMedia { refreshed ?? video }

    var body: some View {
        VStack(spacing: 8) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 240)
                    .overlay { if loading { ProgressView().tint(.white) } }
            } else if current.canPlay {
                Button { play() } label: {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        AsyncImage(url: current.thumbnailURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Color.clear }
                        Image(systemName: "play.circle.fill").font(.system(size: 48))
                            .foregroundStyle(.white).shadow(radius: 3)
                    }.frame(height: 220).clipped()
                }.buttonStyle(.plain).accessibilityLabel("Play video")
            } else {
                Label(current.failed ? "Video processing failed" : "Video is being prepared",
                      systemImage: current.failed ? "exclamationmark.triangle" : "video")
                    .foregroundStyle(.secondary)
                Button("Refresh status") { refresh() }.disabled(loading)
            }
            if loading && player == nil { ProgressView("Loading video…") }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { stop(); play() }.disabled(loading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onDisappear { requestGeneration = UUID(); stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { player?.pause() } }
        .onScrollVisibilityChange(threshold: 0.25) { visible in if !visible { player?.pause() } }
    }

    private func refresh() {
        guard !loading else { return }
        loading = true
        let generation = requestGeneration
        Task {
            do {
                let latest = try await social.refreshVideo(postID: postID)
                guard generation == requestGeneration else { return }
                refreshed = latest
                failure = latest == nil ? "This video is no longer available." : nil
            } catch {
                guard generation == requestGeneration else { return }
                failure = "Could not refresh this video. Please try again."
            }
            loading = false
        }
    }

    private func play() {
        guard !loading else { return }
        loading = true
        failure = nil
        let generation = requestGeneration
        Task {
            do {
                guard let latest = try await social.refreshVideo(postID: postID), latest.canPlay,
                      let url = latest.url, url.scheme == "https" else { throw CancellationError() }
                guard generation == requestGeneration, scenePhase == .active else { return }
                refreshed = latest
                let item = AVPlayerItem(url: url)
                item.preferredPeakBitRate = 1_300_000
                item.preferredMaximumResolution = CGSize(width: 854, height: 854)
                let next = AVPlayer(playerItem: item)
                player = next
                observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                    let status = item.status
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        if status == .readyToPlay { loading = false }
                        if status == .failed {
                            loading = false
                            failure = "This video could not play. Please try again."
                        }
                    }
                }
                next.play()
            } catch {
                guard generation == requestGeneration else { return }
                loading = false
                failure = "This video is unavailable. Refresh and try again."
            }
        }
    }

    private func stop() {
        requestGeneration = UUID()
        observation?.invalidate(); observation = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        loading = false
    }
}
