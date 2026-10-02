import SwiftUI
import AppIntents
import SwiftData

@main
struct IrisApp: App {
    @State private var settings = SettingsStore()
    var body: some Scene {
        WindowGroup(id: "browser", for: WindowRequest.self) { $request in
            Group {
            if ProcessInfo.processInfo.environment["IRIS_UNIT_TEST_HOST"] == "1" {
                Color.clear
            } else {
            BrowserWindow(initialURL: request?.url, popupID: request?.id)
            }
            }
                .environment(settings)
                .modelContainer(settings.container)
        }
        .defaultSize(width: 1100, height: 760)
    }
}

// A fresh id per request, so opening a URL that is already open still makes a new window.
struct WindowRequest: Codable, Hashable {
    var id = UUID()
    var url: URL
}
