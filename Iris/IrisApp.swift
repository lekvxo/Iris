import SwiftUI
import AppIntents

@main
struct IrisApp: App {
    var body: some Scene {
        WindowGroup(id: "browser", for: URL.self) { $url in
            BrowserWindow(initialURL: url)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
