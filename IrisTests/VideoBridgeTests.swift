import XCTest
import Foundation
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

    @MainActor func testCookiesStayWithinHostPathAndSecureScope() throws {
        func cookie(_ name: String, domain: String, path: String = "/", secure: Bool = false) throws -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: path]
            if secure { properties[.secure] = "TRUE" }
            return try XCTUnwrap(HTTPCookie(properties: properties))
        }
        let cookies = try [cookie("host", domain: "cdn.example.com"), cookie("domain", domain: ".example.com"),
            cookie("other", domain: ".evil.test"), cookie("path", domain: ".example.com", path: "/private"),
            cookie("secure", domain: ".example.com", secure: true)]
        XCTAssertEqual(Set(BrowserModel.cookies(cookies, for: URL(string: "https://cdn.example.com/video.mp4")!).map(\.name)), ["host", "domain", "secure"])
        XCTAssertEqual(Set(BrowserModel.cookies(cookies, for: URL(string: "http://cdn.example.com/video.mp4")!).map(\.name)), ["host", "domain"])
        XCTAssertTrue(BrowserModel.cookies(cookies, for: URL(string: "https://example.com.evil.test/video.mp4")!).allSatisfy { $0.name == "other" })
        XCTAssertFalse(BrowserModel.cookies(cookies, for: URL(string: "https://cdn.example.com/private-copy/video.mp4")!).contains { $0.name == "path" })
    }
}
