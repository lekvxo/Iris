import WebKit

extension WKWebView {
    func irisArchiveData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createWebArchiveData { result in continuation.resume(with: result) }
        }
    }
}
