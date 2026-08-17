import Foundation

/// Global or per-field unit system. Switching is free and reversible — the stored
/// value converts, it is never re-rounded.
public enum UnitSystem: String, Sendable { case ip = "IP", si = "SI" }

public enum Temp {
    public static func fToC(_ f: Double) -> Double { (f - 32) / 1.8 }
    public static func cToF(_ c: Double) -> Double { c * 1.8 + 32 }
}

public enum Convert {
    /// grains/lb  ->  g/kg
    public static func grToGkg(_ gr: Double) -> Double { gr / 7.0 }
    /// Btu/lb  ->  kJ/kg
    public static func btuLbToKjKg(_ b: Double) -> Double { b * 2.326 }
    /// ft³/lb  ->  m³/kg
    public static func ft3LbToM3Kg(_ v: Double) -> Double { v * 0.0624279606 }
    /// feet -> metres
    public static func ftToM(_ ft: Double) -> Double { ft * 0.3048 }
}
