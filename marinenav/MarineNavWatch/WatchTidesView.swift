import SwiftUI
import TidesKit

/// Tides on the wrist — structural v0.1.
///
/// The seams the design pass will replace are deliberately obvious: `heroReadout`,
/// `trendLine`, `nextTurn`, `upcomingList`. What must SURVIVE restyling is marked inline;
/// those are carried over from the phone system and are not stylistic choices.
struct WatchTidesView: View {
    @State private var model = WatchTidesModel()
    @State private var showingStations = false

    var body: some View {
        // TimelineView so the countdown and the "now" height stay live while on screen,
        // and so the always-on dimmed state gets its own redraw cadence.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let p = model.prediction(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    stationHeader
                    heroReadout(p)
                    trendLine(p)
                    if let next = p.next { nextTurn(next, now: p.now) }
                    Divider()
                    upcomingList(p)
                    provenance
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $showingStations) {
            stationPicker
        }
    }

    // MARK: Seams

    private var stationHeader: some View {
        Button { showingStations = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.record.name).font(.headline).lineLimit(1)
                Text(model.record.id).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.station")
    }

    private func heroReadout(_ p: WatchTidesModel.Snapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            // MUST SURVIVE: monospaced digits. The height updates continuously and is read at
            // a glance in motion — proportional digits make it jitter.
            Text(String(format: "%.2f", p.height))
                .font(.system(.title, design: .monospaced).weight(.semibold))
            Text(model.unitLabel).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("watch.height")
        .accessibilityLabel("\(String(format: "%.2f", p.height)) \(model.unitLabel)")
    }

    private func trendLine(_ p: WatchTidesModel.Snapshot) -> some View {
        // MUST SURVIVE: rising vs falling reads by GLYPH, not by colour. In red-shift mode the
        // display is effectively monochrome, so a hue-only distinction conveys nothing.
        HStack(spacing: 4) {
            Image(systemName: p.isRising ? "arrow.up" : "arrow.down")
            Text(p.isRising ? "RISING" : "FALLING")
            Text(String(format: "%.2f %@/h", abs(p.slope), model.unitLabel))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .accessibilityIdentifier("watch.trend")
    }

    private func nextTurn(_ e: TideEvent, now: Date) -> some View {
        // MUST SURVIVE: every time carries the STATION's zone label. Tide times are never in
        // the watch's zone.
        HStack(spacing: 4) {
            Text(e.kind == .high ? "High" : "Low").fontWeight(.semibold)
            Text(model.clock(e.date)).font(.system(.body, design: .monospaced))
            Text(model.zoneLabel).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("in \(model.countdown(to: e.date, from: now))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityIdentifier("watch.nextTurn")
    }

    private func upcomingList(_ p: WatchTidesModel.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(p.events.filter { $0.date > p.now }.prefix(4).enumerated()),
                    id: \.offset) { _, e in
                HStack(spacing: 4) {
                    Image(systemName: e.kind == .high ? "arrow.up" : "arrow.down")
                    Text(model.clock(e.date)).font(.system(.caption2, design: .monospaced))
                    Spacer()
                    Text(String(format: "%.2f", e.height))
                        .font(.system(.caption2, design: .monospaced))
                }
            }
        }
        .accessibilityIdentifier("watch.upcoming")
    }

    private var provenance: some View {
        // MUST SURVIVE: the app names the Kit and the authority behind every number. On the
        // watch this may sit below the fold, but it may not disappear.
        Text("TidesKit · NOAA harmonic constants · computed on this device")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private var stationPicker: some View {
        List(StationCatalog.tideStations, id: \.id) { rec in
            Button {
                model.stationID = rec.id
                showingStations = false
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(rec.name).lineLimit(1)
                    Text(rec.region.isEmpty ? rec.id : "\(rec.region) · \(rec.id)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
