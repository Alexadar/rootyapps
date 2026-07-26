import Foundation

/// Stair-code limits (configurable — construction varies by adopted code).
public struct StairCode: Equatable, Sendable {
    public let name: String
    public let maxRiser: Double     // inches
    public let minTread: Double     // inches (tread depth, exclusive of nosing)
    public let minHeadroom: Double  // inches

    public init(name: String, maxRiser: Double, minTread: Double, minHeadroom: Double) {
        self.name = name; self.maxRiser = maxRiser; self.minTread = minTread; self.minHeadroom = minHeadroom
    }

    /// IRC 2021 R311.7 — residential: 7¾" max riser, 10" min tread, 6'-8" (80") headroom.
    public static let irc2021 = StairCode(name: "IRC 2021 (residential)", maxRiser: 7.75, minTread: 10, minHeadroom: 80)
    /// IBC — commercial: 7" max riser, 11" min tread, 6'-8" headroom.
    public static let ibc = StairCode(name: "IBC (commercial)", maxRiser: 7.0, minTread: 11, minHeadroom: 80)
}

public struct StairResult: Equatable, Sendable {
    public let risers: Int
    public let riserHeight: Double   // inches
    public let treads: Int
    public let treadDepth: Double     // inches
    public let totalRun: Double        // inches
    public let stringerLength: Double  // inches (line length, Pythagorean)
    public let riserOK: Bool
    public let treadOK: Bool
    public let headroom: Double         // inches (measured)
    public let headroomOK: Bool
    public let blondel: Double          // 2R + T comfort figure
}

/// Straight-flight stair layout. Pure, stateless.
public enum Stairs {
    /// Solve a stair from total rise (finished floor to finished floor).
    /// `idealRiser` seeds the riser count (rounded to the nearest whole riser); `treadDepth` is
    /// the chosen tread run. Code compliance is checked against `code` but never silently altered.
    public static func solve(totalRise: Double,
                             treadDepth: Double = 10,
                             idealRiser: Double = 7.5,
                             code: StairCode = .irc2021,
                             headroomIn: Double = 80) -> StairResult {
        let n = max(1, Int((totalRise / idealRiser).rounded()))   // nearest whole number of risers
        let riserH = totalRise / Double(n)
        let treads = max(0, n - 1)
        let run = Double(treads) * treadDepth
        let stringer = (totalRise * totalRise + run * run).squareRoot()
        return StairResult(
            risers: n, riserHeight: riserH, treads: treads, treadDepth: treadDepth,
            totalRun: run, stringerLength: stringer,
            riserOK: riserH <= code.maxRiser + 1e-9,
            treadOK: treadDepth >= code.minTread - 1e-9,
            headroom: headroomIn,
            headroomOK: headroomIn >= code.minHeadroom - 1e-9,
            blondel: 2 * riserH + treadDepth)
    }

    /// Blondel's comfort rule: 2·riser + tread, target ≈ 24–25 inches.
    public static func blondel(riser: Double, tread: Double) -> Double { 2 * riser + tread }
}
