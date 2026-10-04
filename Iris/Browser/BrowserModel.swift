import Observation
import WebKit
import AVFoundation

@MainActor @Observable
final class BrowserModel {
    var url: URL?
    var title = "Iris"
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var estimatedProgress = 0.0
    var error: String?
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var openWindow: ((WindowRequest) -> Void)?
    @ObservationIgnored var closeWindow: (() -> Void)?
    // A popup's web view, made by its opener, waiting for its tab to adopt it.
    @ObservationIgnored var popup: (view: WKWebView, coordinator: WebView.Coordinator)?
    static var pendingPopups: [UUID: BrowserModel] = [:]
    @ObservationIgnored var lastLink: URL?
    @ObservationIgnored var lastGestureTime = Date.distantPast
    @ObservationIgnored var nativeDestination: URL?
    @ObservationIgnored var nativeArchiveDestination: URL?
    @ObservationIgnored var serverRedirectDestination: URL?
    var blocked: BlockedNavigation?
    var blockingActivity = PageBlockingActivity()
    var allowedSites: Set<String> = []
    var video: VideoCandidate?
    var videoError: String?
    var dismissedVideoNote: String?
    var isPreparingVideo = false
    var playerSession: PlayerSession?
    var isSavingOffline = false
    var saveError: String?
    var isInitializing = true
    var isBackgrounded = false
    var isWebFullscreen = false
    @ObservationIgnored weak var browserScene: UIWindowScene?
    @ObservationIgnored var browserWindowSize = CGSize(width: 1100, height: 760)
    @ObservationIgnored var videoTask: Task<Void, Never>?
    @ObservationIgnored var videoPreparationID: UUID?
    @ObservationIgnored var preparingPlayer: AVPlayer?
    @ObservationIgnored var loadingAsset: AVURLAsset?
    @ObservationIgnored var requestedURL: URL?
    @ObservationIgnored var documentID = UUID()
    @ObservationIgnored var archiveReplay: (name: String, url: URL)?
    private static var popupExpiry: [UUID: Task<Void, Never>] = [:]

    static func registerPopup(_ model: BrowserModel, id: UUID, expiresAfter: Duration = .seconds(30)) {
        pendingPopups[id] = model
        model.closeWindow = { discardPopup(id) }
        popupExpiry[id] = Task {
            do { try await Task.sleep(for: expiresAfter) } catch { return }
            discardPopup(id)
        }
    }

    static func adoptPopup(_ id: UUID) -> BrowserModel? {
        popupExpiry.removeValue(forKey: id)?.cancel()
        return pendingPopups.removeValue(forKey: id)
    }

    static func discardPopup(_ id: UUID) {
        popupExpiry.removeValue(forKey: id)?.cancel()
        guard let model = pendingPopups.removeValue(forKey: id), let popup = model.popup else { return }
        // Break model -> coordinator -> model before unregistering WebKit's handlers.
        model.popup = nil
        WebView.dismantleUIView(popup.view, coordinator: popup.coordinator)
    }

    func watchReason(native: Bool) -> String? {
        guard let video else { return "Play a video on the page to detect it" }
        if native { return video.descriptor.nativeFullscreen ? nil : "This video has no website fullscreen control" }
        if case .unsupported(let reason) = VideoBridge.classify(video.descriptor) { return reason }
        return nil
    }

    // The note under the toolbar; dismissing hides it for that video only.
    func videoNote(native: Bool) -> String? {
        if let videoError { return videoError }
        guard let video, video.descriptor.id != dismissedVideoNote else { return nil }
        if let reason = watchReason(native: native) { return reason }
        return native && video.descriptor.drm ? "Protected video uses website fullscreen" : nil
    }

    func dismissVideoNote() {
        videoError = nil
        dismissedVideoNote = video?.descriptor.id
    }

    func load(_ url: URL) {
        invalidateVideo()
        error = nil
        requestedURL = url
        nativeDestination = url
        nativeArchiveDestination = nil
        archiveReplay = nil
        webView?.load(URLRequest(url: url))
    }

    func sync(from view: WKWebView) {
        url = view.url
        // Untitled pages report "", which would save as a blank name.
        title = view.title.flatMap { $0.isEmpty ? nil : $0 } ?? view.url?.host ?? "Iris"
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        isLoading = view.isLoading
        estimatedProgress = view.estimatedProgress
    }
}
