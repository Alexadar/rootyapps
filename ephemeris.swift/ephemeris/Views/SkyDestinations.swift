import SwiftUI
import EphemerisKit

/// The two Sky surfaces that are **not** readings of the current moment.
///
/// `MomentLens` answers "how do I want to look at this instant" — wheel, table, aspects, houses.
/// The Moon calendar and the planetary-hours ring answer something else entirely: they read a
/// **place over time**. A month of phases is not a view of one instant, and neither is a day
/// divided into twenty-four unequal hours.
///
/// They briefly lived as two extra lens segments, which is what forced the correction: the picker
/// went to six, and `MomentReadout`'s own comment already warned that *four* truncates once
/// translated — German *Geburtshoroskop*, Polish *Horoskop urodzeniowy*. Six segments do not fit an
/// iPhone in sixteen languages. Making them destinations fixes the layout and states the
/// distinction the code was already making.
enum SkyDestination: String, Hashable, CaseIterable, Identifiable {
    case moon, hours
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .moon:  "Moon"
        case .hours: "Hours"
        }
    }

    var icon: String {
        switch self {
        case .moon:  "moon"
        case .hours: "clock"
        }
    }
}

/// Where an `EPHEMERIS_LENS` value should land.
///
/// Pure and separate from the views so the deep-link contract can be asserted without launching an
/// app. **This is a compatibility surface, not a convenience:** every store screenshot and preview
/// reel is captured by setting these variables, and `moon`/`hours` were valid lens values before
/// they became destinations. They must keep working — pointing the capture pipeline at the wrong
/// screen is how an iPad screenshot of the wrong tab once shipped with a confident caption.
enum SkyRouting {

    /// Resolves a raw `EPHEMERIS_LENS` value.
    ///
    /// - Returns: the lens to select, and the destination to push. Exactly one is non-nil for a
    ///   recognised value; both are nil when the value means nothing, so the caller keeps its
    ///   default rather than guessing.
    static func resolve(_ raw: String?) -> (lens: MomentLens?, destination: SkyDestination?) {
        guard let raw else { return (nil, nil) }
        if let d = SkyDestination(rawValue: raw) { return (nil, d) }
        if let l = MomentLens(rawValue: raw) { return (l, nil) }
        return (nil, nil)
    }
}

// MARK: - The live-value rows

/// A glass row carrying a real current value, not just a label.
///
/// The value is the point: a row reading "Moon · 73% waxing" is worth tapping in a way that a row
/// reading "Moon" is not, and it makes Sky useful at a glance before the user goes anywhere.
struct SkyValueRow: View {
    let destination: SkyDestination
    let value: Text
    let detail: Text?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: destination.icon)
                .font(.headline)
                .foregroundStyle(NebulaPalette.accent)
                .frame(width: 30, height: 30)
                .background(NebulaPalette.accent.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.title).font(.callout)
                value.font(.caption).foregroundStyle(NebulaPalette.textSecondary)
            }
            Spacer()
            if let detail { detail.font(.caption).foregroundStyle(NebulaPalette.textFaint) }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(NebulaPalette.textFaint)
        }
        .contentShape(.rect)
    }
}

/// Both rows, with their values resolved from the moment.
struct SkyDestinationRows: View {
    let date: Date
    let location: GeoLocation?
    let timeZone: TimeZone
    let open: (SkyDestination) -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Identifier on the BUTTON, not on the row inside it: a Button becomes the
            // accessibility element and its label's identifier is not guaranteed to survive, so a
            // UI test looking for the row would find nothing on a screen that looks correct.
            Button { open(.moon) } label: { moonRow }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sky.moon.row")
            Divider().overlay(NebulaPalette.divider)
            Button { open(.hours) } label: { hoursRow }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sky.hours.row")
        }
        .glassCard()
        // `children: .contain` BEFORE the identifier, or the card's identifier propagates down and
        // overwrites the rows' own — both buttons then answer to "card.skyDestinations" and a test
        // looking for "sky.moon.row" finds nothing on a screen that is working perfectly.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.skyDestinations")
    }

    private var moonRow: SkyValueRow {
        let m = MoonPhases.snapshot(at: date)
        let state: LocalizedStringKey = m.waxing ? "Waxing" : "Waning"
        return SkyValueRow(destination: .moon,
                           value: Text("\("\(m.percent)%") \(Text(state))"),
                           detail: m.soonest.map { s in
                               s.phase == .full ? Text("Full in \(s.days) d")
                                                : Text("New in \(s.days) d")
                           })
    }

    /// Gate 1. With no place there is nothing to divide, and with no sunrise there is no division —
    /// both say so rather than showing a blank row that reads as a loading failure.
    private var hoursRow: SkyValueRow {
        guard let location else {
            return SkyValueRow(destination: .hours, value: Text("Set a location"), detail: nil)
        }
        guard let hours = PlanetaryHours.hours(startingOn: date, at: location, timeZone: timeZone),
              let current = hours.first(where: { $0.contains(date) })
        else {
            // Same distinction the ring makes, so the row and the screen it opens cannot disagree
            // about why there are no hours.
            let reason = HoursUnavailable.reason(at: location, on: date, timeZone: timeZone)
            return SkyValueRow(destination: .hours,
                               value: Text(reason == .polar ? "No sunrise today" : "Time zone mismatch"),
                               detail: nil)
        }
        let left = Int((current.end.timeIntervalSince(date) / 60).rounded())
        return SkyValueRow(destination: .hours,
                           value: Text(LocalizedStringKey(current.ruler.name)),
                           detail: Text("\(left) min left"))
    }
}

// MARK: - Gate 0

/// What Sky shows on a brand-new install.
///
/// Every other surface in the app is locked behind a birth record, and the wheel — which is what
/// Sky opened with — means nothing to someone who has entered nothing. The Moon is the one thing
/// this app can say on a fresh launch that is both true and legible, and it is also the only
/// function here with a measured paying audience.
///
/// ⚠️ **Nothing auto-presents.** This is a hero and two teaching rows; the location picker and the
/// chart entry open from a tap, never on appear.
struct SkyFirstRunHero: View {
    let date: Date

    var body: some View {
        let m = MoonPhases.snapshot(at: date)
        VStack(spacing: 8) {
            // No drawn disc: gate 0 means no location, therefore no latitude, and every phase
            // rendering is handed. Text is the only honest form here.
            Text(verbatim: "☽").font(.system(size: 44))
                .foregroundStyle(NebulaPalette.glyph)
                .nebulaGlow()
            Text(m.phase.heroName).font(.title3).bold()
            Text("\("\(m.percent)%") illuminated")
                .font(.callout).foregroundStyle(NebulaPalette.textSecondary)
            if let s = m.soonest {
                (s.phase == .full ? Text("Full in \(s.days) d") : Text("New in \(s.days) d"))
                    .font(.caption).foregroundStyle(NebulaPalette.textFaint)
            }
            Text("The sky right now — no birth details needed.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(NebulaPalette.textFaint)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sky.firstrun.hero")
    }
}

extension MoonPhases.Phase {
    /// Same four keys the widget ships, so the app and the widget cannot name the phase differently.
    var heroName: LocalizedStringKey {
        switch self {
        case .new:          "New Moon"
        case .firstQuarter: "First Quarter"
        case .full:         "Full Moon"
        case .lastQuarter:  "Last Quarter"
        }
    }
}

// MARK: - Chrome

extension View {
    /// Shared presentation for a pushed Sky surface, so the two destinations cannot drift apart in
    /// title, background or scroll behaviour.
    func skyDestinationChrome(_ destination: SkyDestination) -> some View {
        ScrollView { self.padding() }
            .background(AppBackground())
            .navigationTitle(destination.title)
            .assistantToolbar()
            .accessibilityIdentifier("screen.\(destination.rawValue)")
    }

    /// Each destination explains itself with its own context — the moon calendar and the hours ring
    /// share no vocabulary, and sending one screen's schema for the other is how a model starts
    /// answering about phases on a page of planetary hours.
    func skyDestinationAssistant(_ destination: SkyDestination, presenter: AssistantPresenter,
                                 date: Date, location: GeoLocation?, timeZone: TimeZone,
                                 charts: Int) -> some View {
        let id = ScreenContext.ScreenID(id: destination == .moon ? "sky.moon" : "sky.hours",
                                        title: destination == .moon ? "Moon calendar" : "Planetary hours")
        return assistantContext(presenter, screen: id) {
            switch destination {
            case .moon:
                ScreenContexts.moonCalendar(month: date, now: date, timeZone: timeZone,
                                            location: location, charts: charts, rowLimit: 4)
            case .hours:
                ScreenContexts.hours(now: date, timeZone: timeZone, location: location,
                                     charts: charts, rowLimit: 4)
            }
        }
    }

    /// Export for the Moon calendar: new and full moons over the next lunar year.
    ///
    /// Not the quarters — `AstroEvent.Kind` has no case for them and the CSV's `code` column is a
    /// published contract, so an invented code would break every existing reader. The sheet states
    /// the count, which is how the omission stays visible instead of silent.
    func moonExportToolbar(now: Date) -> some View {
        let range = DateInterval(start: now, duration: 365 * 86_400)
        return self.exportToolbar {
            let lunations = EventTimeline.allEvents(in: range)
                .filter { $0.kind == .newMoon || $0.kind == .fullMoon }
            return ExportPayload(subject: .moon("ephemeris-moon-phases"),
                                 content: .events(lunations),
                                 range: range)
        }
    }
}
