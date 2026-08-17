import Foundation

/// Fan affinity laws with air-density correction.
public enum FanLaws {
    /// CFM ∝ N
    public static func flow(from cfm1: Double, n1: Double, n2: Double) -> Double { cfm1 * (n2 / n1) }
    /// SP ∝ N²
    public static func staticPressure(from sp1: Double, n1: Double, n2: Double) -> Double { sp1 * pow(n2 / n1, 2) }
    /// BHP ∝ N³
    public static func brakeHorsepower(from bhp1: Double, n1: Double, n2: Double) -> Double { bhp1 * pow(n2 / n1, 3) }

    /// Density correction for BHP moving between two altitudes (ratio of local pressures).
    public static func densityCorrectedBHP(_ bhp: Double, from: Altitude, to: Altitude) -> Double {
        bhp * (to.pressurePa / from.pressurePa)
    }
}
