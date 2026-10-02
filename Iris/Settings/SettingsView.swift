import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
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
