import SwiftUI

/// Settings sheet — language today, room for more later.
/// Presented from a toolbar gear, matching the `TimeZonePicker`/`LocationPicker` idiom rather
/// than spending a tab (iOS collapses a 6th tab into "More", which would break the floating
/// Liquid Glass bar).
struct SettingsView: View {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Language", selection: $language.selected) {
                        // Endonyms are never translated: someone looking for this menu may not
                        // read the language the app is currently showing.
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.endonym).tag($0) }
                    }
                }
                Section("Accuracy") {
                    Text("Positions are validated against NASA/JPL Horizons across 1900–2100: better than 7 arcminutes for every body.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

/// The gear that opens it — one modifier so both platform shells stay identical.
struct SettingsToolbar: ViewModifier {
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showing = true } label: { Image(systemName: "gearshape") }
                        .help("Settings")
                }
            }
            .sheet(isPresented: $showing) { SettingsView() }
    }
}

extension View {
    func settingsToolbar() -> some View { modifier(SettingsToolbar()) }
}
