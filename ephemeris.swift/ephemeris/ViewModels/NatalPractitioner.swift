import Foundation
import SwiftUI
import EphemerisKit

/// What the practitioner facets need from an open chart.
///
/// Kept apart from `NatalViewModel` because the two answer different questions: that type owns the
/// *library* — which charts exist, which one is open, saving and deleting — while everything here
/// is derived from one chart and holds no state worth persisting. Folding these in would make the
/// library type grow a second job and force every list screen to carry the cost of computing
/// returns it will never show.
///
/// Everything is computed on demand rather than cached. The expensive ones (`returnCycles`,
/// `rangedSynastry`) are called once per facet appearance, not per frame, and a cache here would
/// have to be invalidated on chart edits, house-system changes and the scrubbed target date — three
/// chances to serve a stale chart, in exchange for work the profiler has not asked us to save.
@MainActor
struct ChartFacets {
    let chart: SavedChart

    // MARK: - Bi-wheel feeds
    //
    // Each case of `BiWheelSource` is only a different outer ring on the same natal wheel, which is
    // the whole reason four features share one control and one `MomentReadout`.

    /// Transiting bodies at `date` — the outer ring for `.transits`.
    func transitPositions(at date: Date = Date()) -> [BodyPosition] {
        CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: date),
                         speed: Ephemeris.dailyMotion(of: $0, at: date))
        }
    }

    /// Secondary progressions to `target` — the outer ring for `.progressed`.
    ///
    /// Angles come back nil when the birth time is unknown, and that is load-bearing: the
    /// day-for-a-year map turns a missing birth time into a missing *progressed* time, so a
    /// progressed Ascendant would be as invented as a natal one.
    func progressed(to target: Date) -> ProgressedChart {
        Progressions.secondary(birth: chart.birthInstant,
                               on: target,
                               location: chart.isTimeKnown ? chart.location : nil)
    }

    /// The chart cast for a return instant — the outer ring for `.chartReturn`.
    func returnPositions(for event: ReturnEvent) -> [BodyPosition] {
        CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: event.date),
                         speed: Ephemeris.dailyMotion(of: $0, at: event.date))
        }
    }

    // MARK: - Returns

    /// Solar and lunar returns around now, plus the Saturn return, newest-relevant first.
    ///
    /// The window is deliberately narrow — a year back and a year on — because a return list is a
    /// working document ("when is the next one"), not an ephemeris. `next` pins the row the user
    /// actually came for.
    func returnCycles(around date: Date = Date()) -> [ReturnEvent] {
        var events: [ReturnEvent] = []
        for body in [CelestialBody.sun, .moon] {
            guard let natal = chart.positions.first(where: { $0.body == body })?.longitude,
                  let next = Returns.next(body, to: natal, after: date)
            else { continue }
            events.append(next)
        }
        if let saturn = chart.positions.first(where: { $0.body == .saturn })?.longitude,
           let next = Returns.next(.saturn, to: saturn, after: date) {
            events.append(next)
        }
        return events.sorted { $0.date < $1.date }
    }

    /// Whether a date falls inside the span the ephemeris is *verified* across.
    ///
    /// A return outside it still exists and is still listed — the row is present and disabled,
    /// naming the window. Hiding it would answer "when is my next Saturn return" with silence,
    /// which reads as "there isn't one".
    func isWithinVerifiedWindow(_ date: Date) -> Bool {
        let year = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date).year ?? 0
        return NebulaPractitioner.ephemerisWindow.contains(year)
    }

    // MARK: - Analysis

    var analysis: ChartAnalysis { ChartAnalysis(positions: chart.positions) }

    /// Essential dignities, strongest first. Modern planets are absent rather than zeroed — the
    /// classical tables assign them nothing, and a zero would read as "measured and neutral".
    ///
    /// When the birth time is unknown and the Moon could have been in either of two signs, **both**
    /// scores are returned. Picking one would be a coin toss presented as a result.
    var dignities: [(score: DignityScore, alternative: DignityScore?)] {
        let sect = EssentialDignities.Sect.day   // sect needs an horizon; see `sectIsAssumed`
        return chart.positions.compactMap { position in
            guard let score = EssentialDignities.score(position.body,
                                                       longitude: position.longitude,
                                                       sect: sect) else { return nil }
            let candidates = chart.signCandidates(for: position.body)
            guard candidates.count > 1, let other = candidates.last else { return (score, nil) }
            // The alternative is scored at the first degree of the other candidate sign — the
            // dignity tables are sign-wide for domicile, exaltation, detriment and fall, so the
            // exact degree only shifts term and face.
            let alt = EssentialDignities.score(position.body,
                                               longitude: Double(other.rawValue) * 30 + 0.5,
                                               sect: sect)
            return (score, alt?.sign == score.sign ? nil : alt)
        }
        .sorted { $0.score.total > $1.score.total }
    }

    /// Sect is diurnal-vs-nocturnal and needs to know whether the Sun was above the horizon —
    /// which needs a birth time. With none, the day tables are used and the UI must say so.
    var sectIsAssumed: Bool { !chart.isTimeKnown }

    /// Midpoints between pairs, personal planets first.
    ///
    /// Ambiguous pairs — bodies exactly opposite, where the midpoint is undefined between two
    /// equally valid points — are kept and flagged rather than dropped, because a silently missing
    /// row is indistinguishable from a pair that has no midpoint at all.
    struct MidpointPair: Identifiable, Hashable {
        let a: CelestialBody
        let b: CelestialBody
        let longitude: Double
        let opposite: Double
        let isAmbiguous: Bool
        var id: String { "\(a.rawValue)-\(b.rawValue)" }
    }

    private static let personal: Set<CelestialBody> = [.sun, .moon, .mercury, .venus, .mars]

    func midpoints(personalOnly: Bool = true) -> [MidpointPair] {
        let ps = chart.positions
        var out: [MidpointPair] = []
        for i in ps.indices {
            for j in ps.indices where j > i {
                let a = ps[i], b = ps[j]
                if personalOnly && !(Self.personal.contains(a.body) && Self.personal.contains(b.body)) {
                    continue
                }
                out.append(MidpointPair(
                    a: a.body, b: b.body,
                    longitude: Midpoints.midpoint(a.longitude, b.longitude),
                    opposite: Midpoints.oppositeMidpoint(a.longitude, b.longitude),
                    isAmbiguous: Midpoints.isAmbiguous(a.longitude, b.longitude)))
            }
        }
        return out
    }
}
