import SwiftUI
import SwiftData

struct BrowserWindow: View {
    let initialURL: URL?
    @State private var model = BrowserModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(SettingsStore.self) private var settings
    @State private var showingSettings = false
    @State private var showingSaved = false
    @State private var confirmingRemoval: SavedSite?
    @Query private var savedSites: [SavedSite]
    @SceneStorage("lastURL") private var lastURL: String?

    var body: some View {
        // A restored window resumes where the user left it, not at the link that opened it.
        WebView(model: model, initialURL: lastURL.flatMap(URL.init(string:)) ?? initialURL ?? URL(string: "https://www.google.com")!, settings: settings)
            .overlay {
                if settings.blocker.isUpdating && !settings.blocker.isReady && model.url == nil {
                    ProgressView("Preparing content blocking…").padding(24).glassBackgroundEffect()
                }
                if let error = model.error {
                    ContentUnavailableView {
                        Label("Unable to load page", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try again") {
                            if let url = model.requestedURL ?? model.url { model.load(url) }
                        }.hoverEffect()
                    }.padding().glassBackgroundEffect()
                }
            }
            // Chips sit over the page so they never shift the toolbar under the user's gaze.
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                if let error = model.saveError {
                    HStack {
                        Text(error).font(.caption)
                        Button("Dismiss", systemImage: "xmark") { model.saveError = nil }
                            .labelStyle(.iconOnly).hoverEffect()
                    }.padding(8).glassBackgroundEffect()
                }
                if let reason = model.videoError ?? model.watchReason(native: settings.nativeVideo), model.video != nil {
                    Text(reason).font(.caption).padding(8).glassBackgroundEffect()
                } else if settings.nativeVideo, model.video?.descriptor.drm == true {
                    Text("Protected video uses website fullscreen").font(.caption).padding(8).glassBackgroundEffect()
                }
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
                            settings.allowNavigation(on: blocked.sourceSite, allow: true)
                            model.blocked = nil
                            if blocked.popup { model.openWindow?(blocked.url) } else { model.load(blocked.url) }
                        }.hoverEffect().disabled(blocked.sourceSite.isEmpty)
                        Button("Dismiss", systemImage: "xmark") { model.blocked = nil }
                            .labelStyle(.iconOnly).hoverEffect()
                    }.padding(10).glassBackgroundEffect()
                }
                }
                .padding(.top, 12)
            }
            .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
                HStack(spacing: 8) {
                    tool("Back", "chevron.left", disabled: !model.canGoBack) { model.webView?.goBack() }
                    tool("Forward", "chevron.right", disabled: !model.canGoForward) { model.webView?.goForward() }
                    tool(model.isLoading ? "Stop" : "Reload", model.isLoading ? "xmark" : "arrow.clockwise") {
                        if model.isLoading { model.webView?.stopLoading() } else { model.webView?.reload() }
                    }
                    AddressField(text: model.url?.absoluteString ?? "") { model.load(InputRouter.destination(for: $0)) }
                        .frame(width: 420, height: 44)
                        .disabled(model.isInitializing)
                    Menu {
                        Button("Save offline copy", systemImage: "arrow.down.doc") {
                            Task { await model.saveOffline(existing: currentSavedSite, settings: settings) }
                        }.disabled(model.isSavingOffline)
                    } label: {
                        Label(currentSavedSite == nil ? "Save site" : "Remove saved site",
                              systemImage: currentSavedSite == nil ? "star" : "star.fill")
                            .labelStyle(.iconOnly)
                    } primaryAction: { toggleSave() }
                    .disabled(model.url?.host == nil).hoverEffect()
                    .confirmationDialog("Remove saved site?", isPresented: Binding(get: { confirmingRemoval != nil },
                                                                                   set: { if !$0 { confirmingRemoval = nil } }),
                                        presenting: confirmingRemoval) { site in
                        Button("Remove", role: .destructive) {
                            Task { model.saveError = await settings.removeSaved(site) }
                        }
                    } message: { site in
                        Text(site.archiveFileName == nil ? site.title : "\(site.title) and its offline copy will be deleted.")
                    }
                    tool("Saved sites", "book", disabled: model.isInitializing) { showingSaved = true }
                        .popover(isPresented: $showingSaved) {
                            SavedListView { site in
                                if let url = URL(string: site.url) {
                                    site.lastOpened = Date()
                                    settings.save()
                                    model.load(url)
                                    showingSaved = false
                                }
                            } openOffline: { site in
                                showingSaved = false
                                Task { await model.openArchive(site, settings: settings) }
                            }
                        }
                    tool("Watch in Player", "play.rectangle",
                         disabled: model.isPreparingVideo || model.watchReason(native: settings.nativeVideo) != nil) {
                        let native = settings.nativeVideo
                        model.videoTask = Task { [weak model = model] in
                            if native { await model?.enterNativeFullscreen() }
                            else { await model?.prepareHandoff() }
                        }
                    }
                    tool(settings.blockingActive(for: model.url) ? "Blocking on" : "Blocking off",
                         settings.blockingActive(for: model.url) ? "shield.fill" : "shield.slash",
                         disabled: model.url?.host == nil || !settings.blockingEnabled) {
                        settings.toggleBlocking(for: model.url)
                    }
                    tool("Settings", "gear") { showingSettings = true }
                }
                .padding(12)
                .glassBackgroundEffect()
                // Overlaid so showing progress never changes the toolbar's size.
                .overlay(alignment: .bottom) {
                    if model.isLoading {
                        ProgressView(value: model.estimatedProgress)
                            .progressViewStyle(.linear).frame(height: 3).padding(.horizontal, 28)
                    }
                }
            }
            .onChange(of: model.url) { _, url in
                if let url { lastURL = url.absoluteString }
            }
            .onAppear {
                model.openWindow = { openWindow(id: "browser", value: WindowRequest(url: $0)) }
                model.allowedSites = settings.navigationSites
            }
            .onChange(of: settings.navigationSites) { _, sites in model.allowedSites = sites }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .fullScreenCover(isPresented: Binding(get: { model.playerSession != nil }, set: { visible in
                if !visible { Task { await model.closePlayer() } }
            })) {
                if let session = model.playerSession {
                    PlayerScreen(session: session) { Task { await model.closePlayer() } }
                }
            }
    }

    private var currentSavedSite: SavedSite? {
        savedSites.first { $0.url == model.url?.absoluteString }
    }

    private func toggleSave() {
        guard let url = model.url else { return }
        if let site = currentSavedSite {
            confirmingRemoval = site
        } else {
            settings.container.mainContext.insert(SavedSite(url: url, title: model.title))
            settings.save()
            model.saveError = settings.persistenceError
        }
    }

    private func tool(_ title: String, _ icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: action)
            .labelStyle(.iconOnly)
            .disabled(disabled)
            .hoverEffect()
            .help(title)
    }
}
