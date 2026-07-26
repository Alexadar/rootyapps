import Foundation

/// Rectangular-room modal analysis: the full axial/tangential/oblique mode grid, mode spacing,
/// the Bonello distribution criterion, and nearest published "good" room ratios.
/// Pure, stateless. MODEL CAVEAT: assumes a rigid rectangular box; real rooms (openings, non-rigid
/// walls, furniture) diverge — treat as a design guide, not a measurement.
public enum RoomModes {
    public static let speedOfSound = 343.0   // m/s at ~20 °C

    public enum ModeType: String, Sendable { case axial, tangential, oblique }

    public struct Mode: Sendable, Equatable {
        public let nx, ny, nz: Int
        public let hz: Double
        public let type: ModeType
    }

    /// Every eigenmode with frequency ≤ `maxHz`, sorted ascending.
    /// f = (c/2)·√((nx/L)² + (ny/W)² + (nz/H)²); (0,0,0) excluded. Type = # of nonzero indices.
    public static func modes(lengthM L: Double, widthM W: Double, heightM H: Double,
                             speed c: Double = speedOfSound, maxHz: Double) -> [Mode] {
        guard L > 0, W > 0, H > 0, maxHz > 0 else { return [] }
        var out: [Mode] = []
        let half = c / 2
        var nx = 0
        while half * Double(nx) / L <= maxHz {
            var ny = 0
            while (half * (pow(Double(nx) / L, 2) + pow(Double(ny) / W, 2)).squareRoot()) <= maxHz {
                var nz = 0
                while true {
                    let f = half * (pow(Double(nx) / L, 2) + pow(Double(ny) / W, 2) + pow(Double(nz) / H, 2)).squareRoot()
                    if f > maxHz { break }
                    if !(nx == 0 && ny == 0 && nz == 0) {
                        let nonzero = [nx, ny, nz].filter { $0 > 0 }.count
                        let t: ModeType = nonzero == 1 ? .axial : (nonzero == 2 ? .tangential : .oblique)
                        out.append(Mode(nx: nx, ny: ny, nz: nz, hz: f, type: t))
                    }
                    nz += 1
                }
                ny += 1
            }
            nx += 1
        }
        return out.sorted { $0.hz < $1.hz }
    }

    /// Smallest gap between consecutive mode frequencies (Hz). 0 if fewer than two modes.
    public static func smallestSpacing(_ modes: [Mode]) -> Double {
        guard modes.count >= 2 else { return 0 }
        var minGap = Double.greatestFiniteMagnitude
        for i in 1..<modes.count { minGap = Swift.min(minGap, modes[i].hz - modes[i - 1].hz) }
        return minGap
    }

    /// Bonello criterion: binning modes into one-third-octave bands, the per-band count must be
    /// monotonically non-decreasing across occupied bands. (Bonello, JAES 1981.)
    public static func bonelloPasses(lengthM L: Double, widthM W: Double, heightM H: Double,
                                     speed c: Double = speedOfSound, upToHz: Double) -> Bool {
        let ms = modes(lengthM: L, widthM: W, heightM: H, speed: c, maxHz: upToHz)
        guard !ms.isEmpty else { return true }
        var band: [Int: Int] = [:]                       // 1/3-oct band index → count (ref 16 Hz)
        for m in ms { band[Int(floor(3 * log2(m.hz / 16))), default: 0] += 1 }
        var prev = 0
        for k in band.keys.sorted() {
            let count = band[k]!
            if count < prev { return false }
            prev = count
        }
        return true
    }

    /// Published "good" room proportions, as `(mid, long)` with the short side normalized to 1.
    public static let recommendedRatios: [(name: String, mid: Double, long: Double)] = [
        ("Sepmeyer A", 1.14, 1.39),
        ("Sepmeyer B", 1.28, 1.54),
        ("Sepmeyer C", 1.60, 2.33),
        ("Louden A",   1.40, 1.90),
        ("Louden B",   1.30, 1.90),
        ("Louden C",   1.50, 2.50),
        ("IEC / Bolt", 1.60, 2.33),
    ]

    /// Dimensions normalized so the shortest side = 1, returned as (1, mid, long).
    public static func normalizedRatio(_ L: Double, _ W: Double, _ H: Double) -> (Double, Double, Double) {
        let s = [L, W, H].sorted()
        let m = s[0]
        guard m > 0 else { return (0, 0, 0) }
        return (1, s[1] / m, s[2] / m)
    }

    /// Closest published ratio to the given room, by Euclidean distance in (mid, long) space.
    public static func nearestRatio(_ L: Double, _ W: Double, _ H: Double)
        -> (name: String, mid: Double, long: Double, distance: Double) {
        let (_, mid, long) = normalizedRatio(L, W, H)
        var best = recommendedRatios[0]
        var bestD = Double.greatestFiniteMagnitude
        for r in recommendedRatios {
            let d = (pow(mid - r.mid, 2) + pow(long - r.long, 2)).squareRoot()
            if d < bestD { bestD = d; best = r }
        }
        return (best.name, best.mid, best.long, bestD)
    }

    /// A degenerate proportion (a repeated dimension or an integer-multiple pair) piles modes up —
    /// the classic thing to avoid. True = at least one degenerate relationship.
    public static func hasDegenerateRatio(_ L: Double, _ W: Double, _ H: Double, tolerance: Double = 0.03) -> Bool {
        let d = [L, W, H]
        for i in 0..<3 {
            for j in (i + 1)..<3 {
                let r = Swift.max(d[i], d[j]) / Swift.min(d[i], d[j])
                if abs(r - r.rounded()) < tolerance { return true }   // 1×, 2×, 3× …
            }
        }
        return false
    }
}
