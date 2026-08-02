import Testing
import Foundation
import EphemerisKit

/// **Oracle-backed** accuracy of the position engine, measured against NASA/JPL Horizons
/// across two centuries — the check a practitioner performs when they open Solar Fire and
/// compare. Expected numbers live only in `Oracles.swift`, each citing its source.
///
/// What this establishes: every body the app renders stays within a *measured*, cited bound
/// from 1900 to 2100. Before this suite the only external references were six bodies at a
/// single instant in 2026, with tolerances (0.25°–1.0°) far looser than the engine's real
/// error — so a genuine regression could have slipped through unnoticed.
@Suite("Accuracy vs JPL Horizons")
struct AccuracyTests {

    private static let epochs = [1900, 1925, 1950, 1975, 2000, 2025, 2050, 2075, 2100]

    /// Every body, every epoch, against the cited Horizons value.
    @Test func allBodiesTrackHorizonsAcrossTwoCenturies() {
        for body in CelestialBody.allCases {
            let oracle = Oracles.require("horizons-\(body.rawValue)")
            for year in Self.epochs {
                let key = String(year)
                guard let expected = oracle.values[key] else {
                    Issue.record("\(body.name): no oracle value for \(year)"); continue
                }
                let got = Ephemeris.longitude(of: body, at: utc(year, 1, 1, 0, 0))
                // Compare through the 0/360 seam, then hand the signed error to `matches`
                // as an offset from the oracle value.
                let delta = AstroMath.norm180(got - expected)
                let arcmin = String(format: "%.1f", abs(delta) * 60)
                let tol = String(format: "%.1f", (oracle.tolerances[key] ?? 0) * 60)
                #expect(oracle.matches(key, expected + delta),
                        "\(body.name) \(year): off by \(arcmin)′ (tolerance \(tol)′)")
            }
        }
    }

    /// The headline number, asserted rather than assumed: nothing drifts past 10 arcminutes
    /// anywhere in 1900–2100. Measured worst case is the Moon at 6.2′; this leaves margin
    /// without letting a real regression hide.
    @Test func worstCaseErrorStaysUnderTenArcminutes() {
        var worst = 0.0
        var worstDesc = ""
        for body in CelestialBody.allCases {
            let oracle = Oracles.require("horizons-\(body.rawValue)")
            for (key, expected) in oracle.values {
                guard let year = Int(key) else { continue }
                let got = Ephemeris.longitude(of: body, at: utc(year, 1, 1, 0, 0))
                let arcmin = abs(AstroMath.norm180(got - expected)) * 60
                if arcmin > worst { worst = arcmin; worstDesc = "\(body.name) \(year)" }
            }
        }
        #expect(worst < 10.0, "worst error \(String(format: "%.1f", worst))′ at \(worstDesc)")
    }

    /// Pluto's series is documented as valid ~1800–2099. Prove the claim holds at the top of
    /// the supported window rather than trusting the comment — transit work runs past 2099.
    @Test func plutoHoldsToTheEndOfItsDocumentedWindow() {
        let oracle = Oracles.require("horizons-pluto")
        for year in [2075, 2100] {
            guard let expected = oracle.values[String(year)] else { continue }
            let got = Ephemeris.longitude(of: .pluto, at: utc(year, 1, 1, 0, 0))
            let arcmin = abs(AstroMath.norm180(got - expected)) * 60
            #expect(arcmin < 10, "Pluto \(year) off by \(String(format: "%.1f", arcmin))′")
        }
    }

    /// The four bodies that previously had **no** external check at all. Called out separately
    /// so the coverage gap can't silently reopen.
    @Test func previouslyUncheckedBodiesAreNowCovered() {
        for body in [CelestialBody.moon, .uranus, .neptune, .pluto] {
            let oracle = Oracles.require("horizons-\(body.rawValue)")
            #expect(oracle.values.count >= 9, "\(body.name) needs full epoch coverage")
            #expect(oracle.source.contains("Horizons"))
        }
    }
}
