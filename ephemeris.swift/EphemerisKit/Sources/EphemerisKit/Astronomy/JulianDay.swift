import Foundation

extension Date {
    /// Julian Day (UT). JD 2440587.5 == 1970-01-01T00:00:00Z.
    var julianDay: Double {
        2440587.5 + timeIntervalSince1970 / 86_400.0
    }

    /// Schlyter day number: days since the epoch 2000 Jan 0.0 UT
    /// (= 1999-12-31T00:00:00Z = JD 2451543.5). Fractional, includes time of day.
    var schlyterDay: Double {
        julianDay - 2_451_543.5
    }
}
