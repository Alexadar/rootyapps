import SwiftUI
import SpaceWeatherFeed
import WidgetKit

/// Aurora HUD root shell for iOS + macOS. Two segments — the spaceweather.com-style
/// Dashboard and the kp.gfz.de-style Geomagnetic view — over a live store that
/// refreshes on pull / on a timer and is honest about staleness and offline state.
/// The palette comes from `ContentView`'s `.swTheme(...)`; this view just reads `\.sw`.
struct SpaceWeatherRootView: View {
    @StateObject private var store = SpaceWeatherStore()
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var mode: ModeStore
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var demo: DemoDriver
    @Environment(\.sw) private var sw
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.dashboard
    @State private var showSettings = false

    #if os(macOS)
    private let wideLayout = true
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wideLayout: Bool { sizeClass == .regular }
    #endif

    // Power-user prefs live behind the gear; the main UI reads their values only.
    @AppStorage(Prefs.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(Prefs.showForecast) private var showForecast = true
    @AppStorage(Prefs.hpoRangeHours) private var hpoRangeHours = 168.0

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", geomagnetic = "Geomagnetic"
        var id: String { rawValue }

        /// Display text, kept separate from `rawValue` — that is the persisted identity and the
        /// scroll-target id, so translating it would change what is stored on disk.
        var title: String.LocalizationValue {
            switch self {
            case .dashboard:   return "Dashboard"
            case .geomagnetic: return "Geomagnetic"
            }
        }
    }

    var body: some View {
        ZStack {
            SpaceBackground(accent: sw.brand)
            captureKeepalive
            // Content scrolls full-bleed and passes UNDER the floating Liquid Glass bar.
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, SWM.screenMargin)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .panelWidth(wide: wideLayout)
                        .frame(maxWidth: .infinity)
                }
                .refreshable { await store.refresh() }
                .safeAreaInset(edge: .top, spacing: 0) { glassTopBar }
                // Marketing self-drive scrolls the list to a panel; no effect in normal use.
                .onChange(of: demo.scrollTarget) { _, panel in
                    guard let panel else { return }
                    withAnimation(.easeInOut(duration: 0.9)) {
                        proxy.scrollTo(panel, anchor: demo.scrollAnchor)
                    }
                }
            }
        }
        .tint(sw.brand)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(mode)
                .environmentObject(language)
                .swTheme(theme.selected)
        }
        .task {
            // Full view always. The Simple/Extended switch is gone from the UI; a "lite" build
            // will flip this same store rather than reintroduce a control here.
            mode.selected = .extended
            store.afterRefresh = { snapshot in
                WidgetCenter.shared.reloadAllTimelines()
                AlertNotifier.handle(snapshot)
            }
            await store.refresh()
            applyRefreshInterval()
        }
        .onChange(of: refreshMinutes) { _, _ in applyRefreshInterval() }
        // Any screen change pulls everything, throttled so flicking tabs doesn't hammer NOAA.
        .onChange(of: tab) { _, _ in Task { await store.refreshIfStale() } }
        .onChange(of: scenePhase) { _, phase in
            // The watch already refreshed on activation; the phone never did, so returning from
            // background sat on a stale screen until the 5-minute timer ticked.
            if phase == .active { Task { await store.refreshIfStale() } }
        }
        // The widget renders from these two prefs, so it has to be told they changed —
        // its own timeline wouldn't come back around for another half hour. The watch has
        // its own container entirely, so it needs them pushed over WatchConnectivity.
        .onChange(of: mode.selected) { _, _ in prefsChanged() }
        .onChange(of: theme.selected) { _, _ in prefsChanged() }
        .onChange(of: language.selected) { _, _ in prefsChanged() }
        .onChange(of: demo.tabIndex) { _, i in
            withAnimation(.easeInOut) { tab = Tab.allCases[min(max(i, 0), Tab.allCases.count - 1)] }
        }
        .onDisappear { store.stopAutoRefresh() }
    }

    /// `simctl io recordVideo` emits a frame only when the display *changes*, and timestamps
    /// by frame — so a still screen records as ~2fps and a 5s hold collapses to ~1s of video.
    /// That desynchronises the tour's wall-clock scene markers from the footage. Redrawing an
    /// imperceptible pixel every frame keeps the capture at real time. Demo mode only: it costs
    /// a redraw per frame, which has no business running on a user's battery.
    @ViewBuilder private var captureKeepalive: some View {
        if DemoDriver.enabled {
            TimelineView(.animation) { ctx in
                let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                Rectangle()
                    .fill(sw.brand.opacity(0.002 + 0.002 * phase))
                    .frame(width: 2, height: 2)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func prefsChanged() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchSync.shared.push(theme: theme.selected.rawValue, mode: mode.selected.rawValue,
                              cellular: SharedStore().cellularAllowed,
                              language: language.selected.rawValue)
        #endif
    }

    private func applyRefreshInterval() {
        if refreshMinutes <= 0 { store.stopAutoRefresh() }
        else { store.startAutoRefresh(interval: Double(refreshMinutes) * 60) }
    }

    private var isSnapshotEmpty: Bool { store.snapshot == SpaceWeatherSnapshot() }

    // MARK: - Scrolling content

    @ViewBuilder private var content: some View {
        if store.isOffline && isSnapshotEmpty {
            offlineEmpty
        } else if isSnapshotEmpty && store.isLoading {
            loading
        } else if mode.selected == .simple {
            SimpleView(snapshot: store.snapshot, status: store.status)
        } else {
            switch tab {
            case .dashboard:
                DashboardView(snapshot: store.snapshot, showForecast: showForecast, status: store.status)
            case .geomagnetic:
                GeomagView(snapshot: store.snapshot, showForecast: showForecast,
                           defaultRangeHours: hpoRangeHours, status: store.status)
            }
        }
    }

    // MARK: - Liquid Glass top bar (2026)
    //
    // Floating translucent chrome: the HUD content stays flat/matte, while the top bar
    // is Liquid Glass so scrolled content refracts through it. The glass background
    // extends behind the status bar; the bar's controls stay within the safe area.

    /// Continuous curvature matches the display's own corner shape rather than a circular arc.
    private static let barShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    private var glassTopBar: some View {
        // Simple sheds the chrome as well as the panels: the G/R scoreline and the
        // Dashboard/Geomagnetic ladder are exactly the jargon it exists to remove.
        VStack(spacing: 10) {
            header
            if mode.selected == .extended {
                if !isSnapshotEmpty { matchupStrip }
                SWSegmented(titles: Tab.allCases.map { SWText.str($0.title) }, selection: .index(of: $tab))
                    .padding(.horizontal, SWM.screenMargin)
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            // Liquid Glass is GPU-heavy and starves the simulator's video encoder during
            // the animated marketing capture — fall back to an opaque bar in demo mode only.
            Group {
                if DemoDriver.enabled {
                    sw.surface.opacity(0.96)
                } else {
                    Color.clear.glassEffect(.regular, in: Self.barShape)
                }
            }
            .clipShape(Self.barShape)
        }
        .overlay(Self.barShape.strokeBorder(sw.hairline, lineWidth: 1))
        // A FLOATING bar, inset from the screen edges. It used to be a full-bleed rectangle that
        // ignored the top safe area, so its square corners ran into the iPhone's rounded display
        // corners and got sliced — and its content sat in the status-bar strip, where the system's
        // tap-to-scroll-to-top region swallows touches. Insetting fixes the look and the taps at
        // once, and it cannot collide with the corner radius of any device.
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("//")
                        .font(.system(.headline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(sw.brand)
                    Text("EARTH AROUND")
                        .font(.system(size: 22, weight: .heavy)).tracking(-0.4)
                        .foregroundStyle(sw.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                    // LIVE only when every source actually came back. It used to show whenever a
                    // single fetch of seven succeeded, so six dead feeds still read as live.
                    if let pill = livePill {
                        Text(pill.text)
                            .font(.system(size: 9, design: .monospaced).weight(.bold)).tracking(1.2)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .foregroundStyle(sw.onAccent)
                            .background(pill.color, in: ChamferBox(cut: 5, radius: 3))
                    }
                }
                statusLine
            }
            Spacer()
            HStack(spacing: 6) {
                Button { theme.toggle() } label: {
                    Image(systemName: theme.selected == .night ? "moon.stars.fill" : "moon.stars")
                        .foregroundStyle(theme.selected == .night ? sw.brand : sw.textSecondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Night mode")
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(sw.brand).opacity(store.isLoading ? 0.4 : 1)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(store.isLoading)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").foregroundStyle(sw.textSecondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var livePill: (text: String, color: Color)? {
        if store.isOffline || store.isPausedOnCellular { return nil }
        if store.status.anyFailed { return ("PARTIAL", sw.caution) }
        return ("LIVE", sw.brand)
    }

    private var failedCount: Int {
        FeedSource.allCases.filter { store.status.didFail($0) }.count
    }

    private var statusLine: some View {
        Group {
            if store.isOffline {
                Label(SWText.str("Offline · showing last known"), systemImage: "wifi.slash")
                    .textCase(.uppercase)
                    .foregroundStyle(sw.caution)
            } else if store.isPausedOnCellular {
                Label(SWText.str("Paused on cellular · will refresh on Wi-Fi"),
                      systemImage: "antenna.radiowaves.left.and.right.slash")
                    .textCase(.uppercase)
                    .foregroundStyle(sw.caution)
            } else if failedCount > 0 {
                // Name the number rather than implying everything refreshed.
                Label(SWText.str("\(failedCount) of \(FeedSource.allCases.count) sources didn't refresh"),
                      systemImage: "exclamationmark.triangle.fill")
                    .textCase(.uppercase)
                    .foregroundStyle(sw.caution)
            } else {
                Text(SWText.str("Updated \(Fmt.age(store.lastRefresh)) · NOAA + GFZ, validated"))
                    .textCase(.uppercase)
                    .foregroundStyle(sw.textTertiary)
            }
        }
        .font(.system(size: 9, design: .monospaced)).tracking(0.8)
        .lineLimit(1).minimumScaleFactor(0.75)
    }

    // MARK: - Matchup strip (SUN vs EARTH scoreline, from live snapshot)

    private var matchupStrip: some View {
        let scales = store.snapshot.scales
        let wind = store.snapshot.wind
        return HStack(spacing: 10) {
            sideChip(side: .solar, label: "Sun",
                     score: scales.map { $0.r > 0 ? "R\($0.r)" : "—" } ?? "—")
            Text("VS")
                .font(.system(size: 10, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.textTertiary)
            sideChip(side: .terra, label: "Earth",
                     score: scales.map { $0.g > 0 ? "G\($0.g)" : "—" } ?? "—")
            Spacer()
            if let s = wind?.speed {
                Text(SWText.str("WIND \(Int(s)) KM/S"))
                    .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(0.8)
                    .foregroundStyle(sw.side(.link))
            }
        }
        .padding(.horizontal, SWM.screenMargin)
    }

    private func sideChip(side: SWSide, label: String.LocalizationValue, score: String) -> some View {
        HStack(spacing: 6) {
            Text("//")
                .font(.system(size: 10, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.side(side))
            Text(SWText.str(label))
                .textCase(.uppercase)
                .font(.system(size: 10, design: .monospaced).weight(.semibold)).tracking(1.0)
                .foregroundStyle(sw.textSecondary)
            Text(score)
                .font(.system(size: 11, design: .monospaced).weight(.heavy)).monospacedDigit()
                .foregroundStyle(sw.textPrimary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(sw.surface, in: ChamferBox(cut: 6, radius: SWM.rChip))
        .overlay(ChamferBox(cut: 6, radius: SWM.rChip).strokeBorder(sw.hairline, lineWidth: 1))
    }

    /// Never translated, so it is interpolated rather than sitting inside the sentence.
    private static let brand = "EARTH AROUND"

    // MARK: - States

    private var loading: some View {
        ProgressView(SWText.str("Loading \(Self.brand)…"))
            .textCase(.uppercase)
            .tint(sw.brand)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(sw.textSecondary)
            .padding(.top, 80)
    }

    private var offlineEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash").font(.system(size: 44)).foregroundStyle(sw.caution)
            Text(SWText.str("No connection"))
                .textCase(.uppercase)
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(sw.textPrimary)
            Text(SWText.str("This app needs the network for live NOAA and GFZ data. Reconnect and pull to refresh — no numbers are shown until they're real."))
                .font(.footnote).foregroundStyle(sw.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32).padding(.top, 60)
    }
}
