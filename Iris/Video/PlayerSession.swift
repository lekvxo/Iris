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
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(player: AVPlayer, candidate: VideoCandidate, wasPlaying: Bool, pageURL: URL?) {
        self.player = player
        self.candidate = candidate
        self.wasPlaying = wasPlaying
        self.pageURL = pageURL
        observation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failure = item.status == .failed ? item.error?.localizedDescription ?? "Playback failed" : nil
            Task { @MainActor [weak self] in self?.error = failure }
        }
    }
}
