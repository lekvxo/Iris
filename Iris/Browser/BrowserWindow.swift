import SwiftUI

struct BrowserWindow: View {
    let initialURL: URL?
    @State private var model = BrowserModel()
    @State private var address = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WebView(model: model, initialURL: initialURL ?? URL(string: "https://www.google.com")!)
            .ornament(attachmentAnchor: .scene(.top)) {
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
            }
            .onChange(of: model.url) { _, url in address = url?.absoluteString ?? "" }
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
