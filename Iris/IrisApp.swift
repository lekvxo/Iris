import SwiftUI
import AppIntents

@main
struct IrisApp: App {
    @State private var settings = SettingsStore()
    var body: some Scene {
        WindowGroup(id: "browser", for: URL.self) { $url in
            BrowserWindow(initialURL: url)
                .environment(settings)
                .modelContainer(settings.container)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
