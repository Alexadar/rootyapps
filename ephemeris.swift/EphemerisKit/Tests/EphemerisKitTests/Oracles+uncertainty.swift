import Foundation
import EphemerisKit

/// External ground truth for what an unknown birth time can and cannot pin down.
///
/// The quantity that decides everything here is how far a body moves in a day: that is the width
/// of the ignorance an untimed chart carries. For every body except the Moon it is small enough to
/// round away; for the Moon it is most of a sign, which is why the feature exists at all.
///
/// EXTERNAL oracle kind. The Moon's mean daily motion is a published constant, not something this
/// project may derive from its own engine — checking the engine against a number the engine
/// produced would prove nothing. The extremes are the standard quoted bounds of the Moon's
/// apparent daily motion, which vary with the anomalistic cycle (fastest at perigee, slowest at
/// apogee); the tolerances below are deliberately loose because the assertion is "the engine is in
/// the right regime", not "the engine reproduces a rounded almanac figure to five places".
enum uncertaintyOracles {

    private static let meeus =
        "Meeus, Astronomical Algorithms (2nd ed.), ch. 45 — the Moon's mean longitude term, " +
        "dL/dt = 13.176358°/day"
    private static let bounds =
        "Explanatory Supplement to the Astronomical Almanac — the Moon's apparent daily motion " +
        "in longitude ranges from about 11°46' (apogee) to about 15°23' (perigee)"

    static let all: [Oracle] = [
        Oracle(
            id: "uncertainty-moon-mean-daily-motion",
            source: meeus,
            inputs: "mean of the Moon's longitude travelled per civil day, sampled across 1900–2100",
            precision: "±0.02°/day — the mean over a long span must converge on the published " +
                       "constant; a wider miss means the engine's lunar term is wrong, not noisy",
            values: ["degreesPerDay": 13.176358],
            tolerances: ["degreesPerDay": 0.02]
        ),
        Oracle(
            id: "uncertainty-moon-daily-motion-bounds",
            source: bounds,
            inputs: "extremes of the Moon's longitude travelled in one civil day",
            precision: "±0.6°/day on each bound. The quoted figures are rounded almanac values " +
                       "and the true extremes drift slightly with the epoch, so this asserts the " +
                       "regime — no day is anywhere near 11° or 16°",
            values: ["slowestDegreesPerDay": 11.767, "fastestDegreesPerDay": 15.383],
            tolerances: ["slowestDegreesPerDay": 0.6, "fastestDegreesPerDay": 0.6]
        ),
    ]
}
