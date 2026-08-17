import SwiftUI
import EphemerisKit

/// Settings sheet — language today, room for more later.
/// Presented from a toolbar gear, matching the `TimeZonePicker`/`LocationPicker` idiom rather
/// than spending a tab (iOS collapses a 6th tab into "More", which would break the floating
/// Liquid Glass bar).
struct SettingsView: View {
    @EnvironmentObject private var language: LanguageStore
    /// The frame belongs to the chart, so it is set on the view model rather than kept here.
    @ObservedObject var vm: ChartViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var moon = MoonNotifications()
    @AppStorage("moon.voidOfCourse") private var showVoid = false
    @AppStorage("assistant.enabled") private var assistantEnabled = false

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
                // Off by default. An assistant that appears uninvited in a tool whose value is
                // precision reads as a gimmick; one the user switched on reads as help.
                Section("Explanations") {
                    Toggle("Explain this screen", isOn: $assistantEnabled)
                        .accessibilityIdentifier("settings.assistant")
                    Text("Adds a ✨ button that answers questions about whatever screen you are on, using Apple Intelligence on your device. Nothing is sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let reason = AssistantEngine.unavailableReason() {
                        Text(verbatim: reason.message)
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.assistantUnavailable")
                    }
                }

                // A SETTING, not a screen. The same chart re-read from a different origin — any
                // design that gave sidereal its own wheel would have misunderstood the function.
                Section("Zodiac") {
                    Picker("Zodiac", selection: Binding(
                        get: { vm.zodiac },
                        set: { vm.zodiac = $0 })) {
                        Text("Tropical").tag(Ayanamsa?.none)
                        ForEach(Ayanamsa.allCases) { a in
                            Text(verbatim: a.displayName).tag(Ayanamsa?.some(a))
                        }
                    }
                    .accessibilityIdentifier("settings.zodiac")

                    // ⚠️ The active system and its current value must be visible. A practitioner
                    // comparing two charts needs to know which frame produced what they are
                    // looking at, and the systems differ by up to 1°27′ — more than enough to move
                    // a body across a sign boundary.
                    if let z = vm.zodiac {
                        Text("\(z.displayName) ayanamsa: \(Self.dms(z.value(at: vm.instant)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.ayanamsaValue")
                    } else {
                        Text("Longitudes are measured from the vernal equinox.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.tropicalNote")
                    }
                }

                // The ONLY place notification permission is ever requested. Asking on launch would
                // put a system alert in front of a user who has not seen the app yet, which this
                // app does not do — every modal opens from a tap.
                Section("Moon alerts") {
                    Toggle("Full and new moon", isOn: Binding(
                        get: { moon.enabled },
                        set: { want in
                            if want {
                                Task { await moon.requestAndEnable() }
                            } else {
                                moon.enabled = false
                            }
                        }))
                    .accessibilityIdentifier("settings.moonAlerts")

                    // Practitioner tool, off by default — it means nothing to most of the audience
                    // a moon calendar serves.
                    Toggle("Show void-of-course", isOn: $showVoid)
                        .accessibilityIdentifier("settings.voidOfCourse")

                    if moon.authorization == .denied {
                        Text("Notifications are turned off for Ephemeris in System Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.moonAlertsDenied")
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
            // Reads the current status so a permission revoked in System Settings shows up here
            // rather than leaving the toggle claiming alerts are on. Reads only — never requests.
            .task { await moon.readAuthorization() }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

extension SettingsView {
    /// Degrees to d°mm′ss″ — the form an ayanamsa is published in, so it can be checked against a
    /// printed table without conversion.
    static func dms(_ degrees: Double) -> String {
        let total = Int((degrees * 3600).rounded())
        return "\(total / 3600)°\(String(format: "%02d", (total % 3600) / 60))′"
             + String(format: "%02d", total % 60) + "″"
    }
}

/// The gear that opens it — one modifier so both platform shells stay identical.
struct SettingsToolbar: ViewModifier {
    @ObservedObject var vm: ChartViewModel
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showing = true } label: { Image(systemName: "gearshape") }
                        .help("Settings")
                }
            }
            .sheet(isPresented: $showing) { SettingsView(vm: vm) }
    }
}

extension View {
    func settingsToolbar(vm: ChartViewModel) -> some View { modifier(SettingsToolbar(vm: vm)) }
}
