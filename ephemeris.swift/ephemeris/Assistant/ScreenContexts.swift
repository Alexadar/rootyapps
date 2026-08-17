import Foundation
import EphemerisKit

/// What each surface tells the assistant about itself.
///
/// One builder per screen, all pure functions of the state the screen already holds — so every one
/// is unit-testable without presenting a view, and the assistant can be exercised entirely without
/// eligible hardware.
///
/// ## The shared rules
///
/// - **Rank, never take the first N.** Each builder names its rule and records it in `Omission`.
/// - **Name only terms the glossary knows.** A field named `dignity` with no glossary entry gives
///   the model a heading and no meaning, which is how it starts inventing. A test asserts this.
/// - **State the gate.** The model must not offer a chart reading to someone who has entered
///   nothing, and must not apologise for missing data the user never promised.
enum ScreenContexts {

    /// The vocabulary each screen sends, declared in one place.
    ///
    /// Published rather than inlined so a test can assert `Glossary.unknown(in:)` is empty for every
    /// list. Inline literals could not be checked: `Glossary.entries(for:)` drops what it cannot
    /// find, so an undocumented term simply vanishes and no assertion on the resulting schema can
    /// see it.
    static let vocabulary: [String: [String]] = [
        "sky.wheel":   ["longitude", "sign", "degree in sign", "retrograde"],
        "sky.table":   ["longitude", "sign", "degree in sign", "retrograde"],
        "sky.aspects": ["aspect", "orb", "conjunction", "opposition", "square", "trine", "sextile"],
        "sky.houses":  ["house", "cusp", "ascendant", "midheaven", "house system", "sign"],
        "sky.moon":    ["phase", "illumination", "waxing", "waning", "moonrise",
                        "void of course", "synodic month"],
        "sky.hours":   ["planetary hour", "chaldean order", "hour ruler"],
        "cycles.timeline": ["ingress", "lunation", "mundane aspect", "station", "retrograde", "aspect"],
        "charts.natal": ["natal chart", "longitude", "sign", "degree in sign", "retrograde",
                         "aspect", "orb", "unknown birth time"],
        "charts.astrocartography": ["astrocartography", "MC line", "IC line", "AC line", "DC line",
                                    "circumpolar", "unknown birth time"],
    ]

    /// Named `vocabulary(for:)` rather than `terms(_:)`: providers hold a local `var terms`, and a
    /// same-named function is shadowed by it inside those scopes.
    static func vocabulary(for screenID: String) -> [String] { vocabulary[screenID] ?? [] }

    // MARK: - Shared pieces

    /// "18 Aug 2026 21:14 Europe/Kyiv · Kyiv 50.45N 30.52E · tropical".
    ///
    /// Everything that changes what the numbers *mean*, in one line. A model told only "Sun 26° Leo"
    /// cannot know whether that is today's sky, a birth chart or a sidereal reading — and all three
    /// appear in this app.
    static func situation(date: Date, timeZone: TimeZone, location: GeoLocation?,
                          zodiac: Ayanamsa?, houseSystem: HouseSystem? = nil) -> String {
        var parts: [String] = []
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        parts.append("\(f.string(from: date)) \(timeZone.identifier)")

        if let location {
            let ns = location.latitude >= 0 ? "N" : "S"
            let ew = location.longitude >= 0 ? "E" : "W"
            let place = location.name.map { "\($0) " } ?? ""
            parts.append(String(format: "%@%.2f%@ %.2f%@", place,
                                abs(location.latitude), ns, abs(location.longitude), ew))
        } else {
            parts.append("no location set")
        }

        parts.append(zodiac.map { "\($0.displayName) sidereal zodiac" } ?? "tropical zodiac")
        if let houseSystem { parts.append("\(houseSystem.rawValue) houses") }
        return parts.joined(separator: " · ")
    }

    static func gate(location: GeoLocation?, charts: Int, comparing: Bool = false) -> ScreenContext.Gate {
        if comparing, charts >= 2 { return .twoCharts }
        if charts >= 1 { return .oneChart }
        return location == nil ? .nothing : .place
    }

    // MARK: - Sky · the moment

    /// The wheel, the table and the aspect list are one screen read three ways, so they share a
    /// builder and differ only in which rows lead.
    static func sky(lens: MomentLens, moment: SkyMoment, date: Date, timeZone: TimeZone,
                    location: GeoLocation?, zodiac: Ayanamsa?, houseSystem: HouseSystem,
                    charts: Int, rowLimit: Int) -> ScreenContext {

        let title: String
        let rows: [ScreenContext.ContextRow]
        let omitted: ScreenContext.Omission?
        var terms = vocabulary(for: "sky.wheel")

        switch lens {
        case .aspects:
            title = "Sky · aspects"
            terms = vocabulary(for: "sky.aspects")
            let ranked = ContextRanking.tightest(moment.aspects, limit: rowLimit)
            rows = ranked.map { a in
                .init(title: "\(a.a.name) \(a.type.name) \(a.b.name)",
                      fields: [.init("orb", String(format: "%.2f°", abs(a.orb)))])
            }
            omitted = moment.aspects.count > ranked.count
                ? .init(shown: ranked.count, total: moment.aspects.count,
                        ranking: ContextRanking.tightestOrb)
                : nil

        case .houses:
            title = "Sky · houses"
            terms = vocabulary(for: "sky.houses")
            guard let h = moment.houses else {
                return ScreenContext(
                    screen: .init(id: "sky.houses", title: title),
                    gate: gate(location: location, charts: charts),
                    situation: situation(date: date, timeZone: timeZone, location: location,
                                         zodiac: zodiac, houseSystem: houseSystem),
                    schema: Glossary.entries(for: terms),
                    rows: [.init(title: "No houses",
                                 fields: [.init("reason", "houses need a location, and none is set")])])
            }
            let shown = min(rowLimit, 12)
            rows = (1...shown).map { n in
                .init(title: "House \(n)",
                      fields: [.init("cusp", String(format: "%.2f°", h.cusp(n))),
                               .init("sign", h.sign(ofCusp: n).name)])
            }
            omitted = shown < 12
                ? .init(shown: shown, total: 12, ranking: "the first houses, which include the Ascendant")
                : nil

        default:
            title = lens == .table ? "Sky · positions table" : "Sky · chart wheel"
            let ranked = ContextRanking.byProminence(moment.positions, limit: rowLimit)
            rows = ranked.map { p in
                .init(title: p.body.name,
                      fields: [.init("sign", p.sign.name),
                               .init("degree in sign", p.degMinString),
                               .init("retrograde", p.retrograde ? "yes" : "no")])
            }
            omitted = moment.positions.count > ranked.count
                ? .init(shown: ranked.count, total: moment.positions.count,
                        ranking: ContextRanking.classicalFirst)
                : nil
        }

        return ScreenContext(
            screen: .init(id: "sky.\(lens.rawValue)", title: title),
            gate: gate(location: location, charts: charts),
            situation: situation(date: date, timeZone: timeZone, location: location,
                                 zodiac: zodiac, houseSystem: houseSystem),
            schema: Glossary.entries(for: terms),
            rows: rows,
            omitted: omitted)
    }

    // MARK: - Moon calendar

    static func moonCalendar(month: Date, now: Date, timeZone: TimeZone, location: GeoLocation?,
                             charts: Int, rowLimit: Int) -> ScreenContext {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let snapshot = MoonPhases.snapshot(at: now)

        // The month's principal phases, nearest to now — the four instants the grid marks with a dot
        // and the only ones anyone asks about.
        let interval = cal.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 30 * 86_400)
        let phases = MoonPhases.phases(in: interval)
        let ranked = ContextRanking.nearest(phases, to: now, limit: rowLimit) { $0.date }

        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")

        var rows: [ScreenContext.ContextRow] = [
            .init(title: "Right now",
                  fields: [.init("phase", snapshot.phase.rawValue),
                           .init("illumination", "\(snapshot.percent)%"),
                           .init("waxing", snapshot.waxing ? "yes" : "no")])
        ]
        rows += ranked.map { e in
            .init(title: e.phase.rawValue, fields: [.init("when", f.string(from: e.date))])
        }

        return ScreenContext(
            screen: .init(id: "sky.moon", title: "Moon calendar"),
            gate: gate(location: location, charts: charts),
            situation: situation(date: now, timeZone: timeZone, location: location, zodiac: nil),
            schema: Glossary.entries(for: vocabulary(for: "sky.moon")),
            rows: rows,
            omitted: phases.count > ranked.count
                ? .init(shown: ranked.count, total: phases.count, ranking: ContextRanking.nearestToNow)
                : nil)
    }

    // MARK: - Planetary hours

    static func hours(now: Date, timeZone: TimeZone, location: GeoLocation?,
                      charts: Int, rowLimit: Int) -> ScreenContext {
        let terms = vocabulary(for: "sky.hours")
        let screen = ScreenContext.ScreenID(id: "sky.hours", title: "Planetary hours")
        let situationLine = situation(date: now, timeZone: timeZone, location: location, zodiac: nil)

        guard let location,
              let all = PlanetaryHours.hours(startingOn: now, at: location, timeZone: timeZone)
        else {
            // ⚠️ The absence is the answer, and which absence it is matters — the model must not
            // tell a user in Los Angeles that the Sun did not rise.
            let why: String = location == nil
                ? "no location is set, and planetary hours divide sunrise to sunset at a place"
                : (HoursUnavailable.reason(at: location!, on: now, timeZone: timeZone) == .polar
                    ? "the Sun does not rise or set here today, so there is no daylight interval to divide"
                    : "sunrise and sunset here fall on different days in the selected time zone, so the day cannot be divided")
            return ScreenContext(screen: screen, gate: gate(location: location, charts: charts),
                                 situation: situationLine,
                                 schema: Glossary.entries(for: terms),
                                 rows: [.init(title: "No hours today", fields: [.init("reason", why)])])
        }

        let currentIndex = all.firstIndex { $0.contains(now) }
        let ranked = ContextRanking.aroundCurrent(all, currentIndex: currentIndex, limit: rowLimit)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = timeZone

        return ScreenContext(
            screen: screen,
            gate: gate(location: location, charts: charts),
            situation: situationLine,
            schema: Glossary.entries(for: terms),
            rows: ranked.map { h in
                .init(title: "\(h.ruler.name) hour",
                      fields: [.init("from", f.string(from: h.start)),
                               .init("to", f.string(from: h.end)),
                               .init("length", "\(Int((h.duration / 60).rounded())) min"),
                               .init("current", h.contains(now) ? "yes" : "no")])
            },
            omitted: all.count > ranked.count
                ? .init(shown: ranked.count, total: all.count, ranking: ContextRanking.currentAndNext)
                : nil)
    }

    // MARK: - Cycles · the timeline

    static func timeline(events: [AstroEvent], window: DateInterval, now: Date,
                         timeZone: TimeZone, location: GeoLocation?,
                         charts: Int, rowLimit: Int) -> ScreenContext {
        let ranked = ContextRanking.nearest(events, to: now, limit: rowLimit) { $0.date }
        let f = DateFormatter()
        f.dateFormat = "d MMM HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")

        return ScreenContext(
            screen: .init(id: "cycles.timeline", title: "Cycles · event timeline"),
            gate: gate(location: location, charts: charts),
            situation: situation(date: now, timeZone: timeZone, location: location, zodiac: nil),
            schema: Glossary.entries(for: vocabulary(for: "cycles.timeline")),
            rows: ranked.map { e in
                .init(title: e.label(), fields: [.init("when", f.string(from: e.date))])
            },
            omitted: events.count > ranked.count
                ? .init(shown: ranked.count, total: events.count, ranking: ContextRanking.nearestToNow)
                : nil)
    }

    // MARK: - A saved chart

    static func natalChart(_ chart: SavedChart, positions: [BodyPosition], aspects: [DetectedAspect],
                           rowLimit: Int) -> ScreenContext {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy HH:mm"
        f.timeZone = chart.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")

        let ranked = ContextRanking.byProminence(positions, limit: rowLimit)
        var terms = vocabulary(for: "charts.natal").filter { $0 != "unknown birth time" }
        if !chart.isTimeKnown { terms.append("unknown birth time") }

        var rows: [ScreenContext.ContextRow] = ranked.map { p in
            .init(title: p.body.name,
                  fields: [.init("sign", p.sign.name),
                           .init("degree in sign", p.degMinString),
                           .init("retrograde", p.retrograde ? "yes" : "no")])
        }
        // ⚠️ Stated as a row, not omitted: without a birth time the houses and Ascendant do not
        // exist, and a model that is not told will happily discuss a rising sign that is undefined.
        if !chart.isTimeKnown {
            rows.insert(.init(title: "Birth time unknown",
                              fields: [.init("consequence",
                                             "houses, Ascendant and Midheaven are undefined, and the Moon may be off by up to 13°")]),
                        at: 0)
        }

        return ScreenContext(
            screen: .init(id: "charts.natal", title: "Birth chart · \(chart.name)"),
            gate: .oneChart,
            situation: "\(chart.name), born \(f.string(from: chart.birthInstant)) "
                     + "\(chart.timeZoneID) · \(chart.placeName ?? "unknown place")",
            schema: Glossary.entries(for: terms),
            rows: rows,
            omitted: positions.count > ranked.count
                ? .init(shown: ranked.count, total: positions.count,
                        ranking: ContextRanking.classicalFirst)
                : nil)
    }

    // MARK: - Astrocartography

    static func astrocartography(_ chart: SavedChart, lines: [AstroCartoLine],
                                 observer: GeoLocation?, rowLimit: Int) -> ScreenContext {
        let terms = vocabulary(for: "charts.astrocartography")
        let screen = ScreenContext.ScreenID(id: "charts.astrocartography", title: "Astrocartography")
        let situationLine = "\(chart.name)'s lines · "
            + (observer?.name.map { "you are near \($0)" } ?? "your location is not set")

        guard let observer else {
            return ScreenContext(screen: screen, gate: .oneChart, situation: situationLine,
                                 schema: Glossary.entries(for: terms),
                                 rows: [.init(title: "Distances unavailable",
                                              fields: [.init("reason", "no location is set, so the map cannot say which lines are near you")])],
                                 omitted: .init(shown: 0, total: lines.count, ranking: ContextRanking.nearestToYou))
        }

        let ranked = NearestLines.ranked(lines, observer: observer, limit: rowLimit)
        return ScreenContext(
            screen: screen, gate: .oneChart, situation: situationLine,
            schema: Glossary.entries(for: terms),
            rows: ranked.map { p in
                .init(title: "\(p.body.name) \(p.angle.abbreviation)",
                      fields: p.kilometres.map {
                          [.init("distance", "\(Int($0.rounded())) km \(p.isEast ? "east" : "west")")]
                      } ?? [.init("distance", "no line exists — circumpolar at this latitude")])
            },
            omitted: lines.count > ranked.count
                ? .init(shown: ranked.count, total: lines.count, ranking: ContextRanking.nearestToYou)
                : nil)
    }
}
