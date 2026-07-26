import Foundation

/// Fuel planning math. Volumes are US gallons, rates gallons/hour, times hours.
public enum Fuel {

    /// Standard fuel weights (lb per US gallon) at ~15 °C.
    public static let avgasLbPerGal = 6.0
    public static let jetALbPerGal  = 6.7

    /// Fuel burned (gal) for a duration at a burn rate.
    public static func requiredGal(gph: Double, timeHr: Double) -> Double { gph * timeHr }

    /// Endurance (hours) available from a fuel quantity at a burn rate.
    public static func enduranceHr(fuelGal: Double, gph: Double) -> Double {
        gph > 0 ? fuelGal / gph : 0
    }

    /// Burn rate (gph) implied by a quantity consumed over a time.
    public static func gph(fuelGal: Double, timeHr: Double) -> Double {
        timeHr > 0 ? fuelGal / timeHr : 0
    }

    /// Specific range — nautical miles per gallon at a groundspeed and burn rate.
    public static func specificRangeNmPerGal(gsKt: Double, gph: Double) -> Double {
        gph > 0 ? gsKt / gph : 0
    }
}
