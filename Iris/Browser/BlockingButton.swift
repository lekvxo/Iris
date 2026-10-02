import SwiftUI

struct BlockingButton: View {
    let model: BrowserModel
    @Environment(SettingsStore.self) private var settings
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label {
                // The existing ornament is an HStack, not a ToolbarItem host.
                // Use the system button label instead of drawing a badge bubble.
                Text(model.blockingActivity.badgeTitle).font(.caption).monospacedDigit()
            } icon: {
                Image(systemName: settings.blockingActive(for: model.url) ? "shield.fill" : "shield.slash")
            }
        }
        .labelStyle(.titleAndIcon)
        .hoverEffect()
        .help("Site protection")
        .accessibilityLabel("Site protection")
        .accessibilityValue(model.blockingActivity.summary)
        .popover(isPresented: $isPresented) {
            BlockingPopover(model: model)
                .id(model.blockingActivity.pageID)
        }
    }
}

private struct BlockingPopover: View {
    let model: BrowserModel
    @Environment(SettingsStore.self) private var settings
    @State private var detailsExpanded = false

    private var site: String? {
        model.url?.host.map(PublicSuffix.bundled.registrableDomain)
    }

    private var siteBlocking: Binding<Bool> {
        Binding {
            settings.blockingActive(for: model.url)
        } set: { enabled in
            guard let site, settings.blockingEnabled else { return }
            settings.setBlockingDisabled(!enabled, on: site)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Label("Site protection", systemImage: "shield")
                .font(.headline)
            Text(site ?? "This page").font(.subheadline).foregroundStyle(.secondary)
            Text(model.blockingActivity.summary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Block ads and trackers on this site", isOn: siteBlocking)
                .disabled(site == nil || !settings.blockingEnabled)
            if !settings.blockingEnabled {
                Text("Turn on blocking in Settings to use this switch.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Popup and redirect protection stays on. Ad and tracker counts aren't available.")
                .font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                if model.blockingActivity.items.isEmpty {
                    Text("No blocked destinations yet.").foregroundStyle(.secondary)
                } else {
                    List(model.blockingActivity.items) { item in
                        VStack(alignment: .leading) {
                            Label(item.title, systemImage: item.symbol)
                            Text(item.url.absoluteString)
                                .font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: min(CGFloat(model.blockingActivity.count) * 72, 240))
                    Text(model.blockingActivity.hasMore ? "Showing the first 200 destinations." : "Each destination is counted once.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 360)
        .glassBackgroundEffect()
    }
}
