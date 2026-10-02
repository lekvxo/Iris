import AVFoundation
import WebKit

extension BrowserModel {
    func closePlayer() async {
        guard let session = playerSession else { return }
        session.player.pause()
        playerSession = nil
    }

    func prepareHandoff() async {
        guard !isPreparingVideo, let candidate = video, let view = webView,
              case .playable(let source) = VideoBridge.classify(candidate.descriptor) else { return }
        isPreparingVideo = true
        videoError = nil
        defer { isPreparingVideo = false }
        var paused = false
        var wasPlaying = false
        var time = candidate.descriptor.time
        do {
            let snapshot = try await view.callAsyncJavaScript("""
                const v = [...document.querySelectorAll('video')].find(v => v.dataset.irisVideo === id);
                if (!v || v.currentSrc !== source || v.mediaKeys) throw new Error('Video changed or is protected');
                const result = {time: v.currentTime, wasPlaying: !v.paused};
                v.pause(); return result;
                """, arguments: ["id": candidate.descriptor.id, "source": candidate.descriptor.source], in: candidate.frame, contentWorld: .page)
            if let snapshot = snapshot as? [String: Any] {
                time = snapshot["time"] as? Double ?? time
                wasPlaying = snapshot["wasPlaying"] as? Bool ?? false
            }
            paused = true
            let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
            let userAgent = try await view.evaluateJavaScript("navigator.userAgent", in: candidate.frame, contentWorld: .page) as? String ?? ""
            let asset = AVURLAsset(url: source, options: [
                AVURLAssetHTTPCookiesKey: Self.cookies(cookies, for: source),
                AVURLAssetHTTPUserAgentKey: userAgent
            ])
            guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)) else {
                throw VideoError.unsupported
            }
            guard !Task.isCancelled, webView === view, video?.descriptor.id == candidate.descriptor.id else {
                throw CancellationError()
            }
            let item = AVPlayerItem(asset: asset)
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierTitle
            metadata.value = title as NSString
            metadata.extendedLanguageTag = "und"
            item.externalMetadata = [metadata]
            let player = AVPlayer(playerItem: item)
            let duration = try await asset.load(.duration).seconds
            let start = time.isFinite ? max(0, duration.isFinite && duration > 0 ? min(time, duration) : time) : 0
            if start > 0 { await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            playerSession = PlayerSession(player: player, candidate: candidate, wasPlaying: wasPlaying, pageURL: view.url)
        } catch {
            if !(error is CancellationError) { videoError = "Player could not open this source. \(error.localizedDescription)" }
            if paused { await returnToVideo(candidate, time: time, resume: wasPlaying) }
        }
    }

    static func cookies(_ cookies: [HTTPCookie], for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let matches = domain.hasPrefix(".")
                ? host == String(domain.dropFirst()) || host.hasSuffix(domain)
                : host == domain
            let path = url.path.isEmpty ? "/" : url.path
            let pathMatches = path == cookie.path || (path.hasPrefix(cookie.path) &&
                (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
            return matches && pathMatches && (!cookie.isSecure || url.scheme == "https") &&
                (cookie.expiresDate.map { $0 > Date() } ?? true)
        }
    }

    func returnToVideo(_ candidate: VideoCandidate, time: Double, resume: Bool) async {
        guard let view = webView, time.isFinite else { return }
        _ = try? await view.callAsyncJavaScript("""
            const v = [...document.querySelectorAll('video')].find(v => v.dataset.irisVideo === id);
            if (!v || v.currentSrc !== source) return;
            if (Number.isFinite(v.duration)) v.currentTime = Math.min(time, v.duration);
            else v.currentTime = time;
            if (resume) await v.play();
            """, arguments: ["id": candidate.descriptor.id, "source": candidate.descriptor.source,
                               "time": max(0, time), "resume": resume], in: candidate.frame, contentWorld: .page)
    }
}

enum VideoError: LocalizedError {
    case unsupported
    var errorDescription: String? { "The video is unsupported or protected. Use the website player." }
}
