import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ROOT — the appearance mode's single owner.
//
// ⚠ INVARIANT. `.preferredColorScheme` is attached HERE and nowhere else. On the
// phone, `ToolScreen` also set it while the root passed `nil` for `.auto`, and
// `.auto` silently stopped following the system. No child in this target may set
// it, and no child may read the scheme back out of the environment to decide a
// palette — they read `\.watchTheme`.
//
// ⚠ NAVIGATION DECISION — horizontal paging, not vertical.
// `.tabViewStyle(.verticalPage)` gives the Digital Crown to the tab bar. The
// crown is the best thing about F1 (scrubbing the day) and F5 (spinning a
// heading), so the tab view must not own it. Horizontal paging swipes between
// instruments and leaves the crown to the screen. That is the whole reason for
// this choice.
// ─────────────────────────────────────────────────────────────────────────────

struct WatchRootView: View {
    @AppStorage("watch.mode") private var modeRaw: String = WatchMode.auto.rawValue
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var page: Page = WatchRootView.initialPage

    enum Page: Hashable { case tides, currents, mark, declination, settings }

    /// Lets a capture run open straight onto one page:
    /// `xcrun simctl launch <sim> <bundle> -page declination`.
    /// Mirrors `ContentView.initialTool` on the phone — the pages are a horizontal
    /// `TabView`, so there is no other way to drive them from a script. Capture/automation
    /// affordance only; no product behaviour depends on it.
    static var initialPage: Page {
        // DEBUG-only: see `LaunchOverride`.
        guard let raw = LaunchOverride.argument("page") else { return .tides }
        switch raw {
        case "currents":    return .currents
        case "mark":        return .mark
        case "declination": return .declination
        case "settings":    return .settings
        default:            return .tides
        }
    }

    private var mode: WatchMode { WatchMode(rawValue: modeRaw) ?? .auto }
    private var theme: WatchTheme {
        WatchTheme(mode: mode, luminanceReduced: luminanceReduced)
    }

    var body: some View {
        TabView(selection: $page) {
            WatchTidesNowView()
                .tag(Page.tides)
                .accessibilityIdentifier("tool.tides")
            WatchCurrentsView()
                .tag(Page.currents)
                .accessibilityIdentifier("tool.currents")
            WatchSightMarkView()
                .tag(Page.mark)
                .accessibilityIdentifier("tool.sightMark")
            WatchDeclinationView()
                .tag(Page.declination)
                .accessibilityIdentifier("tool.declination")
            WatchSettingsView(modeRaw: $modeRaw)
                .tag(Page.settings)
                .accessibilityIdentifier("tool.settings")
        }
        .tabViewStyle(.page)
        .environment(\.watchTheme, theme)
        .background(theme.palette.canvas)
        // The one place this is allowed to live.
        .preferredColorScheme(.dark)
        .tint(theme.palette.water)
    }
}

/// Appearance, units, and the provenance statement App Review 4.3(b) wants to be
/// able to see. Deliberately the LAST page: it is read once and then never again.
struct WatchSettingsView: View {
    @Binding var modeRaw: String
    @Environment(\.watchTheme) private var theme
    @ObservedObject private var store = WatchStationStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("APPEARANCE")
                    .font(WatchType.section).tracking(0.8)
                    .foregroundStyle(theme.palette.inkDim)

                // A list of real buttons, not a Picker: at a helm you want one
                // tap on the mode you can see, not a wheel to spin.
                VStack(spacing: 4) {
                    ForEach(WatchMode.allCases) { m in
                        Button { modeRaw = m.rawValue } label: {
                            HStack(spacing: 8) {
                                Image(systemName: m.symbol)
                                    .font(.system(size: 12))
                                    .frame(width: 18)
                                Text(m.title)
                                    .font(WatchType.label)
                                Spacer(minLength: 2)
                                if modeRaw == m.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .foregroundStyle(modeRaw == m.rawValue
                                             ? theme.palette.water : theme.ambientInk)
                            .frame(minHeight: WatchMetrics.target)
                            .padding(.horizontal, 8)
                            .background(modeRaw == m.rawValue
                                        ? theme.palette.water.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("input.mode.\(m.rawValue)")
                    }
                }

                Text("“Auto” follows the watch, which has no light appearance — it resolves to "
                     + "Dusk. Night · red keeps dark adaptation: nothing on screen but red, and "
                     + "no meaning carried by colour.")
                    .font(WatchType.caption)
                    .foregroundStyle(theme.palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                Text("UNITS")
                    .font(WatchType.section).tracking(0.8)
                    .foregroundStyle(theme.palette.inkDim)
                HStack(spacing: 4) {
                    unitButton("Feet", isMetric: false)
                    unitButton("Metres", isMetric: true)
                }

                WatchProvenance(kit: "TidesKit · GeomagKit · GeodesyKit · CelestialNavKit",
                                authority: "NOAA CO-OPS, Schureman SP-98, WMM2025's official "
                                         + "test values, Vincenty and Karney's GeodTest, and "
                                         + "Bowditch's worked sight")
                Text("Bought once. No subscription, no accounts, no adverts, and no network "
                     + "requests — every number is computed on this watch.")
                    .font(WatchType.caption)
                    .foregroundStyle(theme.palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("result.provenanceStatement")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(theme.palette.canvas)
    }

    private func unitButton(_ title: String, isMetric: Bool) -> some View {
        let selected = (store.unit == .meters) == isMetric
        return Button {
            store.unit = isMetric ? .meters : .feet
        } label: {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(selected ? theme.palette.canvas : theme.ambientInk)
                .background(selected ? theme.palette.water : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.ambientHairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("input.unit.\(isMetric ? "meters" : "feet")")
    }
}

@main
struct MarineNavWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

#Preview("Root") {
    WatchRootView()
}
