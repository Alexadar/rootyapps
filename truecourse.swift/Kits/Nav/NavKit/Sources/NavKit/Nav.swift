import Foundation

/// Time–speed–distance navigation math. Distances are nautical miles, speeds knots,
/// times minutes.
public enum Nav {

    /// Leg time (minutes) to cover a distance at a groundspeed.
    public static func timeMin(distanceNm: Double, gsKt: Double) -> Double {
        gsKt > 0 ? distanceNm / gsKt * 60 : 0
    }

    /// Distance (nm) flown in a time at a groundspeed.
    public static func distanceNm(gsKt: Double, timeMin: Double) -> Double {
        gsKt * timeMin / 60
    }

    /// Groundspeed (kt) from a distance flown in a time.
    public static func groundspeedKt(distanceNm: Double, timeMin: Double) -> Double {
        timeMin > 0 ? distanceNm / timeMin * 60 : 0
    }
}
