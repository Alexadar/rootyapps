import Testing
import Foundation
@testable import GeomagKit

// Oracle = the WMM2025 distribution's own stated validity window and file format.
// https://www.ncei.noaa.gov/products/world-magnetic-model/wmm-coefficients -- provenance.
@Suite("WMM2025 provenance and expiry")
struct WMMProvenanceTests {

    /// The embedded COF was diffed against the official NCEI distribution
    /// (WMM2025COF.zip, retrieved 2026-07-26) and matched exactly. This test
    /// guards the header so a bad edit or a silently swapped model is caught.
    @Test("the embedded coefficient file is WMM-2025 at epoch 2025.0")
    func epochHeader() throws {
        let first = try #require(WMM2025.cof.split(whereSeparator: \.isNewline).first)
        #expect(first.contains("WMM-2025"), "unexpected COF header: \(first)")
        let wmm = try #require(WMM(cof: WMM2025.cof))
        #expect(wmm.epoch == 2025.0, "expected epoch 2025.0, got \(wmm.epoch)")
    }

    /// A degree/order-12 model carries 90 main-field lines (n = 1…12, m = 0…n).
    @Test("the coefficient file carries a complete degree-12 set")
    func coefficientCount() {
        let rows = WMM2025.cof.split(whereSeparator: \.isNewline).dropFirst().filter { line in
            let t = line.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            guard t.count >= 6 else { return false }
            let n = Int(t[0]), m = Int(t[1])
            return n >= 1 && n <= 12 && m >= 0 && m <= n
        }
        #expect(rows.count == 90, "expected 90 main-field coefficient lines, got \(rows.count)")
    }

    /// WMM2025 is valid 2025.0–2030.0. This test **is meant to fail** once the
    /// model expires: shipping a stale magnetic model to mariners is a real
    /// navigational error, so the build should stop rather than degrade quietly.
    @Test("the embedded model has not expired")
    func modelNotExpired() {
        let validFrom = 2025.0, validTo = 2030.0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let year = Double(cal.component(.year, from: now))
        let start = cal.date(from: DateComponents(year: Int(year), month: 1, day: 1))!
        let next = cal.date(from: DateComponents(year: Int(year) + 1, month: 1, day: 1))!
        let decimalYear = year + now.timeIntervalSince(start) / next.timeIntervalSince(start)

        #expect(decimalYear >= validFrom && decimalYear < validTo,
                """
                WMM2025 is valid \(validFrom)–\(validTo) but today is \(decimalYear). \
                Replace the embedded WMM.COF and WMM2025_TestValues.txt with the current \
                model from https://www.ncei.noaa.gov/products/world-magnetic-model/wmm-coefficients \
                and update this window.
                """)
    }
}

// Oracle = definitions of the geomagnetic elements. Identity/invariant.
@Suite("Geomagnetic element identities")
struct GeomagIdentityTests {

    private func field(_ lat: Double, _ lon: Double,
                       year: Double = 2026.5, alt: Double = 0) throws -> GeomagField {
        let wmm = try #require(WMM(cof: WMM2025.cof))
        return wmm.field(decimalYear: year, altitudeKm: alt, latDeg: lat, lonDeg: lon)
    }

    /// H² = X² + Y², F² = H² + Z², D = atan2(Y, X), I = atan2(Z, H) — by definition.
    @Test("the element identities hold everywhere on the globe")
    func elementIdentities() throws {
        for lat in stride(from: -85.0, through: 85.0, by: 17.0) {
            for lon in stride(from: -180.0, through: 180.0, by: 37.0) {
                let f = try field(lat, lon)
                #expect(abs(f.h - (f.x * f.x + f.y * f.y).squareRoot()) < 1e-6,
                        "H != hypot(X,Y) at \(lat),\(lon)")
                #expect(abs(f.f - (f.h * f.h + f.z * f.z).squareRoot()) < 1e-6,
                        "F != hypot(H,Z) at \(lat),\(lon)")
                #expect(abs(f.declinationDeg - atan2(f.y, f.x) * 180 / .pi) < 1e-9)
                #expect(abs(f.inclinationDeg - atan2(f.z, f.h) * 180 / .pi) < 1e-9)
                #expect(f.declinationDeg >= -180 && f.declinationDeg <= 180)
                #expect(f.inclinationDeg >= -90 && f.inclinationDeg <= 90)
            }
        }
    }

    /// Field strength is ~24,000–66,000 nT at the surface; anything outside that
    /// means the synthesis or the Schmidt normalisation has gone wrong.
    @Test("total intensity stays within the physical range")
    func intensityRange() throws {
        var lo = Double.infinity, hi = -Double.infinity
        for lat in stride(from: -89.0, through: 89.0, by: 7.0) {
            for lon in stride(from: -180.0, through: 179.0, by: 11.0) {
                let f = try field(lat, lon)
                lo = min(lo, f.f); hi = max(hi, f.f)
            }
        }
        #expect(lo > 20_000 && lo < 30_000, "minimum F \(lo) nT is implausible")
        #expect(hi > 60_000 && hi < 70_000, "maximum F \(hi) nT is implausible")
    }

    /// Inclination is positive (down) in the northern magnetic hemisphere and
    /// negative in the southern — the sign convention a compass user depends on.
    ///
    /// Sampled near the **dip poles**, not the geographic ones: the magnetic and
    /// geographic poles are far apart (the south dip pole sits near 136°E off
    /// Adelie Land), so 70°S 0°E dips only about -60 degrees.
    @Test("inclination dips vertically at the dip poles, with the right sign")
    func inclinationSign() throws {
        #expect(try field(86, -150).inclinationDeg > 88,
                "should dip almost vertically down near the north dip pole")
        #expect(try field(-64, 136).inclinationDeg < -88,
                "should dip almost vertically up near the south dip pole")
        // And the sign simply follows the hemisphere well away from the poles.
        #expect(try field(60, -100).inclinationDeg > 0)
        #expect(try field(-60, 0).inclinationDeg < 0)
    }

    /// The magnetic equator (I = 0) does not follow the geographic one: in the
    /// Atlantic sector it lies well north of it, so I is negative at 0°N 0°E.
    @Test("the magnetic equator is offset from the geographic equator")
    func magneticEquatorOffset() throws {
        #expect(try field(0, 0).inclinationDeg < -20,
                "at 0N 0E the magnetic equator lies to the north, so I should be clearly negative")
        // Crossing north along the prime meridian must pass through I = 0.
        var crossed = false
        var previous = try field(0, 0).inclinationDeg
        for lat in stride(from: 2.0, through: 30.0, by: 2.0) {
            let now = try field(lat, 0).inclinationDeg
            if previous < 0 && now >= 0 { crossed = true }
            previous = now
        }
        #expect(crossed, "should cross the magnetic equator heading north along 0E")
    }

    /// Secular variation must actually move the field — a model that ignores the
    /// SV terms would return identical values across the epoch.
    @Test("secular variation changes the field across the model's validity window")
    func secularVariationApplies() throws {
        let a = try field(51.5, -0.13, year: 2025.0)
        let b = try field(51.5, -0.13, year: 2029.9)
        #expect(abs(a.declinationDeg - b.declinationDeg) > 0.05,
                "declination did not drift: \(a.declinationDeg) vs \(b.declinationDeg)")
        #expect(abs(a.f - b.f) > 10, "total intensity did not drift")
    }

    /// Field strength falls off with altitude (roughly as 1/r³ for a dipole).
    @Test("intensity decreases with altitude")
    func altitudeFalloff() throws {
        let surface = try field(45, 0, alt: 0)
        let high = try field(45, 0, alt: 400)
        #expect(high.f < surface.f, "F should decrease with altitude")
        #expect(high.f > surface.f * 0.7, "F should not collapse over 400 km")
    }

    /// Longitude is periodic: the field at λ and λ+360° must be identical.
    @Test("longitude wraps at 360 degrees")
    func longitudeWrap() throws {
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            let a = try field(lat, 170)
            let b = try field(lat, 170 - 360)
            #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 && abs(a.z - b.z) < 1e-6,
                    "longitude wrap broken at lat \(lat)")
        }
    }

    /// East declination is positive, west negative. Checked where the sign is
    /// unambiguous and well known: the US west coast is east-declining, the US
    /// east coast west-declining, in the current epoch.
    @Test("declination sign convention is east-positive")
    func declinationSign() throws {
        #expect(try field(37.8, -122.4).declinationDeg > 0,
                "San Francisco should have easterly (positive) declination")
        #expect(try field(42.4, -71.0).declinationDeg < 0,
                "Boston should have westerly (negative) declination")
    }

    @Test("a malformed coefficient file is rejected rather than half-parsed")
    func rejectsGarbage() {
        #expect(WMM(cof: "") == nil)
        #expect(WMM(cof: "not a header\n1 0 1.0 0.0 0.0 0.0") == nil)
    }
}
