import SwiftUI
import TidesKit

// ─────────────────────────────────────────────────────────────────────────────
// F3 · CURRENTS
//
// Slack / max flood / max ebb, speed in knots, set in °true, next slack
// countdown. Flood ABOVE the zero rule, ebb BELOW it — position, never hue.
//
// ZERO math: `Currents.velocity` / `Currents.events` produce everything.
// `knots(_:)` is the published 51.4444 cm/s definition and carries over from the
// phone view model unchanged — the one pre-existing exception, not a new one.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class WatchCurrentsViewModel: ObservableObject {
    @Published var stationKey: String { didSet { cached = nil } }

    struct Snapshot {
        let station: CurrentStation
        let record: CurrentStationRecord
        let windowStart: Date
        /// 97 samples spanning 00:00…24:00 inclusive.
        let series: [Double]
        let events: [CurrentEvent]
        let zone: String
    }

    private var cached: Snapshot?
    private var cacheKey = ""

    init(stationKey: String = WatchStationStore.shared.selectedCurrentStationKey) {
        self.stationKey = stationKey
    }

    var record: CurrentStationRecord {
        StationCatalog.currentStations.first { $0.stationKey == stationKey }
            ?? StationCatalog.currentStations[0]
    }

    func snapshot(now: Date = Date()) -> Snapshot {
        let rec = record
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = rec.timeZone
        let start = cal.startOfDay(for: now)
        let key = "\(rec.stationKey)|\(start.timeIntervalSince1970)"
        if let cached, cacheKey == key { return cached }

        let station = rec.station()
        let snap = Snapshot(
            station: station,
            record: rec,
            windowStart: start,
            series: (0...96).map {
                Currents.velocity(station,
                                  at: start.addingTimeInterval(Double($0) * 15 * 60))
            },
            events: Currents.events(station, start: start, hours: 24),
            zone: rec.timeZone.abbreviation(for: start) ?? rec.timeZoneIdentifier)
        cached = snap
        cacheKey = key
        return snap
    }

    /// 1 kn = 51.4444 cm/s (published definition; carried over from the phone).
    func knots(_ cms: Double) -> Double { cms / 51.4444 }

    func value(_ v: Double) -> String { v.formatted(WatchFormat.number(2...2)) }

    func time(_ d: Date, _ s: Snapshot) -> String {
        WatchFormat.time(d, zone: s.record.timeZone)
    }

    func nextEvent(_ s: Snapshot, after date: Date) -> CurrentEvent? {
        s.events.first { $0.date > date }
    }

    func nextSlack(_ s: Snapshot, after date: Date) -> CurrentEvent? {
        s.events.first { $0.date > date && $0.phase == .slack }
    }

    /// Set now: the station's mean flood axis on the flood, its mean ebb axis on
    /// the ebb. Both numbers are the Kit's own published station constants.
    func set(_ s: Snapshot, velocity: Double) -> Double {
        velocity >= 0 ? s.station.meanFloodDirectionDeg : s.station.meanEbbDirectionDeg
    }

    func cursorFraction(_ s: Snapshot, at date: Date) -> Double? {
        let f = date.timeIntervalSince(s.windowStart) / (24 * 3600)
        return (0...1).contains(f) ? f : nil
    }
}

struct WatchCurrentsView: View {
    @StateObject private var model = WatchCurrentsViewModel()
    @Environment(\.watchTheme) private var theme
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var tick = Date()
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let size = WatchSize.measuring(geo.size.width)
            let snap = model.snapshot(now: tick)
            let v = model.knots(Currents.velocity(snap.station, at: tick))
            let flooding = v >= 0
            let set = model.set(snap, velocity: v)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(snap.record.name)
                            .font(WatchType.label)
                            .foregroundStyle(theme.ambientInk)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text("bin \(snap.record.bin)")
                            .font(WatchType.mono11)
                            .foregroundStyle(theme.palette.inkDim)
                        Spacer(minLength: 2)
                        Text(snap.zone)
                            .font(WatchType.mono11)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    .frame(minHeight: 22)

                    // Direction is stated as a WORD and an arrow glyph, and the
                    // curve puts it above or below the line. Three redundant
                    // encodings, none of them hue.
                    VStack(alignment: .leading, spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            speedRow(size.hero, v: v)
                            speedRow(size.hero - 6, v: v)
                            speedRow(size.hero - 12, v: v)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: flooding ? "arrow.right" : "arrow.left")
                                .font(.system(size: 11, weight: .bold))
                            Text(flooding ? "FLOOD" : "EBB")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.5)
                            Text(String(format: "set %03.0f°T", set))
                                .font(WatchType.mono11)
                                .monospacedDigit()
                        }
                        .foregroundStyle(theme.palette.signByGlyph
                                         ? theme.ambientInk
                                         : (flooding ? theme.palette.flood : theme.palette.ebb))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("result.nowVelocity")
                    .accessibilityLabel("\(model.value(abs(v))) knots, "
                                        + "\(flooding ? "flooding" : "ebbing"), "
                                        + "set \(Int(set.rounded())) degrees true, "
                                        + "at \(snap.record.name) bin \(snap.record.bin).")

                    WatchCurrentCurve(samples: snap.series.map { model.knots($0) },
                                      cursorX: model.cursorFraction(snap, at: tick),
                                      scrubbing: false,
                                      height: size.curveHeight)
                        .accessibilityLabel("Velocity curve, flood above the line, ebb below, "
                                            + "midnight to midnight \(snap.zone).")

                    if let slack = model.nextSlack(snap, after: tick) {
                        WatchNextTurn(kind: "Slack",
                                      high: true,
                                      time: model.time(slack.date, snap),
                                      countdown: WatchFormat.countdown(
                                        Int(slack.date.timeIntervalSince(tick)),
                                        coarse: luminanceReduced),
                                      identifier: "result.nextSlack",
                                      voiceOver: "Next slack water "
                                               + "\(model.time(slack.date, snap)) \(snap.zone), "
                                               + "in \(WatchFormat.countdown(Int(slack.date.timeIntervalSince(tick))))." )
                            .frame(minHeight: 28)
                    }

                    if !luminanceReduced {
                        eventsList(snap)
                        WatchCard {
                            HStack {
                                Text("Axes").font(WatchType.labelSmall)
                                    .foregroundStyle(theme.palette.inkDim)
                                Spacer()
                                Text(String(format: "flood %03.0f° · ebb %03.0f°",
                                            snap.station.meanFloodDirectionDeg,
                                            snap.station.meanEbbDirectionDeg))
                                    .font(WatchType.mono11)
                                    .monospacedDigit()
                                    .foregroundStyle(theme.ambientInk)
                            }
                        }
                        WatchCaveat(text: "Major-axis component only; rotary currents are not "
                                        + "modelled. Positive is flood.")
                        WatchProvenance(kit: "TidesKit · Currents",
                                        authority: "NOAA CO-OPS published current predictions")
                    }
                }
                .padding(.horizontal, size.gutter)
                .padding(.bottom, 8)
            }
            .background(theme.palette.canvas)
        }
        .environment(\.watchTheme, luminanceReduced ? theme.dimmed : theme)
        .onReceive(minuteTick) { now in
            guard !luminanceReduced else { return }
            tick = now
        }
    }

    private func speedRow(_ pt: CGFloat, v: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(model.value(abs(v)))
                .font(WatchType.hero(pt))
                .monospacedDigit()
                .foregroundStyle(theme.ambientHero)
            Text("kn")
                .font(.system(size: max(pt * 0.34, 12), weight: .medium))
                .foregroundStyle(theme.palette.inkDim)
        }
        .lineLimit(1)
    }

    private func eventsList(_ snap: WatchCurrentsViewModel.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SLACK AND MAXIMUM — \(snap.zone)")
                .font(WatchType.section).tracking(0.7)
                .foregroundStyle(theme.palette.inkDim)
            ForEach(Array(snap.events.enumerated()), id: \.offset) { i, e in
                let slack = e.phase == .slack
                HStack(spacing: 6) {
                    Image(systemName: slack ? "circle"
                                            : (e.phase == .flood ? "arrow.right" : "arrow.left"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.palette.signByGlyph
                                         ? theme.ambientInk
                                         : (slack ? theme.palette.inkDim
                                            : (e.phase == .flood ? theme.palette.flood
                                                                 : theme.palette.ebb)))
                    Text(model.time(e.date, snap))
                        .font(WatchType.valueSmall)
                        .monospacedDigit()
                        .foregroundStyle(theme.ambientInk)
                    Spacer(minLength: 2)
                    WatchSlot(text: slack ? "—" : model.value(abs(model.knots(e.velocityCMS))),
                              font: WatchType.valueSmall, width: 42,
                              color: slack ? theme.palette.inkDim : theme.ambientInk)
                    Text(slack ? "" : "kn")
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                        .frame(width: 16, alignment: .leading)
                }
                .frame(minHeight: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("result.currentEvent.\(i)")
                .accessibilityLabel(slack
                    ? "Slack water \(model.time(e.date, snap)) \(snap.zone)"
                    : "\(e.phase == .flood ? "Maximum flood" : "Maximum ebb") "
                      + "\(model.time(e.date, snap)) \(snap.zone), "
                      + "\(model.value(abs(model.knots(e.velocityCMS)))) knots")
            }
        }
    }
}

#Preview("Currents — dusk") {
    WatchCurrentsView().environment(\.watchTheme, WatchTheme(mode: .dark))
}

#Preview("Currents — night red") {
    WatchCurrentsView().environment(\.watchTheme, WatchTheme(mode: .nightRed))
}
