import AVFoundation
import WebKit

extension BrowserModel {
    func enterNativeFullscreen() async {
        guard !isPreparingVideo, let candidate = video, let view = webView else { return }
        let preparationID = UUID()
        videoPreparationID = preparationID
        isPreparingVideo = true
        videoError = nil
        defer { finishPreparation(preparationID) }
        do {
            _ = try await view.callAsyncJavaScript("""
                const v = [...document.querySelectorAll('video')].find(v => v.dataset.irisVideo === id);
                if (!v) throw new Error('Video is no longer on this page');
                window.irisPrepareNativeCaptions?.(v);
                if (typeof v.webkitEnterFullscreen === 'function') v.webkitEnterFullscreen();
                else if (typeof v.requestFullscreen === 'function') await v.requestFullscreen();
                else throw new Error('No fullscreen API');
                """, arguments: ["id": candidate.descriptor.id], in: candidate.frame, contentWorld: .page)
        } catch {
            guard videoPreparationID == preparationID, !Task.isCancelled else { return }
            _ = try? await view.callAsyncJavaScript("""
                const v = [...document.querySelectorAll('video')].find(v => v.dataset.irisVideo === id);
                if (v) window.irisRestoreNativeCaptions?.(v);
                """, arguments: ["id": candidate.descriptor.id], in: candidate.frame, contentWorld: .page)
            videoError = "Use the video's fullscreen control on the page. \(error.localizedDescription)"
        }
    }

    func closePlayer() async {
        guard let session = playerSession else { return }
        session.stop()
        let time = session.player.currentTime().seconds
        playerSession = nil
        restoreBrowserWindow()
        guard webView?.url == session.pageURL else { return }
        await returnToVideo(session.candidate, time: time, resume: session.wasPlaying)
    }

    func prepareHandoff() async {
        guard !isPreparingVideo, let candidate = video, let view = webView,
              case .playable(let source) = VideoBridge.classify(candidate.descriptor) else { return }
        let preparationID = UUID()
        let pageURL = view.url
        videoPreparationID = preparationID
        isPreparingVideo = true
        videoError = nil
        defer { finishPreparation(preparationID) }
        var paused = false
        var wasPlaying = false
        var time = candidate.descriptor.time
        var captions = NativeCaptionPreference(nil)
        do {
            let snapshot = try await view.callAsyncJavaScript("""
                const v = [...document.querySelectorAll('video')].find(v => v.dataset.irisVideo === id);
                if (!v || v.currentSrc !== source || v.mediaKeys) throw new Error('Video changed or is protected');
                const result = {time: v.currentTime, wasPlaying: !v.paused, captions: window.irisNativeCaptionPreference?.(v) ?? {known: false}};
                v.pause(); return result;
                """, arguments: ["id": candidate.descriptor.id, "source": candidate.descriptor.source], in: candidate.frame, contentWorld: .page)
            if let snapshot = snapshot as? [String: Any] {
                time = snapshot["time"] as? Double ?? time
                wasPlaying = snapshot["wasPlaying"] as? Bool ?? false
                captions = NativeCaptionPreference(snapshot["captions"] as? [String: Any])
            }
            paused = true
            let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
            let userAgent = try await view.evaluateJavaScript("navigator.userAgent", in: candidate.frame, contentWorld: .page) as? String ?? ""
            try validatePreparation(preparationID, candidate: candidate, view: view, pageURL: pageURL)
            let options: [String: Any] = [
                AVURLAssetHTTPCookiesKey: Self.cookies(cookies, for: source),
                AVURLAssetHTTPUserAgentKey: userAgent
            ]
            let asset = AVURLAsset(url: source, options: options)
            loadingAsset = asset
            guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)) else {
                throw VideoError.unsupported
            }
            let item = AVPlayerItem(asset: asset)
            try await captions.apply(to: item)
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierTitle
            metadata.value = title as NSString
            metadata.extendedLanguageTag = "und"
            item.externalMetadata = [metadata]
            let retryMetadata = item.externalMetadata
            try await completeHandoff(preparationID, candidate: candidate, view: view, pageURL: pageURL,
                                      wasPlaying: wasPlaying, captions: captions, retryItem: {
                let replacement = AVPlayerItem(asset: AVURLAsset(url: source, options: options))
                replacement.externalMetadata = retryMetadata
                return replacement
            }) {
                let player = AVPlayer(playerItem: item)
                preparingPlayer = player
                let duration = try await asset.load(.duration).seconds
                let start = time.isFinite ? max(0, duration.isFinite && duration > 0 ? min(time, duration) : time) : 0
                if start > 0 {
                    await player.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                                      toleranceBefore: .zero, toleranceAfter: .zero)
                }
                return player
            }
        } catch {
            guard videoPreparationID == preparationID, webView === view, view.url == pageURL else { return }
            if !(error is CancellationError) { videoError = "Player could not open this source. \(error.localizedDescription)" }
            if paused { await returnToVideo(candidate, time: time, resume: wasPlaying) }
        }
    }

    // A canceled preparation may still finish an AVFoundation or WebKit callback.
    // Its token must never clear or present a newer preparation's session.
    func invalidateVideo() {
        documentID = UUID()
        videoPreparationID = nil
        videoTask?.cancel()
        videoTask = nil
        preparingPlayer?.currentItem?.cancelPendingSeeks()
        preparingPlayer?.pause()
        preparingPlayer = nil
        loadingAsset?.cancelLoading()
        loadingAsset = nil
        isPreparingVideo = false
        playerSession?.stop()
        playerSession = nil
    }

    private func finishPreparation(_ id: UUID) {
        guard videoPreparationID == id else { return }
        videoPreparationID = nil
        isPreparingVideo = false
        preparingPlayer = nil
        loadingAsset = nil
    }

    private func validatePreparation(_ id: UUID, candidate: VideoCandidate, view: WKWebView, pageURL: URL?) throws {
        guard !Task.isCancelled, videoPreparationID == id, webView === view, view.url == pageURL,
              video?.descriptor.id == candidate.descriptor.id,
              video?.descriptor.source == candidate.descriptor.source,
              video.map({ VideoBridge.classify($0.descriptor) }) == VideoBridge.classify(candidate.descriptor) else { throw CancellationError() }
    }

    func completeHandoff(_ id: UUID, candidate: VideoCandidate, view: WKWebView, pageURL: URL?,
                         wasPlaying: Bool, captions: NativeCaptionPreference = NativeCaptionPreference(nil), retryItem: (() -> AVPlayerItem)? = nil,
                         makePlayer: () async throws -> AVPlayer) async throws {
        try validatePreparation(id, candidate: candidate, view: view, pageURL: pageURL)
        let player = try await makePlayer()
        // In particular, validate after duration loading AND asynchronous seek.
        do { try validatePreparation(id, candidate: candidate, view: view, pageURL: pageURL) }
        catch { player.pause(); throw error }
        playerSession = PlayerSession(player: player, candidate: candidate, wasPlaying: wasPlaying, pageURL: pageURL, captions: captions, retryItem: retryItem)
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
    case noNativeCaptions
    var errorDescription: String? {
        switch self {
        case .unsupported: "The video is unsupported or protected. Use the website player."
        case .noNativeCaptions: "This source doesn't include native subtitles. Keep website playback to retain this site's subtitles."
        }
    }
}
