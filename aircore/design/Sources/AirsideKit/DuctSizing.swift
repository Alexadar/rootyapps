import Foundation

/// Straight-duct sizing from friction rate. NOT a duct-design tool: no fittings,
/// no equivalent length, no total effective length.
public enum DuctSizing {

    public enum Material: String, CaseIterable, Sendable {
        case galvanized, spiral, flex, fibrous
        /// Absolute roughness, ft (published physical constants).
        public var roughnessFt: Double {
            switch self {
            case .galvanized: return 0.0003
            case .spiral:     return 0.0003
            case .flex:       return 0.003
            case .fibrous:    return 0.0009
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public var diameterIn: Double
        public var velocityFPM: Double
        public var equivRect: (a: Int, b: Int)
        public var whistles: Bool          // above noise limit
        public static func == (l: Result, r: Result) -> Bool {
            l.diameterIn == r.diameterIn && l.velocityFPM == r.velocityFPM && l.whistles == r.whistles
        }
    }

    public static let noiseLimitFPM: Double = 1200

    /// Round diameter (in) for CFM at a friction rate (in wg / 100 ft), plus velocity check.
    public static func size(cfm: Double, frictionPer100ft fr: Double) -> Result {
        // Darcy-based friction-chart approximation solved for D (inches).
        let d = pow(0.109136 * pow(cfm, 1.9) / fr, 1.0 / 5.02)
        let areaFt2 = Double.pi * pow(d / 12, 2) / 4
        let vel = areaFt2 > 0 ? cfm / areaFt2 : .infinity
        let a = Int(d.rounded())
        let b = max(4, Int((d * 0.85).rounded()))
        return Result(diameterIn: d, velocityFPM: vel, equivRect: (a, b), whistles: vel > noiseLimitFPM)
    }

    /// Round -> rectangular equivalent diameter.  De = 1.30·(a·b)^0.625 / (a+b)^0.25
    public static func equivalentDiameter(a: Double, b: Double) -> Double {
        1.30 * pow(a * b, 0.625) / pow(a + b, 0.25)
    }
}
