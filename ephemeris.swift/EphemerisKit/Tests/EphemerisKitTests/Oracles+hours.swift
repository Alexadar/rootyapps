import Foundation
import EphemerisKit

// MARK: - Encoding
// Oracle values are Doubles, so planets are carried as indices into `CelestialBody.allCases`.
// The helper is a codec ONLY — it lets each entry be written with the planet's name so a human can
// audit the transcription against the printed source instead of against a column of integers.

private func p(_ b: CelestialBody) -> Double {
    Double(CelestialBody.allCases.firstIndex(of: b)!)
}

/// ±0.5 on an integer-valued entry: any wrong planet is a miss and no rounding can mask one.
private let exact = 0.5

private let valens =
    "Vettius Valens, Anthologies I.10 (Riley trans.) — the planetary hours and their Chaldean " +
    "sequence; the same order Ptolemy gives for the planetary week in Tetrabiblos II.10"
private let geometry =
    "Spherical astronomy: at declination 0° and latitude 0° the hour angle of the geometric " +
    "horizon is exactly 90°, so day and night are each exactly 12 equinoctial hours"

/// External ground truth for the planetary hours.
///
/// This function is mostly a **construction** oracle — no authority publishes hour tables for
/// arbitrary places, because every source derives them the same way from sunrise and sunset. What
/// *is* external is the classical assignment (which planet rules which weekday, and in what order
/// the hours advance) and one number that comes from spherical geometry rather than from us.
enum hoursOracles {
    static let all: [Oracle] = [

        // ── The Chaldean order ───────────────────────────────────────────────────────
        Oracle(
            id: "hours-chaldean-order",
            source: valens,
            inputs: "position 0…6 in the hour-ruler cycle → the ruling planet",
            precision: "±0.5 on a planet index — the value is an identity, not a measurement",
            values: [
                "0": p(.saturn), "1": p(.jupiter), "2": p(.mars), "3": p(.sun),
                "4": p(.venus), "5": p(.mercury), "6": p(.moon),
            ],
            tolerances: ["0": exact, "1": exact, "2": exact, "3": exact,
                         "4": exact, "5": exact, "6": exact]
        ),

        // ── The weekday rulers ───────────────────────────────────────────────────────
        // Transcribed independently of the cycle above, precisely so the test can prove the two
        // agree. If the weekday table were derived from the cycle in the implementation AND in the
        // oracle, their agreement would prove nothing.
        Oracle(
            id: "hours-weekday-rulers",
            source: valens + "; preserved in the Romance weekday names (mardi/Mars, " +
                    "mercredi/Mercury, jeudi/Jupiter, vendredi/Venus)",
            inputs: "Calendar weekday 1…7 (1 = Sunday) → the planet ruling that day's first hour",
            precision: "±0.5 on a planet index",
            values: [
                "1": p(.sun), "2": p(.moon), "3": p(.mars), "4": p(.mercury),
                "5": p(.jupiter), "6": p(.venus), "7": p(.saturn),
            ],
            tolerances: ["1": exact, "2": exact, "3": exact, "4": exact,
                         "5": exact, "6": exact, "7": exact]
        ),

        // ── The closure that makes the week ──────────────────────────────────────────
        // 24 hours advanced through a 7-planet cycle lands 24 mod 7 = 3 places on, and three steps
        // in Chaldean order is one weekday. This is *why* the weekday order is what it is, and it
        // is the single check a clock-hour implementation can never satisfy.
        Oracle(
            id: "hours-weekday-closure-step",
            source: valens + " — the derivation of the seven-day week from the 24-hour cycle",
            inputs: "number of Chaldean positions advanced by one full 24-hour planetary day",
            precision: "±0.5 — an integer count",
            values: ["step": 3, "cycleLength": 7, "hoursPerDay": 24],
            tolerances: ["step": exact, "cycleLength": exact, "hoursPerDay": exact]
        ),

        // ── The one external number ──────────────────────────────────────────────────
        Oracle(
            id: "hours-equinox-equator-geometric",
            source: geometry,
            inputs: "declination 0°, latitude 0°, geometric horizon (altitude 0°)",
            precision: "±1e-9 — this is exact spherical trigonometry, not a measurement; the " +
                       "tolerance guards floating-point only",
            values: ["hourAngleDeg": 90.0, "dayLengthHours": 12.0, "hourLengthMinutes": 60.0],
            tolerances: ["hourAngleDeg": 1e-9, "dayLengthHours": 1e-9, "hourLengthMinutes": 1e-7]
        ),

        // ── Refraction, which is why the anchor above says "geometric" ───────────────
        // With the shipping convention (upper limb, refracted) the Sun is above the horizon LONGER
        // than it is below, everywhere, including at the equinox on the equator. Recording the
        // expected size of that asymmetry stops someone "fixing" it back to 60 minutes.
        Oracle(
            id: "hours-refraction-extends-the-day",
            source: "Meeus, Astronomical Algorithms (2nd ed.), ch. 15 — standard altitude of " +
                    "−0°50′ for the Sun (34′ refraction + 16′ semidiameter)",
            inputs: "equinox at the equator, true rise/set of the upper limb vs the geometric horizon",
            precision: "±1.5 min on the day-length excess — the value follows from the 50′ " +
                       "altitude offset and the Sun's ~0.25°/min horizon crossing rate at the equator",
            values: ["dayExcessMinutes": 6.7],
            tolerances: ["dayExcessMinutes": 1.5]
        ),
    ]
}
