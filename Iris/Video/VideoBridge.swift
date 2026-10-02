import Foundation
import WebKit

struct VideoDescriptor: Sendable {
    let id: String
    let source: String
    let manifest: String?
    let time: Double
    let duration: Double?
    let drm: Bool
    let nativeFullscreen: Bool
    var isPlaying = false
}

enum VideoBridge {
    static func shouldReplace(_ current: VideoDescriptor?, with candidate: VideoDescriptor) -> Bool {
        guard let current else { return true }
        return candidate.isPlaying || !current.isPlaying || current.id == candidate.id
    }
    enum Classification: Equatable {
        case playable(URL)
        case unsupported(String)
    }
    static func classify(_ video: VideoDescriptor) -> Classification {
        if video.drm { return .unsupported("Protected video stays on the website") }
        if let url = playableURL(video.source) { return .playable(url) }
        if video.source.hasPrefix("blob:"), let manifest = video.manifest,
           let url = playableURL(manifest), url.pathExtension.lowercased() == "m3u8" { return .playable(url) }
        return .unsupported(video.source.hasPrefix("blob:") ? "This streamed video needs website fullscreen" : "No direct MP4 or HLS source detected")
    }

    private static func playableURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, ["mp4", "mov", "m4v", "m3u8"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }
}

@MainActor struct VideoCandidate {
    let descriptor: VideoDescriptor
    let frame: WKFrameInfo
}
