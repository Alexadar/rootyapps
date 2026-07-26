import SwiftUI
import SpaceWeatherFeed
import GeomagKit
import HpoKit
import WidgetKit

/// Three vertical pages: the hero readout, the Hp30/Kp geomagnetic detail, and
/// wind/aurora context. Cache-first paint from the watch's own app-group container
/// (the store preloads it), live refresh on activation, and the complications reload
/// off the same fetch. The theme lives in this device's own app-group container — app
/// groups don't span devices — and the phone's choice arrives over `WatchSync`.
struct WatchRootView: View {
    @StateObject private var store = SpaceWeatherStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedStore.Key.theme, store: AppGroup.defaults)
    private var themeRaw: String = SWThemeChoice.dark.rawValue
    @State private var page = 0

    private var palette: SWPalette { (SWThemeChoice(rawValue: themeRaw) ?? .dark).palette }

    var body: some View {
        TabView(selection: $page) {
            WatchReadoutPage(snapshot: store.snapshot, offline: store.isOffline).tag(0)
            WatchGeomagPage(snapshot: store.snapshot).tag(1)
            WatchWindPage(snapshot: store.snapshot, lastRefresh: store.lastRefresh).tag(2)
        }
        .tabViewStyle(.verticalPage)
        .environment(\.sw, palette)
        .task {
            WatchSync.shared.start()          // receives the phone's theme/mode choices
            store.afterRefresh = { _ in WidgetCenter.shared.reloadAllTimelines() }
            WatchDemo.applyInitialState(&page)
            await store.refresh()
            if WatchDemo.enabled { await WatchDemo.run(page: { page = $0 }) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

// MARK: - Page chrome

private extension View {
    /// watchOS floats the system time over the top of the screen, so page content has to
    /// start below it — otherwise a right-aligned header value renders underneath the clock.
    func watchPage(_ sw: SWPalette, alignment: Alignment) -> some View {
        self
            .padding(.top, 18)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(sw.background.ignoresSafeArea())
    }
}

// MARK: - Page 1: the readout (DesignSystem/WatchReadout.example.swift, live)

struct WatchReadoutPage: View {
    @Environment(\.sw) private var sw
    let snapshot: SpaceWeatherSnapshot
    let offline: Bool

    private var kpNow: Double { snapshot.kp?.now ?? 0 }
    private var gScale: Int { snapshot.scales?.g ?? Geomag.gScale(forKp: kpNow) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("//")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.brand)
                Text(offline ? "KP LAST" : "KP NOW")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(sw.textSecondary)
                Spacer()
                Text("G\(gScale)")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.onAccent)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(sw.severity(gScale), in: ChamferBox(cut: 4, radius: 2))
            }

            Text(snapshot.kp != nil ? String(format: "%.1f", kpNow) : "—")
                .font(.system(size: 54, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(sw.severity(gScale))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Planetary Kp, \(String(format: "%.1f", kpNow)), level G\(gScale)")

            HStack(spacing: 12) {
                watchStat(label: "AURORA",
                          value: snapshot.aurora.map { "\($0.maxProbability)%" } ?? "—")
                watchStat(label: "WIND",
                          value: snapshot.wind?.speed.map { Fmt.num($0, 0) } ?? "—", unit: "KM/S")
            }
        }
        .watchPage(sw, alignment: .leading)
    }
}

// MARK: - Page 2: geomagnetic — Hp30 mini-chart + scales line

struct WatchGeomagPage: View {
    @Environment(\.sw) private var sw
    let snapshot: SpaceWeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("//")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.brand)
                Text("HP30 24H")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(sw.textSecondary)
                Spacer()
                if let hp = snapshot.hpo?.latest {
                    Text(Fmt.num(hp, 2))
                        .font(.system(.caption2, design: .monospaced).weight(.heavy))
                        .foregroundStyle(sw.severity(snapshot.hpo?.latestGScale ?? 0))
                }
            }
            if let hpo = snapshot.hpo, !hpo.readings.isEmpty {
                Hp30Chart(readings: last24h(hpo.readings))
            } else {
                Text("No Hp30 data")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(sw.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 8) {
                scaleChip("G", snapshot.scales?.g)
                scaleChip("R", snapshot.scales?.r)
                scaleChip("S", snapshot.scales?.s)
            }
        }
        .watchPage(sw, alignment: .topLeading)
    }

    private func last24h(_ readings: [Hpo.Reading]) -> [Hpo.Reading] {
        guard let end = readings.last?.time else { return readings }
        return readings.filter { $0.time > end.addingTimeInterval(-24 * 3600) }
    }

    private func scaleChip(_ label: String, _ level: Int?) -> some View {
        let lvl = level ?? 0
        return Text("\(label)\(lvl)")
            .font(.system(.caption2, design: .monospaced).weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(lvl > 0 ? sw.onAccent : sw.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background {
                if lvl > 0 {
                    ChamferBox(cut: 4, radius: 2).fill(sw.severity(lvl))
                } else {
                    ChamferBox(cut: 4, radius: 2).strokeBorder(sw.hairline, lineWidth: 1)
                }
            }
    }
}

// MARK: - Page 3: solar wind + freshness

struct WatchWindPage: View {
    @Environment(\.sw) private var sw
    let snapshot: SpaceWeatherSnapshot
    let lastRefresh: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("//")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.brand)
                Text("SOLAR WIND")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(sw.textSecondary)
            }
            HStack(spacing: 12) {
                watchStat(label: "SPEED", value: snapshot.wind?.speed.map { Fmt.num($0, 0) } ?? "—", unit: "KM/S")
                watchStat(label: "BZ", value: snapshot.wind?.bz.map { Fmt.num($0, 1) } ?? "—", unit: "NT")
            }
            HStack(spacing: 12) {
                watchStat(label: "DENSITY", value: snapshot.wind?.density.map { Fmt.num($0, 1) } ?? "—", unit: "P/CM³")
                watchStat(label: "X-RAY", value: snapshot.flare?.currentClass ?? "—")
            }
            if let aurora = snapshot.aurora {
                // Proportional, not mono: the mono caption is too wide to wrap on a watch and
                // truncates to a single "Aurora may be visibl…". fixedSize lets it take the
                // height it needs instead of being compressed to one line.
                Text(aurora.viewLine)
                    .font(.caption2)
                    .foregroundStyle(sw.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Updated \(Fmt.age(lastRefresh))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Fmt.isStale(lastRefresh) ? sw.caution : sw.textTertiary)
        }
        .watchPage(sw, alignment: .topLeading)
    }
}

// MARK: - shared stat cell (WatchReadout example)

private func watchStat(label: String, value: String, unit: String? = nil) -> some View {
    WatchStatCell(label: label, value: value, unit: unit)
}

private struct WatchStatCell: View {
    @Environment(\.sw) private var sw
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .tracking(1.0)
                .foregroundStyle(sw.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(sw.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(sw.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
