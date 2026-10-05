import AVFoundation

struct NativeCaptionPreference {
    let enabled: Bool
    let language: String
    let known: Bool

    init(_ value: [String: Any]?) {
        known = value?["known"] as? Bool ?? true
        enabled = value?["enabled"] as? Bool ?? false
        language = String((value?["language"] as? String ?? "").prefix(128))
    }

    static func matches(_ language: String, nativeTag: String) -> Bool {
        let requested = language.lowercased().replacingOccurrences(of: "_", with: "-")
        let native = nativeTag.lowercased().replacingOccurrences(of: "_", with: "-")
        return !requested.isEmpty && !native.isEmpty &&
            (requested == native || requested.split(separator: "-").first == native.split(separator: "-").first)
    }

    @MainActor func apply(to item: AVPlayerItem) async throws {
        guard known else { throw VideoError.noNativeCaptions }
        guard enabled else { return }
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible), !group.options.isEmpty else {
            throw VideoError.noNativeCaptions
        }
        guard let option = group.options.first(where: {
            Self.matches(language, nativeTag: $0.extendedLanguageTag ?? $0.locale?.identifier ?? "")
        }) else { throw VideoError.noNativeCaptions }
        item.select(option, in: group)
    }
}
