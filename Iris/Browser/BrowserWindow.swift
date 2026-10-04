import SwiftUI
import SwiftData

struct BrowserWindow: View {
    let initialURL: URL?
    @State private var tabs: BrowserTabs
    private var model: BrowserModel { tabs.selected.model }
    @State private var windowID = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    @State private var showingSettings = false
    @State private var showingSaved = false
    @State private var confirmingRemoval: SavedSite?
    @Query private var savedSites: [SavedSite]
    @SceneStorage("lastURL") private var lastURL: String?
    @SceneStorage("browserTabs") private var restoredTabs = ""
    @State private var restorationReady = false

    init(initialURL: URL?, popupID: UUID? = nil) {
        self.initialURL = initialURL
        _tabs = State(initialValue: BrowserTabs(url: initialURL, popupID: popupID))
    }

    var body: some View {
        ZStack {
            browser
                .opacity(model.playerSession == nil ? 1 : 0)
                .allowsHitTesting(model.playerSession == nil)
                .accessibilityHidden(model.playerSession != nil)
            if let session = model.playerSession {
                PlayerScreen(session: session) { Task { await model.closePlayer() } }
                    .id(session.id)
            }
        }
    }

    // Keep WebKit mounted while AVKit owns the window, preserving history and page state.
    private var browser: some View {
        // A restored window resumes where the user left it, not at the link that opened it.
        ZStack {
            if restorationReady {
                ForEach(tabs.tabs.filter(\.hasBeenSelected)) { tab in
                    WebView(model: tab.model, initialURL: tab.initialURL, settings: settings, probeInterval: settings.energy.probeInterval)
                        .opacity(tab.id == tabs.selectedID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabs.selectedID)
                        .accessibilityHidden(tab.id != tabs.selectedID)
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if !settings.blocker.isReady && model.isInitializing {
                    VStack {
                        ProgressView("Preparing content blocking…")
                        if let status = settings.blocker.status { Text(status).font(.caption) }
                    }.padding(24).glassBackgroundEffect()
                }
                if let error = model.error {
                    ContentUnavailableView {
                        Label("Unable to load page", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try again") {
                            Task { await model.retryPage(settings: settings) }
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
                if model.video != nil, let note = model.videoNote(native: settings.nativeVideo) {
                    HStack {
                        Text(note).font(.caption)
                        Button("Dismiss", systemImage: "xmark") { model.dismissVideoNote() }
                            .labelStyle(.iconOnly).hoverEffect()
                    }.padding(8).glassBackgroundEffect()
                }
                if let blocked = model.blocked {
                    HStack {
                        Text("Blocked \(blocked.popup ? "popup" : "redirect") to \(blocked.url.host ?? "website")")
                            .lineLimit(1)
                        Button("Open once") {
                            model.blocked = nil
                            if blocked.popup { model.openWindow?(WindowRequest(url: blocked.url)) } else { model.load(blocked.url) }
                        }.hoverEffect()
                        Button("Always allow on this site") {
                            model.allowedSites.insert(blocked.sourceSite)
                            settings.allowNavigation(on: blocked.sourceSite, allow: true)
                            model.blocked = nil
                            if blocked.popup { model.openWindow?(WindowRequest(url: blocked.url)) } else { model.load(blocked.url) }
                        }.hoverEffect().disabled(blocked.sourceSite.isEmpty)
                        Button("Dismiss", systemImage: "xmark") { model.blocked = nil }
                            .labelStyle(.iconOnly).hoverEffect()
                    }.padding(10).glassBackgroundEffect()
                }
                }
                .padding(.top, 12)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack {
                tabStrip
                HStack(spacing: 8) {
                    tool("Back", "chevron.left", disabled: !model.canGoBack) { model.webView?.goBack() }
                    tool("Forward", "chevron.right", disabled: !model.canGoForward) { model.webView?.goForward() }
                    tool(model.isLoading ? "Stop" : "Reload", model.isLoading ? "xmark" : "arrow.clockwise") {
                        if model.isLoading {
                            (model.webView?.navigationDelegate as? WebView.Coordinator)?.policyTask?.cancel()
                            model.webView?.stopLoading()
                        } else { Task { await model.reloadPage(settings: settings) } }
                    }
                    AddressField(text: model.url?.absoluteString ?? "") { model.load(InputRouter.destination(for: $0)) }
                        .frame(minWidth: 180, maxWidth: .infinity)
                        .frame(height: 44)
                        .layoutPriority(1)
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
                            } openHistory: { url in
                                model.load(url)
                                showingSaved = false
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
                    BlockingButton(model: model)
                    tool("Settings", "gear") { showingSettings = true }
                }
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
                if !restorationReady {
                    if initialURL == nil, !restoredTabs.isEmpty { tabs.restore(restoredTabs) }
                    else if initialURL == nil, let lastURL, let url = URL(string: lastURL) { tabs = BrowserTabs(url: url) }
                    restorationReady = true
                }
                updateActivity()
                for tab in tabs.tabs { tab.model.allowedSites = settings.navigationSites }
            }
            .onChange(of: tabs.snapshot) { _, value in restoredTabs = value }
            .onChange(of: tabs.selectedID) { _, _ in updateActivity() }
            .onChange(of: tabs.tabs.count) { _, _ in
                for tab in tabs.tabs { tab.model.allowedSites = settings.navigationSites }
                updateActivity()
            }
            .onChange(of: scenePhase) { _, _ in updateActivity() }
            .onDisappear { settings.energy.setForeground(false, window: windowID) }
            .onChange(of: settings.navigationSites) { _, sites in
                for tab in tabs.tabs { tab.model.allowedSites = sites }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }

    }

    private func updateActivity() {
        // Inactive is not background: system focus changes must not pause legitimate audio.
        for tab in tabs.tabs {
            tab.model.isBackgrounded = scenePhase == .background || tab.id != tabs.selectedID
            if let view = tab.model.webView, let coordinator = view.navigationDelegate as? WebView.Coordinator {
                coordinator.updateVideoPolicy(view)
            }
        }
        settings.energy.setForeground(scenePhase != .background, window: windowID)
    }

    private var tabStrip: some View {
        HStack {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(tabs.ordered) { tab in
                        HStack {
                            Button {
                                tabs.select(tab.id)
                            } label: {
                                Label(tab.title, systemImage: tab.isPinned ? "pin.fill" : "globe")
                                    .lineLimit(1).frame(maxWidth: 180)
                            }
                            .tint(tab.id == tabs.selectedID ? .accentColor : .secondary)
                            .accessibilityAddTraits(tab.id == tabs.selectedID ? .isSelected : [])
                            .contextMenu {
                                Button(tab.isPinned ? "Unpin tab" : "Pin tab", systemImage: tab.isPinned ? "pin.slash" : "pin") {
                                    tab.isPinned.toggle()
                                }
                                Button("Close tab", systemImage: "xmark", role: .destructive) { tabs.close(tab.id) }
                            }
                            Button("Close \(tab.title)", systemImage: "xmark") { tabs.close(tab.id) }
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }.scrollIndicators(.hidden)
            Menu {
                Button(tabs.selected.isPinned ? "Unpin current tab" : "Pin current tab", systemImage: "pin") {
                    tabs.selected.isPinned.toggle()
                }
            } label: { Label("Tab options", systemImage: "ellipsis") }.labelStyle(.iconOnly)
            tool("New tab", "plus") { tabs.open() }
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
