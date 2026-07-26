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

    private var detailMode: Binding<SWMode> {
        Binding(get: { mode.selected }, set: { mode.selected = $0 })
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
                Section("Live data") {
                    Picker("Auto-refresh", selection: $refreshMinutes) {
                        ForEach(Prefs.refreshOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Toggle("Use cellular data", isOn: $cellularAllowed)
                    Text(cellularAllowed
                         ? "Refreshes over Wi-Fi and cellular. A refresh is a few hundred kilobytes."
                         : "Refreshes only on Wi-Fi. On cellular the app pauses and keeps showing the last reading rather than failing silently.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Display") {
                    Picker("Detail", selection: detailMode) {
                        ForEach(SWMode.allCases) { Text($0.label).tag($0) }
                    }
                    // Both of these only steer Extended's panels; hiding them leaves their
                    // stored values untouched, so Extended comes back exactly as it was.
                    if mode.selected == .extended {
                        Picker("Hp30 default range", selection: $hpoRangeHours) {
                            ForEach(Prefs.rangeOptions, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        Toggle("Show Kp forecast bars", isOn: $showForecast)
                    }
                    Toggle("Night mode (red-shift)", isOn: nightMode)
                }
                Section("Alerts") {
                    Toggle("Space event alerts", isOn: $alertsEnabled)
                        .onChange(of: alertsEnabled) { _, on in
                            if on { Task { alertsEnabled = await AlertNotifier.requestAuthorization() } }
                        }
                    if alertsEnabled {
                        Toggle("Geomagnetic storms", isOn: $alertStorms)
                        if alertStorms {
                            Picker("Notify from", selection: $alertStormThreshold) {
                                ForEach(1...4, id: \.self) { Text("G\($0)+").tag($0) }
                            }
                        }
                        Toggle("Solar flares (M-class and up)", isOn: $alertFlares)
                        Toggle("Aurora chance", isOn: $alertAurora)
                        if alertAurora {
                            Picker("From probability", selection: $alertAuroraThreshold) {
                                ForEach([30, 50, 70], id: \.self) { Text("\($0)%").tag($0) }
                            }
                        }
                    }
                    Text(alertsFootnote)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sources") {
                    LabeledContent("Geomagnetic & Hpo", value: "GFZ Potsdam")
                    LabeledContent("Solar, wind & scales", value: "NOAA SWPC")
                    Text("Every displayed value is classified by a local, offline-tested function checked against the published NOAA/GFZ definition. No number is shown that can't be validated.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("App", value: version)
                    Label("Ad-free · one-time purchase", systemImage: "checkmark.seal")
                        .foregroundStyle(sw.brand)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
