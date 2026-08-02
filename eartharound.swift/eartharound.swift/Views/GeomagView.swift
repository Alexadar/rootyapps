import SwiftUI
import SpaceWeatherFeed
import GeomagKit
import HpoKit

/// kp.gfz.de-parity geomagnetic view. The Hp30 30-minute chart is the hero — the
/// high-cadence storm resolution the competition lacks — with a range selector to
/// scroll back through the week, over the classic Kp bars and the Kit-computed Ap.
struct GeomagView: View {
    let snapshot: SpaceWeatherSnapshot
    var showForecast = true
    var status: FeedStatus? = nil
    @Environment(\.sw) private var sw
    @EnvironmentObject private var demo: DemoDriver
    @State private var range: HpoRange

    init(snapshot: SpaceWeatherSnapshot, showForecast: Bool = true, defaultRangeHours: Double = 168,
         status: FeedStatus? = nil) {
        self.snapshot = snapshot
        self.showForecast = showForecast
        self.status = status
        _range = State(initialValue: HpoRange(rawValue: defaultRangeHours) ?? .week)
    }

    enum HpoRange: Double, CaseIterable, Identifiable {
        case day1 = 24, day3 = 72, week = 168
        var id: Double { rawValue }
        var label: String { self == .day1 ? "1D" : self == .day3 ? "3D" : "7D" }
    }

    var body: some View {
        LazyVStack(spacing: 14) {
            hpoPanel
            kpPanel
        }
        .onChange(of: demo.rangeHours) { _, h in
            if let h, let r = HpoRange(rawValue: h) { withAnimation(.easeInOut) { range = r } }
        }
    }

    @ViewBuilder private var hpoPanel: some View {
        if let h = snapshot.hpo {
            let windowed = windowedReadings(h)
            Panel(id: "hpo", title: "Hp30 · High-Cadence Geomagnetic Index",
                  source: "GFZ Potsdam · Hpo", observedAt: h.observedAt, feed: .hpo, status: status, highlighted: true) {
                HStack(spacing: 12) {
                    MetricTile(id: "hpo.now", value: Fmt.num(h.latest, 2), caption: "Hp30 now", color: sw.brand)
                    MetricTile(id: "hpo.gScale", value: (h.latestGScale ?? 0) > 0 ? "G\(h.latestGScale!)" : "—",
                               caption: "NOAA level")
                    if h.exceedsCeiling {
                        MetricTile(id: "hpo.exceedsCeiling", value: "9+", caption: "exceeds Kp ceiling", color: sw.warning)
                    }
                }
                SWSegmented(titles: HpoRange.allCases.map(\.label), selection: .index(of: $range))
                Hp30Chart(readings: windowed)
                MeaningLine("Hp30 resolves geomagnetic activity every 30 minutes — the sub-hour detail the 3-hourly Kp misses. Open-ended above Kp 9.")
            }
            .tint(sw.side(.terra))
        }
    }

    /// Client-side scroll-back: slice the fetched week to the selected window, anchored
    /// to the newest reading (data may lag real time — anchor to it, not to `now`).
    private func windowedReadings(_ h: HpoPanel) -> [Hpo.Reading] {
        guard let end = h.readings.last?.time else { return h.readings }
        return Hpo.window(h.readings, hours: range.rawValue, endingAt: end)
    }

    /// Daily Ap for the latest UT day (GeomagKit). Complete when eight 3-hourly values
    /// exist; otherwise a labeled running average "so far". nil with no observations.
    private func dailyAp(_ k: KpPanel) -> (value: Int, complete: Bool)? {
        let observed = k.series.filter { !$0.predicted }
        let byDay = Dictionary(grouping: observed) { Hpo.utDayStart(for: $0.time) }
        guard let day = byDay.keys.max(), let vals = byDay[day], !vals.isEmpty else { return nil }
        let kp = vals.sorted { $0.time < $1.time }.map(\.kp)
        if let ap = Geomag.dailyAp(fromThreeHourlyKp: kp) { return (ap, true) }
        let mean = Double(kp.map { Geomag.ap(forKp: $0) }.reduce(0, +)) / Double(kp.count)
        return (Int(mean.rounded()), false)
    }

    @ViewBuilder private var kpPanel: some View {
        if let k = snapshot.kp {
            let ap = dailyAp(k)
            let level = snapshot.geomagNow ?? k.now
            Panel(id: "kp", title: "Planetary Kp · 3-Day", source: "NOAA SWPC", observedAt: k.observedAt,
                  feed: .kp, status: status) {
                KpBarChart(series: k.series, showForecast: showForecast)
                HStack(spacing: 12) {
                    // Same preciser oracle as every other readout — see `geomagNow`.
                    MetricTile(id: "geomag.kp.now", value: Fmt.num(level, 1),
                               caption: SWText.key(Geomag.activity(forKp: level)),
                               color: sw.severity(snapshot.geomagGScale))
                    MetricTile(id: "geomag.kp.ap", value: "\(Geomag.ap(forKp: level))", unit: "ap", caption: "current amplitude")
                    MetricTile(id: "geomag.kp.dailyAp", value: ap.map { "\($0.value)" } ?? "—", unit: "Ap",
                               caption: ap?.complete == false ? "daily (so far)" : "daily average")
                }
                MeaningLine("The 28-level Kp scale (Bartels) with NOAA G-scale color bands. Ap is the day's mean amplitude.")
            }
            .tint(sw.side(.terra))
        }
    }
}
