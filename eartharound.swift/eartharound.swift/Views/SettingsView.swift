import SwiftUI
import SpaceWeatherFeed

/// Preference keys + option lists, shared between the settings sheet and the root
/// shell so the two never drift. Defaults keep the main UI clean — power options live
/// only here, behind the gear.
enum Prefs {
    static let refreshMinutes = "refreshMinutes"   // 0 = off
    static let showForecast = "showForecast"
    static let hpoRangeHours = "hpoRangeHours"

    static let refreshOptions: [(Int, String)] = [(0, "Off"), (1, "1 min"), (5, "5 min"), (15, "15 min")]
    static let rangeOptions: [(Double, String)] = [(24, "1 day"), (72, "3 days"), (168, "7 days")]
}

/// Clean, grouped settings. The complexity lives here so the dashboard stays minimal.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sw) private var sw
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var mode: ModeStore
    @EnvironmentObject private var language: LanguageStore
    @AppStorage(Prefs.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(Prefs.showForecast) private var showForecast = true
    @AppStorage(Prefs.hpoRangeHours) private var hpoRangeHours = 168.0

    // Alert prefs live in the app group — the background task and widgets read them
    // through SharedStore. Defaults mirror AlertPrefs (master off; categories on).
    @AppStorage(SharedStore.Key.cellular, store: AppGroup.defaults) private var cellularAllowed = true
    @AppStorage(SharedStore.Key.alertsEnabled, store: AppGroup.defaults) private var alertsEnabled = false
    @AppStorage(SharedStore.Key.alertStorms, store: AppGroup.defaults) private var alertStorms = true
    @AppStorage(SharedStore.Key.alertStormThreshold, store: AppGroup.defaults) private var alertStormThreshold = 1
    @AppStorage(SharedStore.Key.alertFlares, store: AppGroup.defaults) private var alertFlares = true
    @AppStorage(SharedStore.Key.alertAurora, store: AppGroup.defaults) private var alertAurora = true
    @AppStorage(SharedStore.Key.alertAuroraThreshold, store: AppGroup.defaults) private var alertAuroraThreshold = 50

    private var languageChoice: Binding<SWLanguage> {
        Binding(get: { language.selected }, set: { language.selected = $0 })
    }

    private var nightMode: Binding<Bool> {
        Binding(get: { theme.selected == .night },
                set: { theme.selected = $0 ? .night : .dark })
    }

    private var alertsFootnote: String {
        #if os(macOS)
        "Alerts fire while the app is running (it checks on the auto-refresh interval). Same no-false-alarm rule as the dashboard: one notification per event, validated against the published NOAA scales."
        #else
        "Checked in the background when iOS allows — typically a few times a day, not a real-time alarm. One notification per event, validated against the published NOAA scales."
        #endif
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(v)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(SWText.str("Live data")) {
                    Picker(SWText.str("Auto-refresh"), selection: $refreshMinutes) {
                        ForEach(Prefs.refreshOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .accessibilityIdentifier("settings.refreshMinutes")
                    Toggle(SWText.str("Use cellular data"), isOn: $cellularAllowed)
                    .accessibilityIdentifier("settings.cellular")
                    Text(cellularAllowed
                         ? "Refreshes over Wi-Fi and cellular. A refresh is a few hundred kilobytes."
                         : "Refreshes only on Wi-Fi. On cellular the app pauses and keeps showing the last reading rather than failing silently.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(SWText.str("Display")) {
                    Picker(SWText.str("Hp30 default range"), selection: $hpoRangeHours) {
                        ForEach(Prefs.rangeOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .accessibilityIdentifier("settings.hpoRangeHours")
                    Toggle(SWText.str("Show Kp forecast bars"), isOn: $showForecast)
                    .accessibilityIdentifier("settings.showForecast")
                    Toggle(SWText.str("Night mode (red-shift)"), isOn: nightMode)
                    .accessibilityIdentifier("settings.nightMode")
                    // Endonyms, never translated: someone who needs this menu may not read the
                    // language the app is currently showing.
                    Picker(SWText.str("Language"), selection: languageChoice) {
                        ForEach(SWLanguage.allCases) { Text(verbatim: $0.endonym).tag($0) }
                    }
                    .accessibilityIdentifier("settings.language")
                }
                Section(SWText.str("Alerts")) {
                    Toggle(SWText.str("Space event alerts"), isOn: $alertsEnabled)
                    .accessibilityIdentifier("settings.alertsEnabled")
                        .onChange(of: alertsEnabled) { _, on in
                            if on { Task { alertsEnabled = await AlertNotifier.requestAuthorization() } }
                        }
                    if alertsEnabled {
                        Toggle(SWText.str("Geomagnetic storms"), isOn: $alertStorms)
                        .accessibilityIdentifier("settings.alertStorms")
                        if alertStorms {
                            Picker(SWText.str("Notify from"), selection: $alertStormThreshold) {
                                ForEach(1...4, id: \.self) { Text(SWText.str("G\($0)+")).tag($0) }
                            }
                            .accessibilityIdentifier("settings.alertStormThreshold")
                        }
                        Toggle(SWText.str("Solar flares (M-class and up)"), isOn: $alertFlares)
                        .accessibilityIdentifier("settings.alertFlares")
                        Toggle(SWText.str("Aurora chance"), isOn: $alertAurora)
                        .accessibilityIdentifier("settings.alertAurora")
                        if alertAurora {
                            Picker(SWText.str("From probability"), selection: $alertAuroraThreshold) {
                                ForEach([30, 50, 70], id: \.self) { Text(SWText.str("\($0)%")).tag($0) }
                            }
                            .accessibilityIdentifier("settings.alertAuroraThreshold")
                        }
                    }
                    Text(alertsFootnote)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(SWText.str("Sources")) {
                    LabeledContent(SWText.str("Geomagnetic & Hpo"), value: "GFZ Potsdam")
                    LabeledContent(SWText.str("Solar, wind & scales"), value: "NOAA SWPC")
                    Text(SWText.str("Every displayed value is classified by a local, offline-tested function checked against the published NOAA/GFZ definition. No number is shown that can't be validated."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(SWText.str("About")) {
                    LabeledContent(SWText.str("App"), value: version)
                    Label(SWText.str("Ad-free · one-time purchase"), systemImage: "checkmark.seal")
                        .foregroundStyle(sw.brand)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(SWText.str("Done")) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
