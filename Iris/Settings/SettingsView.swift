import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
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
