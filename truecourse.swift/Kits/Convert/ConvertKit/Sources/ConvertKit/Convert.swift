import Foundation

/// Aviation unit conversions — exact published factors. All functions are pure and
/// reversible by their named inverse.
public enum Convert {

    // Exact conversion factors.
    static let smPerNm   = 1.15078       // statute miles per nautical mile
    static let kmPerNm   = 1.852         // km per nautical mile (exact, by definition)
    static let mPerFt    = 0.3048        // metres per foot (exact)
    static let kgPerLb   = 0.45359237    // kilograms per pound (exact)
    static let litrePerGal = 3.785411784 // litres per US gallon (exact)
    static let mphPerKt  = 1.15078       // statute mph per knot
    static let feetPerNm = 6076.11549    // feet in one nautical mile

    // Temperature
    public static func cToF(_ c: Double) -> Double { c * 9 / 5 + 32 }
    public static func fToC(_ f: Double) -> Double { (f - 32) * 5 / 9 }

    // Distance
    public static func nmToSm(_ nm: Double) -> Double { nm * smPerNm }
    public static func smToNm(_ sm: Double) -> Double { sm / smPerNm }
    public static func nmToKm(_ nm: Double) -> Double { nm * kmPerNm }
    public static func kmToNm(_ km: Double) -> Double { km / kmPerNm }
    public static func ftToM(_ ft: Double) -> Double { ft * mPerFt }
    public static func mToFt(_ m: Double) -> Double { m / mPerFt }

    // Speed
    public static func ktToMph(_ kt: Double) -> Double { kt * mphPerKt }
    public static func mphToKt(_ mph: Double) -> Double { mph / mphPerKt }

    // Weight
    public static func lbToKg(_ lb: Double) -> Double { lb * kgPerLb }
    public static func kgToLb(_ kg: Double) -> Double { kg / kgPerLb }

    // Fuel (weights at ~15 °C)
    public static func avgasGalToLb(_ gal: Double) -> Double { gal * 6.0 }
    public static func avgasLbToGal(_ lb: Double) -> Double { lb / 6.0 }
    public static func jetAGalToLb(_ gal: Double) -> Double { gal * 6.7 }
    public static func jetALbToGal(_ lb: Double) -> Double { lb / 6.7 }
    public static func galToLitre(_ gal: Double) -> Double { gal * litrePerGal }
    public static func litreToGal(_ l: Double) -> Double { l / litrePerGal }

    // Climb gradient
    public static func ftPerNmToPercent(_ ftPerNm: Double) -> Double { ftPerNm / feetPerNm * 100 }
    public static func percentToFtPerNm(_ percent: Double) -> Double { percent / 100 * feetPerNm }
    public static func ftPerNmToDegrees(_ ftPerNm: Double) -> Double { atan(ftPerNm / feetPerNm) * 180 / .pi }
    public static func degreesToFtPerNm(_ deg: Double) -> Double { tan(deg * .pi / 180) * feetPerNm }
}
