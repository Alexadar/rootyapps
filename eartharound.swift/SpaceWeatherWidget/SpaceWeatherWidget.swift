import WidgetKit
import SwiftUI
import SpaceWeatherFeed
import GeomagKit

// The glanceable readout: hero Kp + G chip, aurora and wind stats — the same
// composition as the watch readout (see DesignSystem/WatchReadout.example.swift).
// The provider fetches live NOAA data itself; when the network is down it falls
// back to the app-group cache and shows the age honestly, never a stale number
// dressed up as fresh.

struct SpaceWeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: SpaceWeatherSnapshot
    let refreshedAt: Date?

    static let placeholder: SpaceWeatherEntry = {
        var s = SpaceWeatherSnapshot()
        let now = Date()
        s.kp = KpPanel(series: [KpSample(time: now, kp: 5.3, predicted: false)], observedAt: now)
        s.scales = ScalesPanel(g: 1, r: 0, s: 0, observedAt: now)
        s.wind = SolarWindPanel(speed: 620, density: 4.2, bt: 12, bz: -8.5, observedAt: now)
        s.aurora = AuroraPanel(maxProbability: 45, kp: 5.3, observedAt: now)
        s.flare = FlarePanel(fluxSeries: [FluxSample(time: now, flux: 2.1e-6)],
                             latestFlare: FlareEvent(maxClass: "M1.0", maxTime: now, beginTime: nil),
                             recentFlares: [FlareEvent(maxClass: "M1.0", maxTime: now, beginTime: nil),
                                            FlareEvent(maxClass: "M3.2", maxTime: now, beginTime: nil)],
                             observedAt: now)
        return SpaceWeatherEntry(date: now, snapshot: s, refreshedAt: now)
    }()
}

struct SpaceWeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpaceWeatherEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SpaceWeatherEntry) -> Void) {
        if let cached = SharedStore().load() {
            completion(SpaceWeatherEntry(date: Date(), snapshot: cached.snapshot, refreshedAt: cached.at))
        } else {
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpaceWeatherEntry>) -> Void) {
        // The cache is the floor, not the fallback of last resort. `fetchEntry` opens five NOAA
        // connections, and on a wrist that is a real risk of never returning inside the extension's
        // budget — chronod then kills the process and the complication is stuck on the placeholder,
        // which renders as a grey blank forever. Whatever happens, we complete with something.
        let cached = SharedStore().load()
        let floor = cached.map { SpaceWeatherEntry(date: Date(), snapshot: $0.snapshot, refreshedAt: $0.at) }
            ?? .placeholder
        Task {
            let entry = await Self.fetchEntry(within: 12) ?? floor
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    /// `fetchEntry()` bounded by a deadline. Returns nil if the network outlasts it, so the caller
    /// can fall back to cache instead of holding the extension open until the system kills it.
    static func fetchEntry(within seconds: Double) async -> SpaceWeatherEntry? {
        await withTaskGroup(of: SpaceWeatherEntry?.self) { group in
            group.addTask { await fetchEntry() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Start from the cache, apply what the network delivers, and merge back.
    ///
    /// This deliberately fetches only what the widget renders — five of the app's seven sources.
    /// It must therefore MERGE rather than save: writing the whole snapshot rewrote Hp30 and Solar
    /// at their stale cached values under a fresh timestamp, so the app opened on "updated just
    /// now" with two panels hours behind.
    static func fetchEntry() async -> SpaceWeatherEntry {
        let shared = SharedStore()
        let cached = shared.load()
        var snapshot = cached?.snapshot ?? SpaceWeatherSnapshot()

        let cellularAllowed = shared.cellularAllowed
        if let reason = NetworkMonitor.shared.blockedReason(cellularAllowed: cellularAllowed) {
            var status = shared.status
            let now = Date()
            for source in [FeedSource.kp, .scales, .wind, .aurora, .flares] { status.record(source, reason, at: now) }
            shared.status = status
            return SpaceWeatherEntry(date: now, snapshot: snapshot, refreshedAt: cached?.at)
        }

        async let kp = try? NOAAService.kp()
        async let scales = try? NOAAService.scales()
        async let wind = try? NOAAService.solarWind()
        async let aurora = try? NOAAService.auroraProbability()
        async let flares = try? NOAAService.flares()

        let kpP = await kp
        let scalesP = await scales
        let windP = await wind
        let auroraP = await aurora
        let flareP = await flares

        let now = Date()
        var fresh = SpaceWeatherSnapshot()
        var status = FeedStatus()
        func accept<T>(_ source: FeedSource, _ value: T?, apply: (T) -> Void) {
            guard let value else { status.record(source, .failed, at: now); return }
            status.record(source, .ok, at: now)
            apply(value)
        }
        accept(.kp, kpP) { fresh.kp = $0; snapshot.kp = $0 }
        accept(.scales, scalesP) { fresh.scales = $0; snapshot.scales = $0 }
        accept(.wind, windP) { fresh.wind = $0; snapshot.wind = $0 }
        accept(.flares, flareP) { fresh.flare = $0; snapshot.flare = $0 }
        accept(.aurora, auroraP) { a in
            let panel = AuroraPanel(maxProbability: a.max, kp: snapshot.kp?.now ?? 0, observedAt: a.at)
            fresh.aurora = panel; snapshot.aurora = panel
        }

        let anySucceeded = !status.sources.values.allSatisfy { $0.outcome.isFailure }
        let refreshedAt = anySucceeded ? now : cached?.at
        if anySucceeded { shared.merge(fresh, status: status, at: now) }
        return SpaceWeatherEntry(date: now, snapshot: snapshot, refreshedAt: refreshedAt)
    }
}

// Everything below is the system-sized widget, which does not exist on the watch — the synchronized
// file group compiles this file into the watch complication target too, and `.systemSmall` is simply
// unavailable there. `SpaceWeatherEntry` and `SpaceWeatherProvider` above stay: the complications
// share that provider.
#if !os(watchOS)

struct SpaceWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpaceWeather", provider: SpaceWeatherProvider()) { entry in
            SpaceWeatherWidgetView(entry: entry, mode: .shared)
                .environment(\.sw, SWThemeChoice.shared.palette)
                .environment(\.locale, SWLanguage.sharedLocale)
        }
        .configurationDisplayName("Earth Around")
        .description("Planetary Kp, storm level, aurora chance and solar wind — live from NOAA.")
        .supportedFamilies(Self.families)
    }

    /// System sizes only. The accessory families belong to `KpComplication`/`FlaresComplication`,
    /// which draw the bar gauges; this widget advertising them too put a third "Earth Around" entry
    /// in every complication picker showing an older, gauge-less readout.
    static var families: [WidgetFamily] { [.systemSmall, .systemMedium] }
}

// MARK: - Views

struct SpaceWeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.sw) private var sw
    let entry: SpaceWeatherEntry
    var mode: SWMode = .extended

    private var simple: Bool { mode == .simple }
    private var activity: String { Geomag.activity(forKp: kpNow) }
    private var kpNow: Double { entry.snapshot.kp?.now ?? 0 }
    private var gScale: Int { entry.snapshot.scales?.g ?? Geomag.gScale(forKp: kpNow) }
    private var auroraPct: Int? { entry.snapshot.aurora?.maxProbability }
    private var windKms: Double? { entry.snapshot.wind?.speed }
    private var hasData: Bool { entry.snapshot.kp != nil }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(for: .widget) { sw.background }
    }

    // MARK: system families — the WatchReadout composition

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            readoutHeader
            if simple {
                // A phrase, not two glyphs — so it sets smaller than the Kp numeral.
                Text(hasData ? activity : "—")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sw.severity(gScale))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxHeight: .infinity)
                    .accessibilityLabel("Conditions \(activity)")
                stat(label: "AURORA", value: auroraPct.map { "\($0)%" } ?? "—")
            } else {
                heroKp
                HStack(spacing: 12) {
                    stat(label: "AURORA", value: auroraPct.map { "\($0)%" } ?? "—")
                    stat(label: "WIND", value: windKms.map { Fmt.num($0, 0) } ?? "—", unit: "KM/S")
                }
            }
        }
    }

    private var medium: some View {
        // Each column carries its OWN data age, because the two sides are not refreshed together:
        // NOAA republishes X-ray flux every minute while Kp moves on a 3-hourly cadence, so one
        // shared timestamp would have overstated the freshness of whichever side was older.
        // Structurally identical columns also keep the two 44pt heroes on the same baseline.
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if simple { small } else { kpColumn }
                columnFooter(entry.snapshot.kp?.observedAt)
            }
            Rectangle().fill(sw.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if simple {
                        // The view line is derived from Kp; with no Kp it would state a confident,
                        // wrong latitude, so it stays hidden rather than guessing.
                        if let aurora = entry.snapshot.aurora, entry.snapshot.kp != nil {
                            Text(aurora.viewLine)
                                .font(.footnote)
                                .foregroundStyle(sw.textSecondary)
                                .lineLimit(4)
                        }
                    } else {
                        flareColumn
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                columnFooter(entry.snapshot.flare?.observedAt)
            }
        }
    }

    /// When the SOURCE observed this column's data — not when we fetched it. "Updated" is reserved
    /// for our own refresh; this is the observation time, same wording as the app's panel badges.
    private func columnFooter(_ observedAt: Date?) -> some View {
        Text(SWText.str("Observed \(Fmt.age(observedAt))"))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Fmt.isStale(observedAt) ? sw.caution : sw.textTertiary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kp column for the medium family — the mirror of `flareColumn`: same header shape, same 44pt
    /// hero, and a 24 h peak in the same slot so the two sides can be read against each other.
    /// `small` keeps AURORA/WIND for the systemSmall family, where there is no room for both.
    private var kpColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            readoutHeader
            heroKp
            HStack(spacing: 12) {
                // Highest Kp that actually occurred in the window — forecast rows excluded.
                stat(label: SWText.str("24H PEAK"),
                     value: entry.snapshot.kp?.peak24h().map { Fmt.num($0, 1) } ?? "—")
                stat(label: "WIND", value: windKms.map { Fmt.num($0, 0) } ?? "—", unit: "KM/S")
            }
        }
    }

    private var flareColumn: some View {
        let flare = entry.snapshot.flare
        let latest = flare?.latestFlare
        // Hero is the LATEST flare event; if the Sun has thrown nothing yet we fall back to the
        // current X-ray class so the column never reads as empty.
        let heroClass = latest?.maxClass ?? flare?.currentClass
        let r = latest?.rScale ?? flare?.rScale ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("//")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.side(.solar))
                Text(SWText.str("Latest flare"))
                    .textCase(.uppercase)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(sw.textSecondary)
                Spacer()
                Text(r > 0 ? "R\(r)" : "OK")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.onAccent)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(sw.severity(r), in: ChamferBox(cut: 4, radius: 2))
            }
            Text(heroClass ?? "—")
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(sw.severity(flareClass: heroClass ?? ""))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxHeight: .infinity)
                .accessibilityLabel(Text(SWText.str("Latest flare")) + Text(" \(heroClass ?? "—")"))
            HStack(spacing: 12) {
                // What kind of day it has been, not just this minute.
                if let flare, let peak = flare.peak24h {
                    stat(label: SWText.str("24H PEAK"), value: peak.maxClass,
                         unit: flare.count24h > 1 ? "×\(flare.count24h)" : nil)
                }
                if let flare {
                    stat(label: "X-RAY", value: flare.currentClass)
                }
            }
        }
    }

    private var readoutHeader: some View {
        HStack(spacing: 5) {
            Text("//")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.brand)
            Text(simple ? "Storm" : "Kp now")
                .textCase(.uppercase)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(sw.textSecondary)
            Spacer()
            Text(simple && gScale == 0 ? "OK" : "G\(gScale)")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.onAccent)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(sw.severity(gScale), in: ChamferBox(cut: 4, radius: 2))
        }
    }

    private var heroKp: some View {
        Text(hasData ? Fmt.num(kpNow, 1) : "—")
            .font(.system(size: 44, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(sw.severity(gScale))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Planetary Kp, \(Fmt.num(kpNow, 1)), level G\(gScale)")
    }

    private var scaleline: some View {
        HStack(spacing: 8) {
            miniScale("G", entry.snapshot.scales?.g)
            miniScale("R", entry.snapshot.scales?.r)
            miniScale("S", entry.snapshot.scales?.s)
        }
    }

    private func miniScale(_ label: String, _ level: Int?) -> some View {
        let lvl = level ?? 0
        return Text(lvl > 0 ? "\(label)\(lvl)" : "\(label)0")
            .font(.system(.caption, design: .monospaced).weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(lvl > 0 ? sw.onAccent : sw.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background {
                if lvl > 0 {
                    ChamferBox(cut: 5, radius: 3).fill(sw.severity(lvl))
                } else {
                    ChamferBox(cut: 5, radius: 3).strokeBorder(sw.hairline, lineWidth: 1)
                }
            }
    }

    private func stat(label: String, value: String, unit: String? = nil) -> some View {
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
    }

    private var stale: Bool { Fmt.isStale(entry.refreshedAt) }
}

#endif
