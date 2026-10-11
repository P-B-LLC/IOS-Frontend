import AVKit
import PhotosUI
import SwiftUI

/// Creating the player is a deliberate action, never a side effect of feed rendering.
struct PostVideoView: View {
    let postID: Int
    let video: PostVideoMedia
    let canReplace: Bool
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var failure: String?
    @State private var refreshed: PostVideoMedia?
    @State private var observation: NSKeyValueObservation?
    @State private var playbackObservation: NSKeyValueObservation?
    @State private var didRecordStart = false
    @State private var requestGeneration = UUID()
    @State private var replacement: PhotosPickerItem?

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
                if current.failed && canReplace {
                    PhotosPicker(selection: $replacement, matching: .videos, preferredItemEncoding: .current) {
                        Label("Choose another video", systemImage: "video.badge.plus")
                    }.disabled(loading || social.isPosting)
                }
            }
            if loading && player == nil { ProgressView("Loading video…") }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { stop(); play() }.disabled(loading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onDisappear { requestGeneration = UUID(); stop() }
        .task(id: replacement) {
            guard let replacement else { return }
            loading = true
            var draft: PostVideoDraft?
            defer { draft?.discard(); loading = false; self.replacement = nil }
            do {
                draft = try await replacement.loadTransferable(type: PostVideoDraft.self)
                guard let draft else { throw VideoBetaLimits.ValidationError.format }
                try await draft.validate()
                try Task.checkCancellation()
                if await social.retryVideo(postID: postID, draft: draft) {
                    refreshed = social.lastPosted?.video
                    failure = nil
                } else { failure = "Could not attach this video. Try again." }
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
        .onChange(of: social.isConnected) { if !social.isConnected { stop() } }
        .onChange(of: scenePhase) { if scenePhase != .active { stop() } }
        .onScrollVisibilityChange(threshold: 0.25) { visible in if !visible { stop() } }
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
                didRecordStart = false
                observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                    let status = item.status
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        if status == .readyToPlay {
                            loading = false
                        }
                        if status == .failed {
                            loading = false
                            failure = "This video could not play. Please try again."
                            await social.recordVideoPlayback(postID: postID, failed: true)
                        }
                    }
                }
                playbackObservation = next.observe(\.timeControlStatus, options: [.new]) { next, _ in
                    let status = next.timeControlStatus
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        loading = status == .waitingToPlayAtSpecifiedRate
                        if status == .playing && !didRecordStart {
                            didRecordStart = true
                            await social.recordVideoPlayback(postID: postID, failed: false)
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
        playbackObservation?.invalidate(); playbackObservation = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        loading = false
    }
}
