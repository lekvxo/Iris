import AVFoundation

struct NativeCaptionPreference {
    let enabled: Bool
    let language: String

    init(_ value: [String: Any]?) {
        enabled = value?["enabled"] as? Bool ?? false
        language = String((value?["language"] as? String ?? "").prefix(128))
    }

    @MainActor func apply(to item: AVPlayerItem) async throws {
        guard enabled else { return }
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible), !group.options.isEmpty else {
            throw VideoError.noNativeCaptions
        }
        let language = language.lowercased()
        let option = group.options.first {
            let tag = ($0.extendedLanguageTag ?? $0.locale?.identifier ?? "").lowercased().replacingOccurrences(of: "_", with: "-")
            return !language.isEmpty && (tag == language || tag.split(separator: "-").first == language.split(separator: "-").first)
        } ?? group.defaultOption ?? group.options[0]
        item.select(option, in: group)
    }
}
