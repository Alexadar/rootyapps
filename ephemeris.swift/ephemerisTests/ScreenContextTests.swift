import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// What the assistant is allowed to know about a screen.
///
/// Every builder here is a pure function, which is the point: the model needs eligible hardware and
/// cannot run in a test, but **the part that can be wrong** — what gets sent, what gets dropped, and
/// whether the dropping is disclosed — is all pure and checked here.
///
/// The load-bearing assertions are the honesty ones. A context that quietly shows four of a hundred
/// and four rows produces a confident, wrong answer about "what's coming up", and nothing in the
/// output looks incorrect.
@Suite("Screen context")
@MainActor
struct ScreenContextTests {

    private static let kyiv = GeoLocation(latitude: 50.45, longitude: 30.52, name: "Kyiv")
    private let zone = TimeZone(identifier: "Europe/Kyiv")!

    private func moment(at date: Date) -> SkyMoment {
        let positions = CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: date),
                         speed: Ephemeris.dailyMotion(of: $0, at: date))
        }
        return SkyMoment(positions: positions,
                         aspects: Aspects.detect(in: positions, orbFactor: 1.0),
                         houses: Houses.compute(at: date, location: Self.kyiv, system: .placidus),
                         houseFallback: nil, outerPositions: nil, crossAspects: [])
    }

    private func chart(_ name: String = "Ada", timeKnown: Bool = true) -> SavedChart {
        SavedChart(name: name, birthInstant: utc(1990, 6, 15, 12, 0),
                   timeZoneID: "Europe/London", isTimeKnown: timeKnown,
                   latitude: 51.5, longitude: -0.13, placeName: "London")
    }

    // MARK: - Every screen answers

    /// A surface with no context provider is a screen the assistant silently cannot explain, and the
    /// user gets a shrug on exactly the page they were confused by.
    @Test func everySurfaceProducesAContext() {
        let now = utc(2026, 8, 18, 18, 0)
        let m = moment(at: now)
        let c = chart()

        var contexts: [ScreenContext] = MomentLens.allCases.map {
            ScreenContexts.sky(lens: $0, moment: m, date: now, timeZone: zone,
                               location: Self.kyiv, zodiac: nil, houseSystem: .placidus,
                               charts: 0, rowLimit: 4)
        }
        contexts.append(ScreenContexts.moonCalendar(month: now, now: now, timeZone: zone,
                                                    location: Self.kyiv, charts: 0, rowLimit: 4))
        contexts.append(ScreenContexts.hours(now: now, timeZone: zone, location: Self.kyiv,
                                             charts: 0, rowLimit: 4))
        contexts.append(ScreenContexts.timeline(
            events: EventTimeline.allEvents(in: DateInterval(start: now, duration: 60 * 86_400)),
            window: DateInterval(start: now, duration: 60 * 86_400), now: now,
            timeZone: zone, location: Self.kyiv, charts: 0, rowLimit: 4))
        contexts.append(ScreenContexts.natalChart(c, positions: c.positions,
                                                  aspects: c.aspects, rowLimit: 4))
        contexts.append(ScreenContexts.astrocartography(
            c, lines: AstroCartography.lines(at: c.birthInstant),
            observer: Self.kyiv, rowLimit: 4))

        #expect(contexts.count >= 9, "expected a context per surface, got \(contexts.count)")
        for ctx in contexts {
            #expect(!ctx.screen.id.isEmpty && !ctx.screen.title.isEmpty, "\(ctx.screen) is unnamed")
            #expect(!ctx.situation.isEmpty, "\(ctx.screen.id) says nothing about where we are")
            #expect(!ctx.rows.isEmpty, "\(ctx.screen.id) sent no data at all")
            #expect(!ctx.schema.isEmpty, "\(ctx.screen.id) sent no vocabulary")
        }
        // Ids must be unique, or two screens answer as each other.
        let ids = contexts.map(\.screen.id)
        #expect(Set(ids).count == ids.count, "duplicate screen ids: \(ids)")
    }

    // MARK: - The glossary covers what the screens name

    /// ⚠️ A term a screen names with no glossary entry hands the model a heading and no meaning,
    /// which is precisely when it invents one.
    ///
    /// Checked against the **declared vocabulary**, not against the resulting schema. The earlier
    /// version of this test walked `ctx.schema` and was vacuous: `Glossary.entries(for:)` drops
    /// what it cannot find, so an unknown term never reached the schema to be caught. Naming a
    /// nonexistent term left it green — verified by doing exactly that.
    @Test func everyTermAScreenDeclaresIsInTheGlossary() {
        #expect(!ScreenContexts.vocabulary.isEmpty)
        for (screen, terms) in ScreenContexts.vocabulary {
            let missing = Glossary.unknown(in: terms)
            #expect(missing.isEmpty, "\(screen) names \(missing) with no glossary meaning")
            for term in terms {
                let meaning = Glossary.meaning(of: term) ?? ""
                #expect(meaning.count > 30, "'\(term)' has a meaning too short to explain anything")
            }
        }
    }

    /// And the declared vocabulary is what actually gets sent — a list nobody reads would drift.
    @Test func theDeclaredVocabularyIsWhatReachesThePrompt() {
        let now = utc(2026, 8, 18, 18, 0)
        let ctx = ScreenContexts.sky(lens: .aspects, moment: moment(at: now), date: now,
                                     timeZone: zone, location: Self.kyiv, zodiac: nil,
                                     houseSystem: .placidus, charts: 0, rowLimit: 4)
        let declared = Set(ScreenContexts.vocabulary(for: "sky.aspects"))
        #expect(Set(ctx.schema.map(\.term)) == declared,
                "the aspects screen sent \(ctx.schema.map(\.term)) but declares \(declared)")
    }

    @Test func theGlossaryHasNoDuplicateTerms() {
        let terms = Glossary.allTerms
        #expect(Set(terms).count == terms.count, "duplicate glossary terms")
        #expect(terms.count > 40, "only \(terms.count) terms — the vocabulary is thin")
    }

    // MARK: - Truncation is ranked and disclosed

    /// The timeline is the worst case: 104 events in the shipped window, four of which survive.
    @Test func theTimelineDisclosesWhatItDropped() {
        let now = utc(2026, 8, 18, 12, 0)
        let window = DateInterval(start: now.addingTimeInterval(-30 * 86_400),
                                  end: now.addingTimeInterval(120 * 86_400))
        let events = EventTimeline.allEvents(in: window)
        #expect(events.count > 20, "expected a busy window, got \(events.count)")

        let ctx = ScreenContexts.timeline(events: events, window: window, now: now,
                                          timeZone: zone, location: Self.kyiv,
                                          charts: 0, rowLimit: 4)
        #expect(ctx.rows.count == 4)
        guard let omitted = ctx.omitted else {
            Issue.record("dropped \(events.count - 4) events and said nothing"); return
        }
        #expect(omitted.total == events.count)
        #expect(omitted.shown == 4)
        #expect(omitted.hidden == events.count - 4)
        // The prompt must carry it, not just the struct.
        #expect(ctx.promptText.contains("\(events.count)"), "the prompt hides the true total")
        #expect(ctx.promptText.lowercased().contains("not shown"),
                "the prompt does not tell the model that rows were withheld")
    }

    /// ⚠️ Ranked, not the first four. The window opens thirty days in the past, so head-truncation
    /// would hand the model a month of history and drop today entirely.
    @Test func theTimelineKeepsTheEventsNearestNowNotTheFirstFour() {
        let now = utc(2026, 8, 18, 12, 0)
        let window = DateInterval(start: now.addingTimeInterval(-30 * 86_400),
                                  end: now.addingTimeInterval(120 * 86_400))
        let events = EventTimeline.allEvents(in: window)
        let ctx = ScreenContexts.timeline(events: events, window: window, now: now,
                                          timeZone: zone, location: Self.kyiv,
                                          charts: 0, rowLimit: 4)

        // Every kept event must be nearer to now than the earliest event in the window.
        let sorted = events.sorted { $0.date < $1.date }
        guard let earliest = sorted.first else { Issue.record("no events"); return }
        let earliestGap = abs(earliest.date.timeIntervalSince(now))

        for row in ctx.rows {
            guard let match = events.first(where: { $0.label() == row.title }) else { continue }
            let gap = abs(match.date.timeIntervalSince(now))
            #expect(gap < earliestGap,
                    "'\(row.title)' is \(Int(gap / 86_400)) d away — further than the window's first event")
        }
    }

    @Test func aspectsAreRankedByTightestOrb() {
        let now = utc(2026, 8, 18, 12, 0)
        let m = moment(at: now)
        let ctx = ScreenContexts.sky(lens: .aspects, moment: m, date: now, timeZone: zone,
                                     location: Self.kyiv, zodiac: nil, houseSystem: .placidus,
                                     charts: 0, rowLimit: 4)
        guard m.aspects.count > 4 else { return }
        let tightest = m.aspects.map { abs($0.orb) }.sorted().prefix(4)
        let shown = ctx.rows.compactMap { row -> Double? in
            row.fields.first { $0.name == "orb" }
                .flatMap { Double($0.value.replacingOccurrences(of: "°", with: "")) }
        }
        #expect(shown.count == 4)
        for orb in shown {
            #expect(orb <= (tightest.last ?? 0) + 0.01,
                    "an aspect with orb \(orb)° was kept over a tighter one")
        }
    }

    /// Nothing is dropped when everything fits, and the prompt then says "all" rather than implying
    /// a cut that did not happen.
    @Test func nothingIsClaimedOmittedWhenEverythingFits() {
        let now = utc(2026, 8, 18, 12, 0)
        let ctx = ScreenContexts.sky(lens: .wheel, moment: moment(at: now), date: now,
                                     timeZone: zone, location: Self.kyiv, zodiac: nil,
                                     houseSystem: .placidus, charts: 0, rowLimit: 99)
        #expect(ctx.omitted == nil)
        #expect(ctx.promptText.contains("all "), "a complete context should say so")
    }

    // MARK: - The gate

    /// The model must not offer a chart reading to someone who has entered nothing.
    @Test func theGateReflectsWhatTheUserActuallyHas() {
        let now = utc(2026, 8, 18, 12, 0)
        let m = moment(at: now)

        let empty = ScreenContexts.sky(lens: .wheel, moment: m, date: now, timeZone: zone,
                                       location: nil, zodiac: nil, houseSystem: .placidus,
                                       charts: 0, rowLimit: 4)
        #expect(empty.gate == .nothing)
        #expect(empty.promptText.contains("entered nothing"))

        let placed = ScreenContexts.sky(lens: .wheel, moment: m, date: now, timeZone: zone,
                                        location: Self.kyiv, zodiac: nil, houseSystem: .placidus,
                                        charts: 0, rowLimit: 4)
        #expect(placed.gate == .place)

        let withChart = ScreenContexts.sky(lens: .wheel, moment: m, date: now, timeZone: zone,
                                           location: Self.kyiv, zodiac: nil, houseSystem: .placidus,
                                           charts: 1, rowLimit: 4)
        #expect(withChart.gate == .oneChart)
    }

    // MARK: - Honest absences reach the model

    /// The two reasons there are no planetary hours are different, and only one is fixable by the
    /// user. Telling a model in Los Angeles that the Sun did not rise would make it explain the
    /// Arctic to someone in California.
    @Test func theHoursScreenExplainsWhichAbsenceItIs() {
        let la = GeoLocation(latitude: 34.05, longitude: -118.24, name: "Los Angeles")
        let day = utc(2026, 8, 18, 12, 0)

        let mismatch = ScreenContexts.hours(now: day, timeZone: zone, location: la,
                                            charts: 0, rowLimit: 4)
        #expect(mismatch.promptText.lowercased().contains("time zone"),
                "a zone mismatch must be named as one")

        let polar = ScreenContexts.hours(now: utc(2026, 6, 21, 12, 0),
                                         timeZone: TimeZone(secondsFromGMT: 0)!,
                                         location: GeoLocation(latitude: 78.22, longitude: 15.63),
                                         charts: 0, rowLimit: 4)
        #expect(polar.promptText.lowercased().contains("does not rise"),
                "a polar day must be named as one")
    }

    /// An unknown birth time removes the houses and the Ascendant. If the model is not told, it will
    /// discuss a rising sign that does not exist.
    @Test func anUntimedChartSaysWhatIsUndefined() {
        let c = chart("Sam", timeKnown: false)
        let ctx = ScreenContexts.natalChart(c, positions: c.positions, aspects: c.aspects,
                                            rowLimit: 4)

        // Asserted on the ROW, not on the prompt text. Matching "undefined" anywhere was vacuous:
        // the glossary's own "unknown birth time" entry contains that word, so deleting the row
        // left the test green — verified by deleting it.
        let notice = ctx.rows.first { $0.title.lowercased().contains("birth time unknown") }
        #expect(notice != nil, "an untimed chart must state what it cannot show, as a row")
        #expect(notice?.fields.contains { $0.value.contains("Ascendant") } == true,
                "the notice must name what is undefined, not merely say something is")
        #expect(ctx.schema.contains { $0.term == "unknown birth time" })

        // And a timed chart must NOT carry it, or the notice is decoration.
        let timed = chart("Ada", timeKnown: true)
        let ok = ScreenContexts.natalChart(timed, positions: timed.positions,
                                           aspects: timed.aspects, rowLimit: 4)
        #expect(!ok.rows.contains { $0.title.lowercased().contains("birth time unknown") })
    }

    /// A circumpolar line does not exist anywhere, and "no line" must reach the model as a stated
    /// absence rather than a missing row.
    @Test func circumpolarLinesReachTheModelAsAbsences() {
        let c = chart()
        let polarBand = LatitudeBand(south: 80, north: 89, step: 1)
        let lines = AstroCartography.lines(at: c.birthInstant,
                                           bodies: CelestialBody.allCases,
                                           angles: [.ascendant, .descendant], band: polarBand)
        guard lines.contains(where: \.isEmpty) else {
            Issue.record("expected circumpolar lines in an 80–89° band"); return
        }
        let ctx = ScreenContexts.astrocartography(c, lines: lines, observer: Self.kyiv, rowLimit: 8)
        #expect(ctx.promptText.lowercased().contains("circumpolar"),
                "an absent line must be explained, not silently dropped")
    }
}
