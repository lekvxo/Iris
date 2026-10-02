import SwiftUI

struct ClearHistoryButton: View {
    @Environment(SettingsStore.self) private var settings
    @State private var confirming = false
    static let footer = "Clearing history keeps website data, saved sites and offline copies. Back and Forward still work in open windows until you close them."

    var body: some View {
        Button("Clear…", role: .destructive) { confirming = true }
            .hoverEffect()
            .confirmationDialog("Clear browsing history?", isPresented: $confirming, titleVisibility: .visible) {
                ForEach(HistoryClearRange.allCases) { range in
                    Button(range.title, role: .destructive) { settings.history.clear(range) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text(Self.footer) }
    }
}
