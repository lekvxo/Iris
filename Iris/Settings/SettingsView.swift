import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var clearingData = false
    @State private var confirmingClear = false
    @State private var dataStatus: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Browsing") {
                    Toggle("Ad and tracker blocking", isOn: Binding(get: { settings.blockingEnabled }, set: { settings.blockingEnabled = $0 }))
                    Button(clearingData ? "Clearing…" : "Clear website data", role: .destructive) {
                        confirmingClear = true
                    }.disabled(clearingData).hoverEffect()
                    .confirmationDialog("Clear all website data?", isPresented: $confirmingClear) {
                        Button("Clear data", role: .destructive) {
                            clearingData = true
                            dataStatus = nil
                            Task {
                                await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                                settings.blocker.applyToAll(reload: true)
                                clearingData = false
                                dataStatus = "Website data cleared"
                            }
                        }
                    } message: { Text("You will be signed out of every website.") }
                    Text("Clearing data signs you out of websites. Your saved sites and offline copies are kept.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let dataStatus { Text(dataStatus).font(.footnote) }
                }
                Section("Watch in Player") {
                    Toggle("Use website native fullscreen", isOn: Binding(get: { settings.nativeVideo }, set: { settings.nativeVideo = $0 }))
                    Text(settings.nativeVideo
                         ? "Requests fullscreen on the detected video, including website streams. Headset testing determines which player and environments the website offers."
                         : "Hands direct MP4 and HLS sources to Apple's player. Protected videos and streams without an observed HLS source stay on the website.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Filter lists") {
                    if let date = settings.blocker.lastUpdated {
                        LabeledContent("Last updated", value: date.formatted(date: .abbreviated, time: .shortened))
                        Text("\(settings.blocker.ruleCount.formatted()) compiled rules")
                    } else { Text("Lists have not been updated yet") }
                    Button(settings.blocker.isUpdating ? "Updating…" : "Update lists now") {
                        Task { await settings.blocker.refresh() }
                    }.disabled(settings.blocker.isUpdating).hoverEffect()
                    if let status = settings.blocker.status { Text(status).foregroundStyle(.orange) }
                }
                Section("Allow popups and redirects") {
                    if settings.navigationSites.isEmpty { Text("No site exceptions") }
                    ForEach(settings.permissions.filter(\.allowsNavigation), id: \.domain) { permission in
                        HStack {
                            Text(permission.domain)
                            Spacer()
                            Button("Remove") { settings.allowNavigation(on: permission.domain, allow: false) }.hoverEffect()
                        }
                    }
                    Text("Sign-in hosts allowed: accounts.google.com, appleid.apple.com, login.microsoftonline.com, github.com.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = settings.persistenceError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Iris Settings")
            .toolbar { Button("Done") { dismiss() }.hoverEffect() }
        }.frame(width: 650, height: 560)
    }
}
