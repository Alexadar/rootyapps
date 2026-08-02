import SwiftUI
import TidesKit

// ─────────────────────────────────────────────────────────────────────────────
// F1 · TIDES NOW — the root screen and the reason the watch app exists.
//
// The Digital Crown scrubs time across the station's day and the WHOLE readout
// follows: height, trend, rate, and the cursor on the curve. This is the watch's
// best affordance and the one thing it does better than the phone.
//
// ZERO math. Everything comes from TidesKit; the view model memoises a Snapshot
// per (station, unit, day) and does selection + formatting only.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class WatchTidesViewModel: ObservableObject {
    @Published var stationID: String { didSet { invalidate() } }
    @Published var unit: TideUnit { didSet { invalidate() } }

    /// Minutes past station midnight, 0…1440. The crown writes this; `nil` means
    /// "follow the clock". Presentation state, not a computed quantity.
    @Published var scrubMinute: Double?
    @Published var isScrubbing = false

    /// One evaluation pass per (station, unit, day). The phone learned this the
    /// hard way: reading `extremes` five times a body pass re-ran ~370 height
    /// evaluations each, and four separate `Date()` calls could sample four
    /// different instants.
    struct Snapshot {
        let station: Station
        let record: TideStationRecord
        let windowStart: Date
        /// 97 samples spanning 00:00…24:00 INCLUSIVE, so index/96 == time/24 h.
        let curve: [Double]
        let extremes: [TideEvent]
        let zone: String
        let datum: Double
    }

    private var cached: Snapshot?
    private var cacheKey: String = ""

    init(stationID: String = WatchStationStore.storedTideStationID,
         unit: TideUnit = WatchStationStore.storedUnit) {
        self.stationID = stationID
        self.unit = unit
    }

    private func invalidate() { cached = nil }

    var record: TideStationRecord {
        StationCatalog.tideStations.first { $0.id == stationID }
            ?? StationCatalog.tideStations[0]
    }

    /// Station-local, always. The watch's own zone must never leak into a tide time.
    private var stationCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = record.timeZone
        return c
    }

    func snapshot(now: Date = Date()) -> Snapshot {
        let rec = record
        let cal = stationCalendar
        let start = cal.startOfDay(for: now)
        let key = "\(rec.id)|\(unit)|\(start.timeIntervalSince1970)"
        if let cached, cacheKey == key { return cached }

        let station = rec.station(unit: unit)
        let snap = Snapshot(
            station: station,
            record: rec,
            windowStart: start,
            curve: Harmonics.heights(station, from: start, count: 97, stepSeconds: 15 * 60),
            extremes: Harmonics.extremes(station, start: start, hours: 24),
            zone: rec.timeZone.abbreviation(for: start) ?? rec.timeZoneIdentifier,
            datum: 0)
        cached = snap
        cacheKey = key
        return snap
    }

    // MARK: Selection & formatting only

    /// The instant the readout is describing: the scrub position, or now.
    func readoutDate(_ snap: Snapshot, now: Date = Date()) -> Date {
        guard let m = scrubMinute else { return now }
        return snap.windowStart.addingTimeInterval(m * 60)
    }

    func height(_ snap: Snapshot, at date: Date) -> Double {
        Harmonics.height(snap.station, at: date)
    }

    func slope(_ snap: Snapshot, at date: Date) -> Double {
        Harmonics.slope(snap.station, at: date)
    }

    func unitLabel() -> String { unit == .meters ? "m" : "ft" }
    func unitSpoken() -> String { unit == .meters ? "metres" : "feet" }

    func value(_ v: Double) -> String { v.formatted(WatchFormat.number(2...2)) }

    func time(_ d: Date, _ snap: Snapshot) -> String {
        WatchFormat.time(d, zone: snap.record.timeZone)
    }

    func cursorFraction(_ snap: Snapshot, at date: Date) -> Double? {
        let f = date.timeIntervalSince(snap.windowStart) / (24 * 3600)
        return (0...1).contains(f) ? f : nil
    }

    /// Next turning point after the readout instant — `first { … }` over what the
    /// Kit already returned.
    func nextExtreme(_ snap: Snapshot, after date: Date) -> TideEvent? {
        snap.extremes.first { $0.date > date }
    }

    func marks(_ snap: Snapshot) -> [WatchCurveMark] {
        snap.extremes.enumerated().map { i, e in
            WatchCurveMark(id: i,
                           x: e.date.timeIntervalSince(snap.windowStart) / (24 * 3600),
                           y: e.height,
                           positive: e.kind == .high)
        }
    }
}

struct WatchTidesNowView: View {
    @StateObject private var model = WatchTidesViewModel()
    @Environment(\.watchTheme) private var theme
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var crownMinute: Double = 0
    /// Set only around the programmatic `crownMinute` write in `resetScrub`, so that
    /// write is not mistaken for the user turning the crown.
    @State private var ignoreNextCrownChange = false
    /// ⚠ watchOS: `.digitalCrownRotation` only delivers to the view that HOLDS FOCUS, and
    /// `Button` is focusable by default. `.focusable()` alone is not enough — tapping any
    /// sibling button moves focus off the scroll view and the crown goes silently dead.
    /// Nothing crashes and nothing looks wrong; the day just stops scrubbing. Focus has to be
    /// reclaimed explicitly after every button on this screen. (Same pattern ephemeris's
    /// watch root already uses.)
    @FocusState private var crownFocused: Bool
    @State private var showStationPicker = false

    /// Re-renders the readout on the minute. The always-on state is not a live
    /// view, so the tick is ignored while dimmed.
    @State private var tick = Date()
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let size = WatchSize.measuring(geo.size.width)
            let snap = model.snapshot(now: tick)
            let date = model.readoutDate(snap, now: tick)
            let h = model.height(snap, at: date)
            let s = model.slope(snap, at: date)
            let next = model.nextExtreme(snap, after: date)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    stationLine(snap)

                    WatchHero(value: model.value(h),
                              unit: model.unitLabel(),
                              positive: s >= 0,
                              rate: "\(model.value(abs(s))) \(model.unitLabel())/h",
                              size: size,
                              identifier: "result.nowHeight",
                              voiceOver: heroVoiceOver(snap, date: date, height: h, slope: s))

                    // Scrub state is stated in words — a cursor 30 pt wide is not
                    // enough to tell you you are looking at 14:20, not now.
                    if model.scrubMinute != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.system(size: 10, weight: .semibold))
                            Text(model.time(date, snap))
                                .font(WatchType.mono13)
                                .monospacedDigit()
                            Text(snap.zone).font(WatchType.mono11)
                            Spacer(minLength: 4)
                            Button("NOW") {
                                withAnimation { resetScrub(snap) }
                                crownFocused = true          // else the crown dies on the tap
                            }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.palette.water)
                                .accessibilityIdentifier("input.scrubReset")
                        }
                        .foregroundStyle(theme.palette.caution)
                        .frame(minHeight: 26)
                    }

                    WatchTideCurve(samples: snap.curve,
                                   marks: model.marks(snap),
                                   datumValue: snap.datum,
                                   cursorX: model.cursorFraction(snap, at: date),
                                   scrubbing: model.isScrubbing,
                                   height: size.curveHeight)
                        .accessibilityLabel(curveVoiceOver(snap))

                    if let next {
                        WatchNextTurn(kind: next.kind == .high ? "High" : "Low",
                                      high: next.kind == .high,
                                      time: model.time(next.date, snap),
                                      countdown: WatchFormat.countdown(
                                        Int(next.date.timeIntervalSince(date)),
                                        coarse: luminanceReduced),
                                      identifier: "result.nextTurn",
                                      voiceOver: nextVoiceOver(snap, next: next, from: date))
                            .frame(minHeight: 28)
                    }

                    // Everything below here is one scroll down, by design: the
                    // first screenful is the instrument.
                    if !luminanceReduced {
                        extremesList(snap)
                        WatchCard {
                            HStack {
                                Text("Datum").font(WatchType.labelSmall)
                                    .foregroundStyle(theme.palette.inkDim)
                                Spacer()
                                Text("MLLW").font(WatchType.mono13)
                                    .foregroundStyle(theme.ambientInk)
                            }
                            Text("Heights are above mean lower low water.")
                                .font(WatchType.caption)
                                .foregroundStyle(theme.palette.inkDim)
                        }
                        WatchCaveat(text: "Astronomical tide only — surge, wind and river flow "
                                        + "are not modelled.")
                        WatchProvenance(kit: "TidesKit",
                                        authority: "NOAA CO-OPS published predictions and "
                                                 + "Schureman SP-98")
                    }
                }
                .padding(.horizontal, size.gutter)
                .padding(.bottom, 8)
            }
            .background(theme.palette.canvas)
            // The crown owns the day. Detents every 15 minutes match the sample
            // grid, so the cursor never lands between two knowns.
            .focusable(!luminanceReduced)
            .focused($crownFocused)
            .digitalCrownRotation($crownMinute,
                                  from: 0, through: 1440, by: 15,
                                  // .high = less rotation per detent. Kept `by: 15` so the
                                  // cursor still lands on a real sample, per the design rule.
                                  sensitivity: .high,
                                  isContinuous: false,
                                  isHapticFeedbackEnabled: true)
            .onChange(of: crownMinute) { _, new in
                // `resetScrub` writes `crownMinute` programmatically and that write lands here
                // too. Without this guard the `onAppear` reset flipped the view straight into
                // scrubbing, so the app OPENED showing a scrub time and a NOW button instead of
                // a plain now-reading. Only a real crown turn should count as scrubbing.
                if ignoreNextCrownChange { ignoreNextCrownChange = false; return }
                model.isScrubbing = true
                model.scrubMinute = new
            }
            .onAppear { resetScrub(snap); crownFocused = true }
            // Coming back from the always-on state the view becomes focusable again, but
            // nothing re-focuses it on its own.
            .onChange(of: luminanceReduced) { _, dimmed in
                if !dimmed { crownFocused = true }
            }
        }
        .environment(\.watchTheme, luminanceReduced ? theme.dimmed : theme)
        .sheet(isPresented: $showStationPicker) {
            WatchStationPickerView(selection: $model.stationID)
        }
        // The sheet takes focus with it; reclaim it on the way back.
        .onChange(of: showStationPicker) { _, shown in
            if !shown { crownFocused = true }
        }
        .onReceive(minuteTick) { now in
            guard !luminanceReduced else { return }
            tick = now
        }
    }

    private func resetScrub(_ snap: WatchTidesViewModel.Snapshot) {
        model.scrubMinute = nil
        model.isScrubbing = false
        // Arm the guard ONLY when the value actually changes: `onChange` does not fire for an
        // identical write, and a stuck flag would swallow the user's next real scrub.
        let target = Date().timeIntervalSince(snap.windowStart) / 60
        if crownMinute != target {
            ignoreNextCrownChange = true
            crownMinute = target
        }
    }

    private func stationLine(_ snap: WatchTidesViewModel.Snapshot) -> some View {
        Button { showStationPicker = true } label: {
            HStack(spacing: 4) {
                Text(snap.record.name)
                    .font(WatchType.label)
                    .foregroundStyle(theme.ambientInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(snap.zone)
                    .font(WatchType.mono11)
                    .foregroundStyle(theme.palette.inkDim)
                if !luminanceReduced {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.palette.inkDim)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("input.station")
        .accessibilityLabel("Station \(snap.record.name), times in \(snap.zone). Change station.")
    }

    private func extremesList(_ snap: WatchTidesViewModel.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HIGH AND LOW — \(snap.zone)")
                .font(WatchType.section)
                .tracking(0.7)
                .foregroundStyle(theme.palette.inkDim)
            ForEach(Array(snap.extremes.enumerated()), id: \.offset) { i, e in
                HStack(spacing: 6) {
                    Image(systemName: e.kind == .high ? "arrowtriangle.up.fill"
                                                      : "arrowtriangle.down.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.palette.signByGlyph
                                         ? theme.ambientInk
                                         : (e.kind == .high ? theme.palette.water
                                                            : theme.palette.ebb))
                    Text(model.time(e.date, snap))
                        .font(WatchType.valueSmall)
                        .monospacedDigit()
                        .foregroundStyle(theme.ambientInk)
                    Spacer(minLength: 2)
                    WatchSlot(text: model.value(e.height), font: WatchType.valueSmall,
                              width: 48, color: theme.ambientInk)
                    Text(model.unitLabel())
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                }
                .frame(minHeight: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("result.extreme.\(i)")
                .accessibilityLabel("\(e.kind == .high ? "High" : "Low") water "
                                    + "\(model.time(e.date, snap)) \(snap.zone), "
                                    + "\(model.value(e.height)) \(model.unitSpoken())")
            }
        }
    }

    // MARK: VoiceOver — full quantity, unit, and the station's zone

    private func heroVoiceOver(_ snap: WatchTidesViewModel.Snapshot,
                               date: Date, height: Double, slope: Double) -> String {
        let when = model.scrubMinute == nil ? "Now" : "At \(model.time(date, snap)) \(snap.zone)"
        return "\(when), \(model.value(height)) \(model.unitSpoken()) above chart datum, "
             + "\(slope >= 0 ? "rising" : "falling") "
             + "\(model.value(abs(slope))) \(model.unitSpoken()) per hour, "
             + "at \(snap.record.name)."
    }

    private func nextVoiceOver(_ snap: WatchTidesViewModel.Snapshot,
                               next: TideEvent, from date: Date) -> String {
        "Next \(next.kind == .high ? "high" : "low") water "
        + "\(model.time(next.date, snap)) \(snap.zone), "
        + "in \(WatchFormat.countdown(Int(next.date.timeIntervalSince(date)))), "
        + "\(model.value(next.height)) \(model.unitSpoken())."
    }

    private func curveVoiceOver(_ snap: WatchTidesViewModel.Snapshot) -> String {
        "Tide curve for \(snap.record.name), midnight to midnight \(snap.zone). "
        + "Turn the Digital Crown to scrub through the day."
    }
}

#Preview("Tides now — dusk") {
    WatchTidesNowView().environment(\.watchTheme, WatchTheme(mode: .dark))
}

#Preview("Tides now — day / sunlight") {
    WatchTidesNowView().environment(\.watchTheme, WatchTheme(mode: .day))
}

#Preview("Tides now — night red") {
    WatchTidesNowView().environment(\.watchTheme, WatchTheme(mode: .nightRed))
}

#Preview("Tides now — always-on") {
    WatchTidesNowView().environment(\.watchTheme, WatchTheme(mode: .dark).dimmed)
}
