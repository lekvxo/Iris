import AVFoundation
import Observation

@MainActor @Observable
final class PlayerSession: Identifiable {
    let id = UUID()
    let player: AVPlayer
    let candidate: VideoCandidate
    let wasPlaying: Bool
    let pageURL: URL?
    var error: String?
    var isRetrying = false
    var canRetry: Bool { retryItem != nil }
    @ObservationIgnored private let retryItem: (() -> AVPlayerItem)?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var playbackObservation: NSKeyValueObservation?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private let captions: NativeCaptionPreference

    init(player: AVPlayer, candidate: VideoCandidate, wasPlaying: Bool, pageURL: URL?, captions: NativeCaptionPreference = NativeCaptionPreference(nil), retryItem: (() -> AVPlayerItem)? = nil) {
        self.player = player
        self.candidate = candidate
        self.wasPlaying = wasPlaying
        self.pageURL = pageURL
        self.retryItem = retryItem
        self.captions = captions
        observeItem()
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                if playing, let self, !self.stopped, self.player.currentItem?.status != .failed { self.error = nil }
            }
        }
    }

    private func observeItem() {
        for token in notifications { NotificationCenter.default.removeObserver(token) }
        notifications.removeAll()
        observation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let failure = item.status == .failed ? item.error?.localizedDescription ?? "Playback failed" : nil
            Task { @MainActor [weak self] in
                guard let self, !self.stopped, self.player.currentItem === item else { return }
                if let failure { self.error = failure }
            }
        }
        guard let item = player.currentItem else { return }
        for name in [AVPlayerItem.playbackStalledNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.stopped, self.player.currentItem === item else { return }
                    self.error = name == AVPlayerItem.playbackStalledNotification
                        ? "Playback stalled. Check your connection, then retry or return to the page."
                        : "Playback failed. Retry or return to the page."
                }
            }
            notifications.append(token)
        }
    }

    func retry() {
        guard !isRetrying, !stopped, let retryItem else { return }
        let time = player.currentTime()
        player.pause()
        error = nil
        isRetrying = true
        player.replaceCurrentItem(with: retryItem())
        observeItem()
        retryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRetrying = false; self.retryTask = nil }
            if let item = self.player.currentItem {
                do { try await self.captions.apply(to: item) }
                catch { self.error = error.localizedDescription; return }
            }
            guard !Task.isCancelled, !self.stopped else { return }
            if time.seconds.isFinite, time.seconds > 0 {
                await self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            guard !Task.isCancelled, !self.stopped else { return }
            self.player.play()
        }
    }

    func play() {
        guard !stopped else { return }
        player.play()
    }

    func stop() {
        stopped = true
        retryTask?.cancel()
        player.currentItem?.cancelPendingSeeks()
        player.pause()
    }

    isolated deinit {
        retryTask?.cancel()
        player.pause()
        for token in notifications { NotificationCenter.default.removeObserver(token) }
    }

}
