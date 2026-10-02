import XCTest
@testable import Iris

final class VideoBridgeTests: XCTestCase {
    private func video(_ source: String, manifest: String? = nil, drm: Bool = false) -> VideoDescriptor {
        .init(id: "test", source: source, manifest: manifest, time: 12, duration: 100, drm: drm, nativeFullscreen: true)
    }
    func testDirectAndSignedMediaURLs() {
        for ext in ["mp4", "m4v", "mov", "m3u8"] {
            let url = "https://media.example/video.\(ext)?token=a%2Bb"
            XCTAssertEqual(VideoBridge.classify(video(url)), .playable(URL(string: url)!))
        }
    }
    func testMSERequiresObservedHLS() {
        let hls = "https://cdn.example/master.m3u8?signature=123"
        XCTAssertEqual(VideoBridge.classify(video("blob:https://example.com/id", manifest: hls)), .playable(URL(string: hls)!))
        if case .playable = VideoBridge.classify(video("blob:https://example.com/id")) { XCTFail("Unsupported MSE was accepted") }
        if case .playable = VideoBridge.classify(video("blob:https://example.com/id", manifest: "https://example.com/video.mp4")) { XCTFail("Unrelated MP4 was accepted") }
    }
    func testDRMAndNonHTTPAreNeverHandedOff() {
        for source in ["https://example.com/protected.mp4", "blob:https://example.com/id"] {
            if case .playable = VideoBridge.classify(video(source, manifest: "https://example.com/a.m3u8", drm: true)) { XCTFail("DRM was accepted") }
        }
        for source in ["file:///video.mp4", "data:video/mp4;base64,AAAA", "https://example.com/page", ""] {
            if case .playable = VideoBridge.classify(video(source)) { XCTFail("Unsupported source was accepted") }
        }
    }
}
