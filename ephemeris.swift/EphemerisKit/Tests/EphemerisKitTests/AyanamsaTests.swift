import Testing
import Foundation
@testable import EphemerisKit

/// The sidereal frame.
///
/// The single most important test in this suite is the **epoch series**, not the round trip. A
/// round trip passes trivially for any implementation, including one that returns a constant. What
/// separates a correct ayanamsa from a plausible one is whether it grows at the right rate — so the
/// oracle checks five epochs a century and a half apart, and hardcoding today's ~24° misses 1900 by
/// 1.4°, a hundred times the tolerance.
@Suite("Sidereal zodiac")
struct AyanamsaTests {

    private func jan1(_ year: Int) -> Date { utc(year, 1, 1, 0, 0) }

    // MARK: - The rate, which is the whole difficulty

    @Test func lahiriMatchesThePublishedTableAcrossACenturyAndAHalf() {
        let o = Oracles.require("ayanamsa-lahiri-epochs")
        for year in [1900, 1950, 2000, 2025, 2050] {
            let got = Ayanamsa.lahiri.value(at: jan1(year))
            let expected = o.values[String(year)]!
            let arcsec = (got - expected) * 3600
            // Built first: Swift Testing's message is a `Comment`, and a `+` concatenation of
            // string literals does not coerce to one.
            let detail = "Lahiri \(year): \(String(format: "%.6f", got))° vs published \(String(format: "%.6f", expected))° — off by \(String(format: "%.1f", arcsec))\""
            #expect(o.matches(String(year), got), "\(detail)")
        }
    }

    /// Pins the derivative directly. The five-epoch series above could in principle be satisfied by
    /// a model that is wrong between the sampled dates; this cannot.
    @Test func theAyanamsaGrowsAtThePrecessionRate() {
        let o = Oracles.require("ayanamsa-precession-rate")
        let span = Double(2000 - 1900)
        let rate = (Ayanamsa.lahiri.value(at: jan1(2000))
                    - Ayanamsa.lahiri.value(at: jan1(1900))) * 3600 / span
        #expect(o.matches("arcsecPerYear", rate),
                "measured \(String(format: "%.2f", rate))″/yr")
    }

    /// The failure this whole series exists to catch, asserted as a property rather than trusted:
    /// the value at 1900 must differ from the value today by well over a degree. A constant passes
    /// every single-epoch test and fails this by two orders of magnitude.
    @Test func aConstantAyanamsaCouldNotPass() {
        let then = Ayanamsa.lahiri.value(at: jan1(1900))
        let now = Ayanamsa.lahiri.value(at: jan1(2025))
        #expect(now - then > 1.2, "125 years of precession is ~1.74°, got \(now - then)°")
    }

    // MARK: - Fagan–Bradley's defining anchor

    @Test func faganBradleyMatchesItsDefinitionAt1950() {
        let o = Oracles.require("ayanamsa-fagan-bradley-1950")
        let got = Ayanamsa.faganBradley.value(at: jan1(1950))
        #expect(o.matches("degrees", got),
                "Fagan–Bradley 1950.0: \(String(format: "%.6f", got))°")
    }

    // MARK: - The systems must actually differ

    /// Copy-pasting one system's implementation into another passes every test above. This is what
    /// catches it — and it is not hypothetical, because three of the four systems here are modelled
    /// as offsets from the same base.
    @Test func theFourSystemsDisagreeByTheirDocumentedAmounts() {
        let o = Oracles.require("ayanamsa-system-differences")
        let d = jan1(2026)
        let lahiri = Ayanamsa.lahiri.value(at: d)
        for (system, key) in [(Ayanamsa.krishnamurti, "krishnamurti"),
                              (Ayanamsa.raman, "raman"),
                              (Ayanamsa.faganBradley, "faganBradley")] {
            let gap = system.value(at: d) - lahiri
            #expect(o.matches(key, gap),
                    "\(system.displayName) − Lahiri = \(String(format: "%.4f", gap))°")
        }
        // …and no two systems may be identical, whatever the tolerances allow.
        let values = Ayanamsa.allCases.map { $0.value(at: d) }
        #expect(Set(values.map { Int($0 * 1e6) }).count == Ayanamsa.allCases.count,
                "two ayanamsa systems returned the same value")
    }

    // MARK: - Applying the frame

    @Test func theRoundTripIsExact() {
        let d = jan1(2026)
        for system in Ayanamsa.allCases {
            for lon in stride(from: 0.0, to: 360.0, by: 17.0) {
                let back = system.tropical(fromSidereal: system.sidereal(fromTropical: lon, at: d), at: d)
                #expect(abs(AstroMath.norm180(back - lon)) < 1e-9,
                        "\(system.displayName) round trip at \(lon)°")
            }
        }
    }

    /// The check that proves the shift actually *reaches* something, rather than being applied at
    /// render time only: a body can change **sign**, not merely degree, and any consumer reading
    /// `position(of:at:)` must see that.
    ///
    /// The boundary is derived from the ayanamsa rather than hardcoded. The function documentation
    /// gives "24°30′ tropical Aries lands in Pisces" as the example, and that is not true today —
    /// 24°30′ minus a ~24°13′ ayanamsa is 0°17′ Aries, still Aries by seventeen arcminutes. It
    /// becomes true around 2044, when the ayanamsa passes 24°30′. A test written against that
    /// literal degree would pass then and fail now for entirely the wrong reason; deriving it means
    /// the assertion holds in any year.
    @Test func aBodyJustBelowTheAyanamsaFallsBackASign() {
        for year in [1950, 2026, 2100] {
            let d = jan1(year)
            let ayan = Ayanamsa.lahiri.value(at: d)

            // Half a degree below the offset: tropical Aries, sidereal Pisces.
            let below = ayan - 0.5
            #expect(ZodiacSign.from(longitude: below) == .aries)
            let sidBelow = Ayanamsa.lahiri.sidereal(fromTropical: below, at: d)
            #expect(ZodiacSign.from(longitude: sidBelow) == .pisces,
                    "\(year): \(String(format: "%.2f", below))° tropical → \(String(format: "%.2f", sidBelow))° sidereal")

            // Half a degree above it: Aries in both frames, so the shift is not a blanket rename.
            let above = ayan + 0.5
            #expect(ZodiacSign.from(longitude: above) == .aries)
            #expect(ZodiacSign.from(longitude: Ayanamsa.lahiri.sidereal(fromTropical: above, at: d)) == .aries)
        }
    }

    /// The shift must travel with the body into everything downstream, which is what
    /// `position(of:at:)` exists for. Compared against the tropical engine directly.
    @Test func siderealPositionsCarryTheShiftNotJustTheDisplay() {
        let d = jan1(2026)
        let ayan = Ayanamsa.lahiri.value(at: d)
        for body in CelestialBody.allCases {
            let tropical = Ephemeris.longitude(of: body, at: d)
            let sid = Ayanamsa.lahiri.position(of: body, at: d)
            #expect(abs(AstroMath.norm180(sid.longitude - (tropical - ayan))) < 1e-9,
                    "\(body.name) sidereal longitude does not carry the offset")
            // Speed is frame-independent — the ayanamsa is a rotation, not a rescaling.
            #expect(sid.speed == Ephemeris.dailyMotion(of: body, at: d))
        }
        #expect(Ayanamsa.lahiri.positions(at: d).count == CelestialBody.allCases.count)
    }

    /// Sidereal *zodiac* and sidereal *time* share a word and nothing else. Asserted because the
    /// function documentation lists confusing them as a failure mode, and both live in this Kit.
    @Test func theSiderealZodiacIsUnrelatedToSiderealTime() {
        let d = jan1(2026)
        let ayan = Ayanamsa.lahiri.value(at: d)
        let lst = SiderealTime.localMeanSiderealTime(at: d, longitude: 0)
        #expect(abs(ayan - lst) > 1, "these are different quantities that happen to share a name")
        #expect((23.0...25.0).contains(ayan), "an ayanamsa in 2026 is ~24°, not an hour angle")
    }
}
