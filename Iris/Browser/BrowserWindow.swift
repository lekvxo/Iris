import SwiftUI

struct BrowserWindow: View {
    let initialURL: URL?
    @State private var model = BrowserModel()
    @State private var address = ""
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("lastURL") private var lastURL = "https://www.google.com"

    var body: some View {
        WebView(model: model, initialURL: initialURL ?? URL(string: lastURL) ?? URL(string: "https://www.google.com")!)
            .overlay {
                if let error = model.error {
                    ContentUnavailableView {
                        Label("Unable to load page", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try again") {
                            model.load(model.url ?? InputRouter.destination(for: address))
                        }.hoverEffect()
                    }.padding().glassBackgroundEffect()
                }
            }
            .ornament(attachmentAnchor: .scene(.top)) {
                VStack(spacing: 6) {
                HStack(spacing: 8) {
                    tool("Back", "chevron.left", disabled: !model.canGoBack) { model.webView?.goBack() }
                    tool("Forward", "chevron.right", disabled: !model.canGoForward) { model.webView?.goForward() }
                    tool(model.isLoading ? "Stop" : "Reload", model.isLoading ? "xmark" : "arrow.clockwise") {
                        if model.isLoading { model.webView?.stopLoading() } else { model.webView?.reload() }
                    }
                    AddressField(text: $address) { model.load(InputRouter.destination(for: address)) }
                        .frame(width: 420, height: 44)
                    tool("Save", "star", disabled: true) {}
                    tool("Saved sites", "book", disabled: true) {}
                    tool("Watch in Player", "play.rectangle", disabled: true) {}
                    tool("Blocking", "shield", disabled: true) {}
                }
                .padding(12)
                .glassBackgroundEffect()
                if let blocked = model.blocked {
                    HStack {
                        Text("Blocked \(blocked.popup ? "popup" : "redirect") to \(blocked.url.host ?? "website")")
                            .lineLimit(1)
                        Button("Open once") {
                            model.blocked = nil
                            if blocked.popup { model.openWindow?(blocked.url) } else { model.load(blocked.url) }
                        }.hoverEffect()
                        Button("Always allow on this site") {
                            model.allowedSites.insert(blocked.sourceSite)
                            model.blocked = nil
                            if blocked.popup { model.openWindow?(blocked.url) } else { model.load(blocked.url) }
                        }.hoverEffect().disabled(blocked.sourceSite.isEmpty)
                        Button("Dismiss", systemImage: "xmark") { model.blocked = nil }
                            .labelStyle(.iconOnly).hoverEffect()
                    }.padding(10).glassBackgroundEffect()
                }
                }
            }
            .onChange(of: model.url) { _, url in
                address = url?.absoluteString ?? ""
                if let url { lastURL = url.absoluteString }
            }
            .onAppear { model.openWindow = { openWindow(id: "browser", value: $0) } }
    }

    private func tool(_ title: String, _ icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: action)
            .labelStyle(.iconOnly)
            .disabled(disabled)
            .hoverEffect()
            .help(title)
    }
}
