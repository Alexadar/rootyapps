import Foundation
import EphemerisKit

/// Ground truth for the void-of-course Moon.
///
/// ## This one is mostly construction, and the reason is worth recording
///
/// Void-of-course has **competing definitions**, and the disagreement is not a detail:
///
/// - which bodies count (Lilly's seven, or the seven plus Uranus/Neptune/Pluto)
/// - whether "applies to" means *perfects* or *comes within moiety of orbs*
///
/// Two correct implementations can differ by hours. That makes a published table a weak oracle
/// unless it states its method — and the one used here **does not**. moontracks.com says only that
/// it uses "the last Ptolemy aspect", naming the five aspects but never the bodies. So it cannot
/// settle the traditional-vs-modern question, and pretending otherwise would be worse than having
/// no external anchor at all.
///
/// What it *can* do is check the arithmetic: both transcribed periods have their last aspect to a
/// classical planet, where the two definitions agree, so agreement there tests the search and the
/// ingress solve without depending on the definitional choice. Measured against those rows the
/// worst error is **4 minutes**, and both the aspect type and the aspected body match exactly.
///
/// ⚠️ **Four values is a thin sample** — two periods, each with a start and an end. It is recorded
/// as an external anchor rather than a proof, and the identities in `VoidOfCourseTests` are what
/// actually pin the behaviour. Stated here so nobody later reads this file as stronger than it is.
enum voidOfCourseOracles {

    private static let moontracks =
        "moontracks.com void-of-course tables, times in UT to the minute (retrieved 2026-08-17). " +
        "SECONDARY and METHOD-INCOMPLETE: the page states it uses the last Ptolemaic aspect and " +
        "lists the five aspects, but never states which bodies it counts, so it cannot arbitrate " +
        "between the traditional and modern body sets. Both rows below aspect a classical planet, " +
        "where the two definitions agree"

    private static let lilly =
        "William Lilly, Christian Astrology (1647), 'Considerations before Judgement': \"A planet " +
        "is void of course, when he is separated from a planet, nor doth forthwith, during his " +
        "being in that sign, apply to any other.\" — the definition, not a table of values"

    /// 6 minutes, in seconds. Measured worst error is 4.0 min across the four transcribed instants;
    /// this is that plus 50%. The bound is dominated by the lunar position series: the Moon covers
    /// its own ~6′ worst-case error in about eleven minutes, so a materially tighter tolerance here
    /// would be asserting timing precision the underlying longitude does not have.
    private static let tol = 6.0 * 60

    private static func ts(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Double {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!.timeIntervalSince1970
    }

    static let all: [Oracle] = [

        // ── The two published periods ────────────────────────────────────────────────
        Oracle(
            id: "voc-moontracks-periods",
            source: moontracks,
            inputs: "void-of-course start (last exact aspect) and end (sign ingress), UT, " +
                    "September 2026; last aspects are Moon opposite Mercury and Moon square Jupiter",
            precision: "±6 min (360 s) — measured worst 4.0 min over the four instants, +50%",
            values: [
                "2026-09-28-start": ts(2026, 9, 28,  9, 50),   // Moon opp Mercury, in Aries
                "2026-09-28-end":   ts(2026, 9, 28, 14, 40),   // enters Taurus
                "2026-09-29-start": ts(2026, 9, 29, 23, 36),   // Moon square Jupiter, in Taurus
                "2026-09-30-end":   ts(2026, 9, 30, 17, 26),   // enters Gemini
            ],
            tolerances: ["2026-09-28-start": tol, "2026-09-28-end": tol,
                         "2026-09-29-start": tol, "2026-09-30-end": tol]
        ),

        // ── The definition, as an identity rather than a number ──────────────────────
        // Lilly gives no table, so what is citable is the SHAPE: a void runs from the last aspect
        // to the sign boundary, and holds no exact aspect in between. That identity cannot be
        // satisfied by a wrong search, which is what makes it worth as much as the rows above.
        Oracle(
            id: "voc-lilly-definition",
            source: lilly,
            inputs: "structural constants of the definition: aspects counted, bodies in the " +
                    "traditional set, and the count of principal aspects",
            precision: "±0.5 — integer counts, guarding transcription rather than accuracy",
            values: [
                "ptolemaicAspects": 5,      // conjunction, sextile, square, trine, opposition
                "traditionalBodies": 6,     // Lilly's seven, less the Moon itself
                "modernBodies": 9,          // plus Uranus, Neptune, Pluto
            ],
            tolerances: ["ptolemaicAspects": 0.5, "traditionalBodies": 0.5, "modernBodies": 0.5]
        ),

        // ── How often it happens ─────────────────────────────────────────────────────
        // The Moon changes sign every ~2.3 days, and each occupancy ends in exactly one void, so a
        // lunar month holds twelve or thirteen. A search that missed aspects would produce longer,
        // fewer periods; one that invented them would produce more.
        Oracle(
            id: "voc-frequency",
            source: "Geometry of the definition: the Moon completes the zodiac in one tropical " +
                    "month (27.32 d), so it makes twelve or thirteen sign ingresses per month and " +
                    "each occupancy contributes exactly one void period",
            inputs: "void periods per 27.32-day tropical month",
            precision: "±1.5 — twelve or thirteen depending on where the month is cut",
            values: ["perMonth": 12.5],
            tolerances: ["perMonth": 1.5]
        ),
    ]
}
