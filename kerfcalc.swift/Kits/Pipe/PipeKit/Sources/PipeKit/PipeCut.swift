import Foundation

/// Cut length — turning a laid-out centre-to-centre dimension into a piece you can actually cut.
/// Pure, stateless. All lengths in inches.
///
/// Layout dimensions are centre-to-centre of the fittings; the pipe between them is shorter by each
/// fitting's **take-out** (centre of fitting to the face the pipe lands on, less any thread/socket
/// engagement):
///
///     end-to-end = centre-to-centre − take-out A − take-out B
///
/// **Take-outs are NOT oracle-backed and are never shipped as a table.** They vary by manufacturer,
/// material, pressure class and joining method, so the user enters the two values they measured or
/// keep on file. This function is the definition of the subtraction, nothing more.
public enum PipeCut {

    /// Pipe length to cut between two fittings. Never returns negative — if the take-outs exceed the
    /// centre-to-centre dimension the fittings collide, which reads as 0 rather than a negative cut.
    public static func endToEndIn(centerToCenterIn: Double,
                                  takeoutAIn: Double, takeoutBIn: Double) -> Double {
        let e = centerToCenterIn - takeoutAIn - takeoutBIn
        return e > 0 ? e : 0
    }

    /// Inverse — the centre-to-centre dimension a cut piece plus its two take-outs will produce.
    public static func centerToCenterIn(endToEndIn: Double,
                                        takeoutAIn: Double, takeoutBIn: Double) -> Double {
        endToEndIn + takeoutAIn + takeoutBIn
    }

    /// True when the two take-outs consume the whole centre-to-centre dimension — the fittings won't
    /// fit and there is no pipe left to cut.
    public static func fittingsCollide(centerToCenterIn: Double,
                                       takeoutAIn: Double, takeoutBIn: Double) -> Bool {
        centerToCenterIn - takeoutAIn - takeoutBIn <= 0
    }
}
