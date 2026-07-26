import SwiftUI

/// The app's only settings screen: pick a language, or leave it following the device.
/// Presented as a sheet on iOS and as the `Settings` scene (⌘,) on macOS.
struct SettingsView: View {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $language.selected) {
                    ForEach(AppLanguage.allCases) { lang in
                        // Endonyms are shown untranslated — someone hunting for this menu may not
                        // read the language currently on screen. "System" is the exception.
                        if let endonym = lang.endonym {
                            Text(verbatim: endonym).tag(lang)
                        } else {
                            Text("System").tag(lang)
                        }
                    }
                } label: {
                    Text("Language")
                }
            } footer: {
                Text("Follows your device unless you pick a language here.")
            }

            Section {
                // Interpolating a LocalizedStringKey gives the catalog key "Version %@", which is
                // what lets hu put the number first ("%@ verzió").
                Text("Version \(version)")
                    .foregroundStyle(OTL.textSecondary)
                Text("Offline · no account · no tracking")
                    .font(.footnote)
                    .foregroundStyle(OTL.textSecondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .tint(ToolSection.signal.accent)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }
}
