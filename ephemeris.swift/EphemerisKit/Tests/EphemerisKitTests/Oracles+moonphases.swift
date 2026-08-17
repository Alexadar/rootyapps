import Foundation
import EphemerisKit

/// External ground truth for the Moon's phases.
///
/// This is the strongest oracle of the three new functions, because somebody else genuinely
/// publishes the answer: Fred Espenak's phase catalogue gives every principal phase to the minute
/// in Universal Time, for six millennia.
///
/// ## Values are seconds-since-epoch, and why
///
/// An `Oracle` carries `[String: Double]`, so each phase instant is stored as a Unix timestamp and
/// the tolerance is in **seconds**. Less readable than a date string, but it keeps these entries in
/// the same shape as every other oracle in the corpus and lets `matches` do the comparison
/// unchanged. The key names carry the human-readable date so an auditor can check the transcription
/// against the printed page without decoding a number.
///
/// ## A transcription warning worth keeping
///
/// These were first transcribed from a *summarised* reading of the source page and two of the
/// quarter columns came back mis-associated — a Last Quarter attributed to a date 24 days after its
/// own New Moon, which is arithmetically impossible for a 29.53-day month. Measured against those
/// bad values the engine looked 2,961 minutes wrong, and the "measured" tolerance would have been
/// **4,442 minutes** — loose enough to hide anything at all.
///
/// The values below are transcribed from the raw four-column rows instead. The lesson generalises:
/// when a measured error is implausibly large, suspect the transcription before widening the
/// tolerance, and never let a tolerance be set by data you have not verified.
enum moonPhaseOracles {

    private static let espenak =
        "Fred Espenak (NASA/GSFC, ret.), Six Millennium Catalog of Phases of the Moon, " +
        "astropixels.com/ephemeris/phasescat/ — Universal Time, to the minute; transcribed from " +
        "the raw four-column year rows (retrieved 2026-08-17)"

    /// 14 minutes, in seconds. Measured worst error is 9.1 min across 48 phases spanning 2010–2035;
    /// this is that plus ~50%. The bound is dominated by the Moon's own position accuracy — the
    /// engine's lunar longitude is good to ~6′ worst-case, and the Moon covers 6′ in about eleven
    /// minutes, so a materially tighter tolerance here would be asserting precision the position
    /// series does not have.
    private static let tol = 14.0 * 60

    private static func ts(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Double {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!.timeIntervalSince1970
    }

    static let all: [Oracle] = [

        // ── New and full moons, 2010 · 2020 · 2026 · 2035 ────────────────────────────
        Oracle(
            id: "moonphase-espenak-syzygies",
            source: espenak,
            inputs: "New and Full Moon instants, three lunations each in 2010, 2020, 2026 and 2035",
            precision: "±14 min (840 s) — measured worst 9.1 min over 48 published phases, +50%",
            values: [
                "2010-01-15-new":  ts(2010, 1, 15,  7, 11),
                "2010-01-30-full": ts(2010, 1, 30,  6, 18),
                "2010-02-14-new":  ts(2010, 2, 14,  2, 51),
                "2010-02-28-full": ts(2010, 2, 28, 16, 38),
                "2010-03-15-new":  ts(2010, 3, 15, 21,  1),
                "2010-03-30-full": ts(2010, 3, 30,  2, 25),
                "2020-01-24-new":  ts(2020, 1, 24, 21, 42),
                "2020-02-09-full": ts(2020, 2,  9,  7, 33),
                "2020-02-23-new":  ts(2020, 2, 23, 15, 32),
                "2020-03-09-full": ts(2020, 3,  9, 17, 48),
                "2020-03-24-new":  ts(2020, 3, 24,  9, 28),
                "2020-04-08-full": ts(2020, 4,  8,  2, 35),
                "2026-01-18-new":  ts(2026, 1, 18, 19, 52),
                "2026-02-01-full": ts(2026, 2,  1, 22,  9),
                "2026-02-17-new":  ts(2026, 2, 17, 12,  1),
                "2026-03-03-full": ts(2026, 3,  3, 11, 38),
                "2026-03-19-new":  ts(2026, 3, 19,  1, 23),
                "2026-04-02-full": ts(2026, 4,  2,  2, 12),
                "2035-01-09-new":  ts(2035, 1,  9, 15,  3),
                "2035-01-23-full": ts(2035, 1, 23, 20, 17),
                "2035-02-08-new":  ts(2035, 2,  8,  8, 22),
                "2035-02-22-full": ts(2035, 2, 22,  8, 54),
                "2035-03-09-new":  ts(2035, 3,  9, 23,  9),
                "2035-03-23-full": ts(2035, 3, 23, 22, 42),
            ],
            tolerances: Dictionary(uniqueKeysWithValues: [
                "2010-01-15-new", "2010-01-30-full", "2010-02-14-new", "2010-02-28-full",
                "2010-03-15-new", "2010-03-30-full", "2020-01-24-new", "2020-02-09-full",
                "2020-02-23-new", "2020-03-09-full", "2020-03-24-new", "2020-04-08-full",
                "2026-01-18-new", "2026-02-01-full", "2026-02-17-new", "2026-03-03-full",
                "2026-03-19-new", "2026-04-02-full", "2035-01-09-new", "2035-01-23-full",
                "2035-02-08-new", "2035-02-22-full", "2035-03-09-new", "2035-03-23-full",
            ].map { ($0, tol) })
        ),

        // ── The quarters ─────────────────────────────────────────────────────────────
        // Their own entry, because they are the phases a mean-phase implementation gets *least*
        // wrong-looking: halfway between two syzygies, an interpolation is at its most plausible.
        Oracle(
            id: "moonphase-espenak-quarters",
            source: espenak,
            inputs: "First and Last Quarter instants, three lunations each in 2010, 2020, 2026 and 2035",
            precision: "±14 min (840 s) — same measured bound as the syzygies; worst observed " +
                       "error in the whole 48-sample set was a First Quarter at 9.1 min",
            values: [
                "2010-01-23-fq": ts(2010, 1, 23, 10, 53),
                "2010-02-05-lq": ts(2010, 2,  5, 23, 49),
                "2010-02-22-fq": ts(2010, 2, 22,  0, 42),
                "2010-03-07-lq": ts(2010, 3,  7, 15, 42),
                "2010-03-23-fq": ts(2010, 3, 23, 11,  0),
                "2010-04-06-lq": ts(2010, 4,  6,  9, 37),
                "2020-02-02-fq": ts(2020, 2,  2,  1, 42),
                "2020-02-15-lq": ts(2020, 2, 15, 22, 17),
                "2020-03-02-fq": ts(2020, 3,  2, 19, 57),
                "2020-03-16-lq": ts(2020, 3, 16,  9, 34),
                "2020-04-01-fq": ts(2020, 4,  1, 10, 21),
                "2020-04-14-lq": ts(2020, 4, 14, 22, 56),
                "2026-01-26-fq": ts(2026, 1, 26,  4, 48),
                "2026-02-09-lq": ts(2026, 2,  9, 12, 43),
                "2026-02-24-fq": ts(2026, 2, 24, 12, 28),
                "2026-03-11-lq": ts(2026, 3, 11,  9, 39),
                "2026-03-25-fq": ts(2026, 3, 25, 19, 18),
                "2026-04-10-lq": ts(2026, 4, 10,  4, 52),
                "2035-01-17-fq": ts(2035, 1, 17,  4, 45),
                "2035-01-31-lq": ts(2035, 1, 31,  6,  3),
                "2035-02-15-fq": ts(2035, 2, 15, 13, 17),
                "2035-03-02-lq": ts(2035, 3,  2,  3,  1),
                "2035-03-16-fq": ts(2035, 3, 16, 20, 15),
                "2035-03-31-lq": ts(2035, 3, 31, 23,  7),
            ],
            tolerances: Dictionary(uniqueKeysWithValues: [
                "2010-01-23-fq", "2010-02-05-lq", "2010-02-22-fq", "2010-03-07-lq",
                "2010-03-23-fq", "2010-04-06-lq", "2020-02-02-fq", "2020-02-15-lq",
                "2020-03-02-fq", "2020-03-16-lq", "2020-04-01-fq", "2020-04-14-lq",
                "2026-01-26-fq", "2026-02-09-lq", "2026-02-24-fq", "2026-03-11-lq",
                "2026-03-25-fq", "2026-04-10-lq", "2035-01-17-fq", "2035-01-31-lq",
                "2035-02-15-fq", "2035-03-02-lq", "2035-03-16-fq", "2035-03-31-lq",
            ].map { ($0, tol) })
        ),

        // ── The synodic month ────────────────────────────────────────────────────────
        Oracle(
            id: "moonphase-synodic-month",
            source: "Meeus, Astronomical Algorithms (2nd ed.), ch. 49 — mean synodic month " +
                    "29.530588 days at the present epoch",
            inputs: "mean interval between consecutive New Moons, days",
            precision: "±0.35 d on the mean of a year's lunations — the TRUE interval swings " +
                       "roughly ±0.25 d either side of the mean with the Moon's anomaly, so a " +
                       "tolerance tighter than that would fail on correct output",
            values: ["days": 29.530588],
            tolerances: ["days": 0.35]
        ),
    ]
}
