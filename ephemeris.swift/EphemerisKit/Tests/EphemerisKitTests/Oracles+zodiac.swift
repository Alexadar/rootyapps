import Foundation
import EphemerisKit

/// External ground truth for the sidereal frame.
///
/// This is one of the few esoteric-adjacent functions with a genuine published authority behind it,
/// but the citations need care and the `source` strings below say exactly what each value is:
///
/// - **Fagan–Bradley at 1950.0 is a definition**, not a measurement. 24°02′31.36″ is the number the
///   system is defined by, so its tolerance guards transcription, not accuracy.
/// - **Lahiri at J2000.0** is the ICRC-standardised 23.853222°, corroborated independently by the
///   Swiss Ephemeris table below (23°51′12″ — the same value to the arcsecond).
/// - **The multi-epoch Lahiri values are computed by Swiss Ephemeris**, not transcribed from the
///   Government of India's printed table. Swiss Ephemeris is the field's reference implementation
///   and a legitimate outside authority, but it is a secondary source and this file says so rather
///   than implying a government publication.
/// - **Krishnamurti and Raman are specified as offsets from Lahiri** in ordinary practice, so that
///   relation is what is oracled. Asserting a documented relation beats inventing absolute values
///   nobody publishes.
///
/// The tolerance on the epoch series is **measurement-derived**: the Meeus general-precession model
/// tracks the published table to a worst 31.3″ across 1900–2050, so the tolerance is 47″ (that plus
/// ~50%). It is deliberately far tighter than the 1.388° error a hardcoded present-day constant
/// would produce at 1900 — which is the failure this series exists to catch.
enum zodiacOracles {

    private static let swissTable =
        "Lahiri (Chitra-paksha, true, including nutation) computed with Swiss Ephemeris and " +
        "rounded to the arcsecond, at 00:00 UT on 1 January of each year — secondary source, " +
        "published at jagannathhora.com/historical-lahiri-ayanamsa-values-tables/ (retrieved 2026-08-17)"
    private static let icrc =
        "International Convention on Rectification and Correction — standardised Lahiri ayanamsa " +
        "at JD 2451545.0 (J2000.0) = 23.853222°; agrees to the arcsecond with the Swiss Ephemeris " +
        "table entry of 23°51′12″"
    private static let fagan =
        "Fagan–Bradley definition: ayanamsa = 24°02′31.36″ at 1950 January 1.0, with Spica at " +
        "29°06′05″ Virgo — a defining constant, not a measurement"
    private static let meeus21 =
        "Meeus, Astronomical Algorithms (2nd ed.), ch. 21 — general precession in longitude, " +
        "p_A = 5029.0966″T + 1.11113″T² − 0.000006″T³"

    /// 47″ in degrees — measured worst residual 31.3″ plus ~50%.
    private static let epochTol = 47.0 / 3600.0

    static let all: [Oracle] = [

        // ── Lahiri across a century and a half ───────────────────────────────────────
        // Five separated epochs, because a single-epoch check cannot catch a wrong precession
        // RATE — and the rate is the only thing here that is hard to get right.
        Oracle(
            id: "ayanamsa-lahiri-epochs",
            source: swissTable + "; anchored at J2000 by " + icrc,
            inputs: "Lahiri ayanamsa at 00:00 UT on 1 Jan of 1900, 1950, 2000, 2025 and 2050",
            precision: "±47″ (0.01305°) — measured worst residual of the Meeus ch.21 precession " +
                       "model against this table is 31.3″ at 1900, plus ~50% margin. Tighter than " +
                       "this would fail on the published table's own nutation content; looser " +
                       "would stop catching a wrong rate",
            values: [
                "1900": 22.0 + 27.0/60 + 55.0/3600,
                "1950": 23.0 +  9.0/60 + 28.0/3600,
                "2000": 23.0 + 51.0/60 + 12.0/3600,
                "2025": 24.0 + 12.0/60 + 23.0/3600,
                "2050": 24.0 + 33.0/60 + 35.0/3600,
            ],
            tolerances: ["1900": epochTol, "1950": epochTol, "2000": epochTol,
                         "2025": epochTol, "2050": epochTol]
        ),

        // ── The rate itself, stated separately ───────────────────────────────────────
        // The series above would still pass if the model were wrong in a way that happened to
        // cancel at those five dates. This pins the derivative directly.
        Oracle(
            id: "ayanamsa-precession-rate",
            source: meeus21 + "; the published table's own 1900→2000 span gives 4997″/century",
            inputs: "mean growth of the Lahiri ayanamsa per year, arcseconds, over 1900–2000",
            precision: "±0.5″/yr — general precession is ~50.29″/yr at this epoch and the value " +
                       "must be recovered from the model, not assumed",
            values: ["arcsecPerYear": 49.97],
            tolerances: ["arcsecPerYear": 0.5]
        ),

        // ── Fagan–Bradley: exact by definition ───────────────────────────────────────
        Oracle(
            id: "ayanamsa-fagan-bradley-1950",
            source: fagan,
            inputs: "Fagan–Bradley ayanamsa at 1950 January 1.0 UT",
            precision: "±1″ — a defining constant; the tolerance guards transcription and the " +
                       "epoch conversion, not the underlying quantity",
            values: ["degrees": 24.0 + 2.0/60 + 31.36/3600],
            tolerances: ["degrees": 1.0/3600]
        ),

        // ── The systems must disagree, by the documented amounts ─────────────────────
        // Copy-pasting one system's implementation into another is a real and easy mistake; it
        // passes every single-system test above. These differences are what catch it.
        Oracle(
            id: "ayanamsa-system-differences",
            source: "Krishnamurti (KP) runs ~6′ above Lahiri in the modern era; Raman runs ~1°27′ " +
                    "below it (Raman ≈ 22.78° vs Lahiri ≈ 24.22° in 2026). Fagan–Bradley sits " +
                    "~0°53′ above Lahiri, following from the two systems' own definitions",
            inputs: "ayanamsa(system) − ayanamsa(Lahiri) in 2026, degrees",
            precision: "±0.1° on the KP and Fagan–Bradley gaps and ±0.15° on Raman — the sources " +
                       "quote these to the arcminute at best, and the gaps drift slowly",
            values: ["krishnamurti": 0.10, "raman": -1.45, "faganBradley": 0.88],
            tolerances: ["krishnamurti": 0.10, "raman": 0.15, "faganBradley": 0.10]
        ),
    ]
}
