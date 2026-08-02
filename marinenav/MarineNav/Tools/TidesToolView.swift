import SwiftUI
import TidesKit

/// The product's hero screen: predicted tide for a station and a day, offline.
///
/// ZERO math here. Every number comes from `TidesKit`; the view-model only picks
/// the window, formats, and maps already-computed values onto the chart's 0…1
/// axes. `nextExtreme` / `countdown` are selection and formatting over the events
/// `Harmonics.extremes` returned — no prediction is repeated in the view layer.
@MainActor
final class TidesViewModel: ObservableObject {
    @Published var stationID: String = StationCatalog.tideStations.first!.id {
        didSet {
            // Re-anchor the day to the NEW station's today — but only if it was still the old
            // station's today, i.e. the user never picked a date. A deliberately chosen date
            // survives a station change. Stateless: `oldValue` is enough to tell the two apart.
            guard let old = StationCatalog.tideStations.first(where: { $0.id == oldValue }),
                  day == StationDay.today(in: old.timeZone) else { return }
            day = StationDay.today(in: record.timeZone)
        }
    }
    @Published var unit: TideUnit = .feet
    /// The station's today, NOT the device's — see `StationDay`.
    @Published var day: Date

    init() {
        day = StationDay.today(in: StationCatalog.tideStations.first!.timeZone)
    }

    var record: TideStationRecord {
        StationCatalog.tideStations.first { $0.id == stationID }
            ?? StationCatalog.tideStations[0]
    }

    var station: Station { snapshot.station }

    /// Everything on this screen is reckoned in the **station's** time zone, not
    /// the device's. A tide table read in the wrong zone is a navigational error.
    var stationCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = record.timeZone
        return c
    }

    /// Midnight of the *picked calendar date* at the station — what a mariner
    /// means by "today".
    var windowStart: Date {
        let ymd = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return stationCalendar.date(from: DateComponents(year: ymd.year,
                                                         month: ymd.month,
                                                         day: ymd.day))
            ?? stationCalendar.startOfDay(for: day)
    }

    var windowEnd: Date { windowStart.addingTimeInterval(24 * 3600) }

    /// e.g. "PDT" — shown next to the times so the zone is never ambiguous.
    var timeZoneAbbreviation: String {
        record.timeZone.abbreviation(for: windowStart) ?? record.timeZoneIdentifier
    }

    // MARK: Prediction snapshot
    //
    // Everything the screen shows is computed ONCE per (station, unit, day) and
    // cached. Without this, each of `curve`/`extremes`/`nowHeight`/`nowSlope` was a
    // computed property re-running the Kit on every SwiftUI body pass — and the
    // redesign references `extremes` five times and `nowSlope` four times per pass.
    // `Harmonics.extremes(24h)` alone is ~370 height evaluations, and `station`
    // re-parsed the station's constituent table on every access.
    //
    // It also fixes a correctness wrinkle: the hero height, the rate, the now-marker
    // and the countdown each called `Date()` separately and could sample four
    // different instants. Now they share one.
    private struct Snapshot {
        let key: String
        let now: Date
        let station: Station
        let curve: [Double]
        let extremes: [TideEvent]
        let nowHeight: Double
        let nowSlope: Double
    }

    /// Plain stored property, deliberately NOT `@Published`: it is a cache, and
    /// publishing it from a getter during a body pass would re-enter the update.
    private var cached: Snapshot?

    private var snapshotKey: String {
        "\(stationID)|\(unit.rawValue)|\(windowStart.timeIntervalSince1970)"
    }

    private var snapshot: Snapshot {
        if let c = cached, c.key == snapshotKey { return c }
        let s = record.station(unit: unit)
        let now = Date()
        // 97 samples spans 00:00…24:00 inclusive, so sample index i maps to the exact
        // time fraction i/96 — the same axis the markers and the now-line use. With 96
        // the last sample was 23:45 but was drawn at x = 1.0, a 15-minute lie.
        let c = Snapshot(key: snapshotKey, now: now, station: s,
                         curve: Harmonics.heights(s, from: windowStart, count: 97,
                                                  stepSeconds: 15 * 60),
                         extremes: Harmonics.extremes(s, start: windowStart, hours: 24),
                         nowHeight: Harmonics.height(s, at: now),
                         nowSlope: Harmonics.slope(s, at: now))
        cached = c
        return c
    }

    var curve: [Double] { snapshot.curve }
    var extremes: [TideEvent] { snapshot.extremes }
    var nowHeight: Double { snapshot.nowHeight }

    /// Rate of change right now — rising or falling, and how fast.
    var nowSlope: Double { snapshot.nowSlope }

    var unitLabel: String { unit == .meters ? "m" : "ft" }

    // MARK: Presentation

    func format(_ v: Double) -> String { String(format: "%.2f", v) }

    func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = stationCalendar
        f.timeZone = record.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    func dayLabel() -> String {
        let f = DateFormatter()
        f.calendar = stationCalendar
        f.timeZone = record.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM yyyy"
        return f.string(from: windowStart)
    }

    /// Where "now" sits in the plotted window, or nil when the window is not today.
    var nowFraction: Double? {
        let now = snapshot.now
        guard now >= windowStart, now < windowEnd else { return nil }
        return now.timeIntervalSince(windowStart) / (24 * 3600)
    }

    var nowLabel: String? {
        guard nowFraction != nil else { return nil }
        return "\(time(snapshot.now)) · \(format(nowHeight)) \(unitLabel)"
    }

    /// The next turning point after now — selection over `extremes`, not a new
    /// prediction.
    var nextExtreme: TideEvent? {
        let now = snapshot.now
        return extremes.first { $0.date > now }
    }

    var countdown: String? {
        guard let next = nextExtreme else { return nil }
        let s = Int(next.date.timeIntervalSince(snapshot.now))
        guard s > 0 else { return nil }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    var chartMarkers: [ChartMarker] {
        extremes.enumerated().map { i, e in
            ChartMarker(id: i,
                        x: e.date.timeIntervalSince(windowStart) / (24 * 3600),
                        value: format(e.height),
                        time: time(e.date),
                        positive: e.kind == .high,
                        y: e.height)
        }
    }
}

struct TidesToolView: View {
    @StateObject private var model = TidesViewModel()
    @Environment(\.marine) private var theme

    var body: some View {
        ToolScreen(tool: .tides) {
            stationCard

            HeroReadout(value: model.format(model.nowHeight),
                        unit: model.unitLabel,
                        stateLabel: model.nowSlope >= 0 ? "RISING" : "FALLING",
                        stateValue: "\(model.format(abs(model.nowSlope))) \(model.unitLabel)/h",
                        positive: model.nowSlope >= 0,
                        nextEvent: model.nextExtreme.map {
                            ($0.kind == .high ? "High" : "Low",
                             model.time($0.date),
                             model.countdown ?? "—")
                        },
                        identifier: "result.nowHeight",
                        stateIdentifier: "result.nowSlope")
                .accessibilityElement(children: .contain)

            VStack(spacing: 7) {
                TideCurve(samples: model.curve,
                          markers: model.chartMarkers,
                          nowX: model.nowFraction,
                          nowLabel: model.nowLabel,
                          datumValue: 0,
                          datumLabel: "MLLW",
                          unitLabel: model.unitLabel)
                HStack {
                    Text("Hours, station local")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.palette.inkDim)
                    Spacer()
                    Text(model.timeZoneAbbreviation)
                        .font(MarineType.mono11)
                        .foregroundStyle(theme.palette.ink)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, MarineMetrics.gutter)
            .padding(.bottom, MarineMetrics.sectionGap)

            ToolSection(title: "High and low water — \(model.timeZoneAbbreviation)") {
                if model.extremes.isEmpty {
                    Text("No turning points in this window.")
                        .font(MarineType.label)
                        .foregroundStyle(theme.palette.inkDim)
                        .frame(minHeight: MarineMetrics.rowHeight)
                        .padding(.horizontal, MarineMetrics.cardPadding)
                } else {
                    ForEach(Array(model.extremes.enumerated()), id: \.offset) { index, e in
                        if index > 0 { MarineDivider() }
                        extremeRow(index: index, event: e)
                    }
                }
            }

            ToolSection(title: "Datum") {
                ResultRow(label: "Chart datum", value: "MLLW",
                          identifier: "result.chartDatum")
                MarineDivider()
                // NOAA's published Z0 for the station — date-independent, so this is the one
                // number on this screen a UI test can assert against a citation.
                ResultRow(label: "Mean sea level above datum",
                          value: model.format(model.station.meanWaterLevel),
                          unit: model.unitLabel,
                          identifier: "result.meanSeaLevel")
                MarineDivider()
                Text("Heights are above mean lower low water, the datum US charts sound to.")
                    .font(MarineType.caption)
                    .foregroundStyle(theme.palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MarineMetrics.cardPadding)
            }

            ModelCaveat(title: "Limits of this model",
                        text: "Astronomical tide only — surge, wind and river flow are not "
                            + "modelled. Accuracy is bounded by the station's published "
                            + "constituent set; do not read chart-datum accuracy at stations "
                            + "NOAA predicts with more constituents than it publishes.")

            ProvenanceFooter(tool: .tides,
                             evidence: "7.6 mm rms over four years of hourly predictions at "
                                     + "San Francisco.")
        }
    }

    // MARK: Pieces

    private var stationCard: some View {
        MarineCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.record.name)
                        .font(MarineType.rowTitle)
                        .foregroundStyle(theme.palette.ink)
                    Text([model.record.region, model.record.id].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(MarineType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                }
                Spacer(minLength: 8)
                // A Menu, not a bare Picker — a Picker renders its selected value as
                // the control label, repeating the station name this card already shows.
                Menu {
                    Picker("Station", selection: $model.stationID) {
                        ForEach(StationCatalog.tideStations) { s in
                            Text("\(s.name), \(s.region)").tag(s.id)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Change").font(MarineType.label)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                    }
                    .foregroundStyle(theme.palette.water)
                    .frame(minHeight: MarineMetrics.tapTarget)
                }
                .accessibilityIdentifier("input.station")
            }
            .frame(minHeight: MarineMetrics.controlHeight)
            .padding(.horizontal, MarineMetrics.cardPadding)

            MarineDivider()

            HStack {
                Text("Day").font(MarineType.label).foregroundStyle(theme.palette.inkDim)
                Spacer()
                DatePicker("Day", selection: $model.day, displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("input.day")
            }
            .frame(minHeight: MarineMetrics.controlHeight)
            .padding(.horizontal, MarineMetrics.cardPadding)

            MarineDivider()

            MarineSegmented(selection: $model.unit,
                            options: [(.feet, "Feet"), (.meters, "Metres")],
                            idPrefix: "input.units")
                .padding(MarineMetrics.cardPadding)
        }
        .padding(.bottom, MarineMetrics.sectionGap)
    }

    private func extremeRow(index: Int, event e: TideEvent) -> some View {
        let high = e.kind == .high
        return HStack(spacing: 12) {
            Image(systemName: high ? "arrow.up" : "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
                .foregroundStyle(theme.palette.signByGlyph
                                 ? theme.palette.ink
                                 : (high ? theme.palette.water : theme.palette.ebb))
            Text(e.kind.rawValue)
                .font(MarineType.label)
                .foregroundStyle(theme.palette.ink)
            Spacer(minLength: 8)
            Text(model.time(e.date))
                .font(MarineType.value)
                .monospacedDigit()
                .foregroundStyle(theme.palette.ink)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(model.format(e.height))
                    .font(MarineType.valueEmphasis)
                    .monospacedDigit()
                Text(model.unitLabel)
                    .font(MarineType.caption)
                    .foregroundStyle(theme.palette.inkDim)
            }
            .frame(width: 84, alignment: .trailing)
            .foregroundStyle(theme.palette.ink)
        }
        .frame(minHeight: 48)
        .padding(.horizontal, MarineMetrics.cardPadding)
        .accessibilityIdentifier("result.extreme.\(index)")
    }
}

#Preview("Tides — day") {
    NavigationStack { TidesToolView() }
        .environment(\.marine, MarineTheme(mode: .day))
}

#Preview("Tides — dark") {
    NavigationStack { TidesToolView() }
        .environment(\.marine, MarineTheme(mode: .dark))
}

#Preview("Tides — night dim") {
    NavigationStack { TidesToolView() }
        .environment(\.marine, MarineTheme(mode: .nightDim))
}

#Preview("Tides — night red") {
    NavigationStack { TidesToolView() }
        .environment(\.marine, MarineTheme(mode: .nightRed))
}
