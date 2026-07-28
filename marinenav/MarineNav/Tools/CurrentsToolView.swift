import SwiftUI
import TidesKit

/// Tidal current for a station and bin. ZERO math here: `Currents` produces the
/// velocities and the events; the view-model converts to knots (the unit a
/// mariner reads), formats, and maps onto the chart's 0…1 axes.
@MainActor
final class CurrentsViewModel: ObservableObject {
    @Published var stationKey: String = StationCatalog.currentStations.first!.stationKey {
        didSet {
            // Same re-anchoring rule as Tides: follow the new station only while the day is
            // still the old station's today (i.e. untouched by the user).
            guard let old = StationCatalog.currentStations.first(where: { $0.stationKey == oldValue }),
                  day == StationDay.today(in: old.timeZone) else { return }
            day = StationDay.today(in: record.timeZone)
        }
    }
    /// The station's today, NOT the device's — see `StationDay`.
    @Published var day: Date

    init() {
        day = StationDay.today(in: StationCatalog.currentStations.first!.timeZone)
    }

    var record: CurrentStationRecord {
        StationCatalog.currentStations.first { $0.stationKey == stationKey }
            ?? StationCatalog.currentStations[0]
    }

    var station: CurrentStation { snapshot.station }

    /// Reckoned in the **station's** time zone, not the device's.
    var stationCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = record.timeZone
        return c
    }

    var windowStart: Date {
        let ymd = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return stationCalendar.date(from: DateComponents(year: ymd.year,
                                                         month: ymd.month,
                                                         day: ymd.day))
            ?? stationCalendar.startOfDay(for: day)
    }

    var windowEnd: Date { windowStart.addingTimeInterval(24 * 3600) }

    var timeZoneAbbreviation: String {
        record.timeZone.abbreviation(for: windowStart) ?? record.timeZoneIdentifier
    }

    // MARK: Prediction snapshot
    //
    // Computed ONCE per (station, day) and cached — see the note on
    // `TidesViewModel`. `Currents.events(24h)` is ~432 velocity evaluations plus
    // bisections, and the redesign reads `events` from four places per body pass.
    private struct Snapshot {
        let key: String
        let now: Date
        let station: CurrentStation
        let series: [Double]
        let events: [CurrentEvent]
        let nowVelocity: Double
    }

    /// Plain stored property, deliberately NOT `@Published` — it is a cache.
    private var cached: Snapshot?

    private var snapshotKey: String {
        "\(stationKey)|\(windowStart.timeIntervalSince1970)"
    }

    private var snapshot: Snapshot {
        if let c = cached, c.key == snapshotKey { return c }
        let s = record.station()
        let now = Date()
        // 97 samples spans 00:00…24:00 inclusive so index i maps to the exact time
        // fraction i/96, matching the markers and the now-line.
        let c = Snapshot(key: snapshotKey, now: now, station: s,
                         series: (0...96).map {
                             Currents.velocity(s, at: windowStart
                                 .addingTimeInterval(Double($0) * 15 * 60))
                         },
                         events: Currents.events(s, start: windowStart, hours: 24),
                         nowVelocity: Currents.velocity(s, at: now))
        cached = c
        return c
    }

    var series: [Double] { snapshot.series }
    var events: [CurrentEvent] { snapshot.events }
    var now: Double { snapshot.nowVelocity }

    /// Speed in knots — what a mariner actually reads. 1 kn = 51.4444 cm/s.
    func knots(_ cms: Double) -> Double { cms / 51.4444 }

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

    var nowFraction: Double? {
        let now = snapshot.now
        guard now >= windowStart, now < windowEnd else { return nil }
        return now.timeIntervalSince(windowStart) / (24 * 3600)
    }

    var nextEvent: CurrentEvent? {
        let now = snapshot.now
        return events.first { $0.date > now }
    }

    var countdown: String? {
        guard let next = nextEvent else { return nil }
        let s = Int(next.date.timeIntervalSince(snapshot.now))
        guard s > 0 else { return nil }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    var setNow: Double {
        now >= 0 ? station.meanFloodDirectionDeg : station.meanEbbDirectionDeg
    }

    var chartMarkers: [ChartMarker] {
        events.enumerated().map { i, e in
            ChartMarker(id: i,
                        x: e.date.timeIntervalSince(windowStart) / (24 * 3600),
                        value: e.phase == .slack ? "" : format(abs(knots(e.velocityCMS))),
                        time: time(e.date),
                        positive: e.phase == .flood,
                        hollow: e.phase == .slack,
                        y: e.phase == .slack ? 0 : knots(e.velocityCMS))
        }
    }
}

struct CurrentsToolView: View {
    @StateObject private var model = CurrentsViewModel()
    @Environment(\.marine) private var theme

    var body: some View {
        ToolScreen(tool: .currents) {
            stationCard

            HeroReadout(value: model.format(abs(model.knots(model.now))),
                        unit: "kn",
                        stateLabel: model.now >= 0 ? "FLOODING" : "EBBING",
                        stateValue: String(format: "set %03.0f°T", model.setNow),
                        positive: model.now >= 0,
                        nextEvent: model.nextEvent.map {
                            ($0.phase.rawValue, model.time($0.date), model.countdown ?? "—")
                        },
                        identifier: "result.nowVelocity",
                        stateIdentifier: "result.nowSet")

            VStack(spacing: 7) {
                CurrentGraph(samples: model.series.map { model.knots($0) },
                             markers: model.chartMarkers,
                             nowX: model.nowFraction,
                             floodLabel: String(format: "Flood %03.0f°",
                                                model.station.meanFloodDirectionDeg),
                             ebbLabel: String(format: "Ebb %03.0f°",
                                              model.station.meanEbbDirectionDeg))
                HStack {
                    Text("Flood above the line, ebb below")
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

            ToolSection(title: "Slack and maximum — \(model.timeZoneAbbreviation)") {
                if model.events.isEmpty {
                    Text("No events in this window.")
                        .font(MarineType.label)
                        .foregroundStyle(theme.palette.inkDim)
                        .frame(minHeight: MarineMetrics.rowHeight)
                        .padding(.horizontal, MarineMetrics.cardPadding)
                } else {
                    ForEach(Array(model.events.enumerated()), id: \.offset) { index, e in
                        if index > 0 { MarineDivider() }
                        eventRow(index: index, event: e)
                    }
                }
            }

            ToolSection(title: "Axis") {
                ResultRow(label: "Mean flood",
                          value: String(format: "%.0f", model.station.meanFloodDirectionDeg),
                          unit: "°T")
                MarineDivider()
                ResultRow(label: "Mean ebb",
                          value: String(format: "%.0f", model.station.meanEbbDirectionDeg),
                          unit: "°T")
            }

            ModelCaveat(title: "Limits of this model",
                        text: "Major-axis (rectilinear) component only; rotary currents are not "
                            + "modelled. Positive is flood.")

            ProvenanceFooter(tool: .currents,
                             evidence: "Slack and maxima within 4.6 min and 4.1 cm/s of NOAA's "
                                     + "published predictions.")
        }
    }

    private var stationCard: some View {
        MarineCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.record.name)
                            .font(MarineType.rowTitle)
                            .foregroundStyle(theme.palette.ink)
                        Text("bin \(model.record.bin)")
                            .font(MarineType.mono12)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    Text([model.record.region, model.record.id].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(MarineType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                }
                Spacer(minLength: 8)
                // A Menu, not a bare Picker: a Picker renders its selected value as
                // the control label, which printed the station name a second time
                // beside the one this card already shows — and these names are long
                // enough ("Golden Gate Bridge, 0.46 nm E of") to wrap to three lines.
                Menu {
                    // Keyed by stationKey, not `id`: `CurrentStationRecord.id` is the
                    // NOAA station id WITHOUT the bin, so two bins of the same station
                    // would collide and silently drop a row.
                    Picker("Station", selection: $model.stationKey) {
                        ForEach(StationCatalog.currentStations, id: \.stationKey) { s in
                            Text("\(s.name) — bin \(s.bin)").tag(s.stationKey)
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
                .accessibilityIdentifier("input.currentStation")
            }
            .frame(minHeight: MarineMetrics.controlHeight)
            .padding(.horizontal, MarineMetrics.cardPadding)

            MarineDivider()

            HStack {
                Text("Day").font(MarineType.label).foregroundStyle(theme.palette.inkDim)
                Spacer()
                DatePicker("Day", selection: $model.day, displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("input.currentDay")
            }
            .frame(minHeight: MarineMetrics.controlHeight)
            .padding(.horizontal, MarineMetrics.cardPadding)
        }
        .padding(.bottom, MarineMetrics.sectionGap)
    }

    private func eventRow(index: Int, event e: CurrentEvent) -> some View {
        let color: Color = theme.palette.signByGlyph ? theme.palette.ink : {
            switch e.phase {
            case .slack: return theme.palette.inkDim
            case .flood: return theme.palette.flood
            case .ebb:   return theme.palette.ebb
            }
        }()
        return HStack(spacing: 10) {
            Image(systemName: symbol(e.phase))
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
                .foregroundStyle(color)
            Text(e.phase.rawValue)
                .font(MarineType.label)
                .foregroundStyle(e.phase == .slack ? theme.palette.inkDim : theme.palette.ink)
            Spacer(minLength: 8)
            Text(model.time(e.date))
                .font(MarineType.value)
                .monospacedDigit()
                .foregroundStyle(theme.palette.ink)
            Text(e.phase == .slack ? "—" : model.format(abs(model.knots(e.velocityCMS))))
                .font(e.phase == .slack ? MarineType.value : MarineType.valueEmphasis)
                .monospacedDigit()
                .foregroundStyle(e.phase == .slack ? theme.palette.inkDim : theme.palette.ink)
                .frame(width: 66, alignment: .trailing)
            Text(e.directionDeg(model.station).map { String(format: "%.0f°", $0) } ?? "")
                .font(MarineType.mono12)
                .foregroundStyle(theme.palette.inkDim)
                .frame(width: 44, alignment: .trailing)
        }
        .frame(minHeight: MarineMetrics.rowHeight)
        .padding(.horizontal, MarineMetrics.cardPadding)
        .accessibilityIdentifier("result.currentEvent.\(index)")
    }

    private func symbol(_ p: CurrentPhase) -> String {
        switch p {
        case .slack: return "pause.circle"
        case .flood: return "arrow.right"
        case .ebb:   return "arrow.left"
        }
    }
}

#Preview("Currents — day") {
    NavigationStack { CurrentsToolView() }
        .environment(\.marine, MarineTheme(mode: .day))
}

#Preview("Currents — night red") {
    NavigationStack { CurrentsToolView() }
        .environment(\.marine, MarineTheme(mode: .nightRed))
}
