import Testing
import Foundation
@testable import GeomagKit

@Suite("Oracle corpus integrity")
struct GuardTests {
    @Test func hasSources() {
        for o in Oracles.all { #expect(!o.source.isEmpty); #expect(!o.values.isEmpty)
            for k in o.values.keys { #expect(o.tolerances[k] != nil) } }
    }
    @Test func idsUnique() { #expect(Set(Oracles.all.map(\.id)).count == Oracles.all.count) }
    @Test func corpusLoaded() {
        // The embedded official file must parse into a real corpus (was ~100 rows).
        #expect(Oracles.rows.count >= 50, "embedded WMM2025 test-value corpus not parsed")
    }
}

// Oracle = OFFICIAL WMM2025 test values (NOAA/NCEI & BGS), embedded verbatim.  oracle-backed
// Epoch note: WMM2025 valid 2025–2029 — expire/replace at WMM2030.
@Suite("WMM2025 official test values")
struct WMMOracleTests {
    @Test func synthesisMatchesOfficialTestValues() throws {
        let wmm = try #require(WMM(cof: WMM2025.cof), "embedded WMM2025 COF failed to parse")
        var checked = 0, maxNT = 0.0, maxDeg = 0.0
        for r in Oracles.rows {
            let f = wmm.field(decimalYear: r.year, altitudeKm: r.altKm, latDeg: r.latDeg, lonDeg: r.lonDeg)
            maxNT = max(maxNT, abs(f.x - r.x), abs(f.y - r.y), abs(f.z - r.z), abs(f.f - r.f), abs(f.h - r.h))
            maxDeg = max(maxDeg, abs(f.declinationDeg - r.d), abs(f.inclinationDeg - r.i))
            checked += 1
        }
        print("WMM: checked \(checked) official test points — max |ΔXYZHF| = \(String(format: "%.4f", maxNT)) nT, "
              + "max |ΔD,I| = \(String(format: "%.5f", maxDeg))°")
        #expect(checked >= 50, "test-value corpus not loaded")
        #expect(maxNT < 5.0, "max field error \(maxNT) nT")
        #expect(maxDeg < 0.05, "max angle error \(maxDeg)°")
    }
}
