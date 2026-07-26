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
        s.flare = FlarePanel(fluxSeries: [FluxSample(time: now, flux: 2.1e-6)], latestFlare: nil, observedAt: now)
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
        Task {
            let entry = await Self.fetchEntry()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
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

struct SpaceWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpaceWeather", provider: SpaceWeatherProvider()) { entry in
            SpaceWeatherWidgetView(entry: entry, mode: .shared)
                .environment(\.sw, SWThemeChoice.shared.palette)
        }
        .configurationDisplayName("Earth Around")
        .description("Planetary Kp, storm level, aurora chance and solar wind — live from NOAA.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #elseif os(macOS)
        [.systemSmall, .systemMedium]
        #else
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
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
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
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
        HStack(spacing: 14) {
            small
            Rectangle().fill(sw.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 8) {
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
                    scaleline
                    if let flare = entry.snapshot.flare {
                        stat(label: "X-RAY", value: flare.currentClass)
                    }
                    if let bz = entry.snapshot.wind?.bz {
                        stat(label: "BZ", value: Fmt.num(bz, 1), unit: "NT")
                    }
                }
                Spacer(minLength: 0)
                Text("Updated \(Fmt.age(entry.refreshedAt))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(stale ? sw.caution : sw.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readoutHeader: some View {
        HStack(spacing: 5) {
            Text("//")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.brand)
            Text(simple ? "STORM" : "KP NOW")
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
        Text(hasData ? String(format: "%.1f", kpNow) : "—")
            .font(.system(size: 44, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(sw.severity(gScale))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxHeight: .infinity)
            .accessibilityLabel("Planetary Kp \(String(format: "%.1f", kpNow)), level G\(gScale)")
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

    // MARK: accessory families (lock screen / watch)

    private var inline: some View {
        if simple {
            Text(hasData ? "\(activity)\(auroraPct.map { " · aurora \($0)%" } ?? "")" : "Earth Around")
        } else {
            Text(hasData ? "KP \(String(format: "%.1f", kpNow)) · G\(gScale)" : "Earth Around")
        }
    }

    private var circular: some View {
        Gauge(value: min(kpNow, 9), in: 0...9) {
            Text("KP")
        } currentValueLabel: {
            Text(hasData ? String(format: "%.1f", kpNow) : "—")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }

    @ViewBuilder private var rectangular: some View {
        if simple {
            VStack(alignment: .leading, spacing: 1) {
                Text(hasData ? activity : "—")
                    .font(.headline)
                Text("Aurora \(auroraPct.map { "\($0)%" } ?? "—")")
                    .font(.system(.caption2, design: .monospaced))
            }
        } else {
            extendedRectangular
        }
    }

    private var extendedRectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("KP \(hasData ? String(format: "%.1f", kpNow) : "—")")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .monospacedDigit()
                Text("G\(gScale)")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
            }
            Text("AUR \(auroraPct.map { "\($0)%" } ?? "—")  WND \(windKms.map { Fmt.num($0, 0) } ?? "—")")
                .font(.system(.caption2, design: .monospaced))
            Text(Geomag.activity(forKp: kpNow))
                .font(.system(.caption2, design: .monospaced))
                .opacity(0.7)
        }
    }
}
