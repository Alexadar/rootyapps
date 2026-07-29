import Testing
import Foundation
import EphemerisKit
@testable import Ephemeris

/// UI value tests — verify the *exact figures* the Positions/Aspects views render
/// (zodiac sign, degree-minute string, retrograde flag, aspect orb) for known
/// moments. Cross-checked against JPL Horizons references and real 2026 sky events,
/// so these guard the ViewModel → UI value pipeline, not merely that "something"
/// non-empty is produced.
@Suite("Position values")
@MainActor
struct PositionValuesTests {

    /// A view model whose `instant` equals the given absolute UTC moment.
    /// `instant` reads `date`'s wall-clock in the *device* zone, then reforms it in
    /// `timeZone` — so pinning `timeZone` to the device zone makes `instant` an
    /// identity on `date`, and every assertion below is machine-independent.
    private func vm(at t: Date) -> ChartViewModel {
        let vm = ChartViewModel()
        vm.timeZone = .current
        vm.date = t
        vm.recompute()
        return vm
    }

    private func pos(_ vm: ChartViewModel, _ body: CelestialBody) -> BodyPosition {
        vm.positions.first { $0.body == body }!
    }

    private func parseDegMin(_ s: String) -> Double {   // "13° 20′" → 13.333…
        let parts = s.replacingOccurrences(of: "′", with: "")
                     .replacingOccurrences(of: "°", with: "")
                     .split(separator: " ")
        let d = Double(parts[0]) ?? 0, m = Double(parts.count > 1 ? parts[1] : "0") ?? 0
        return d + m / 60
    }

    // MARK: Horizons cross-check, through the ViewModel that feeds the UI

    /// The longitudes (and derived signs) the Positions view shows must match JPL
    /// Horizons (geocentric ObsEcLon) for 2026-06-21 00:00 UTC — the same references
    /// the engine suite validates, re-asserted at the ViewModel layer.
    @Test func positionsMatchHorizons() {
        let v = vm(at: utc(2026, 6, 21, 0, 0))
        // body, Horizons longitude, expected sign, tolerance.
        // 0.1° (6′) — matched to the Kit's measured accuracy, not the old 0.25–1.0° guesses.
        // See EphemerisKit's AccuracyTests/Oracles for the 3,940-sample Horizons sweep.
        let tol = 0.1
        let refs: [(CelestialBody, Double, ZodiacSign, Double)] = [
            (.sun,      89.6656, .gemini, tol),
            (.mercury, 113.3888, .cancer, tol),
            (.venus,   128.7542, .leo,    tol),
            (.mars,     54.3946, .taurus, tol),
            (.jupiter, 118.0494, .cancer, tol),
            (.saturn,   13.6804, .aries,  tol),
        ]
        for (body, lon, sign, tol) in refs {
            let p = pos(v, body)
            #expect(abs(AstroMath.norm180(p.longitude - lon)) < tol,
                    "\(body) lon \(p.longitude) vs Horizons \(lon)")
            #expect(p.sign == sign, "\(body) sign \(p.sign) expected \(sign)")
        }
    }

    /// At the June-2026 solstice noon the Sun stands at the very start of Cancer.
    @Test func sunAtSolsticeIsZeroCancer() {
        let p = pos(vm(at: utc(2026, 6, 21, 12, 0)), .sun)
        #expect(p.sign == .cancer)
        #expect(p.degreesInSign >= 0 && p.degreesInSign < 0.3)
        #expect(p.degMinString.hasPrefix("0° "))
    }

    /// Real 2026 sky, verified against the marketing capture moment
    /// (2026-07-05 08:00 UTC = 01:00 America/Los_Angeles):
    ///  • Sun in Cancer (two weeks past solstice)
    ///  • Jupiter freshly in Leo (ingress ~2026-06-30)
    ///  • Mercury retrograde in Cancer (retrograde window ~Jun 29 – Jul 23 2026)
    ///  • Saturn in Aries, near its mid-July retrograde station (near-stationary)
    @Test func julyFifthSkyMatchesReality() {
        let v = vm(at: utc(2026, 7, 5, 8, 0))
        #expect(pos(v, .sun).sign == .cancer)
        #expect(pos(v, .jupiter).sign == .leo)
        #expect(pos(v, .mercury).sign == .cancer)
        #expect(pos(v, .mercury).retrograde)
        #expect(pos(v, .saturn).sign == .aries)
        #expect(abs(pos(v, .saturn).speed) < 0.1)      // slowing to station
    }

    // MARK: Rendered-field consistency

    /// Every Positions row's rendered fields are internally consistent with its
    /// longitude: sign, degrees-in-sign range, retrograde flag, and the formatted
    /// "d° mm′" string all agree.
    @Test func rowFieldsAreConsistent() {
        let v = vm(at: utc(2026, 3, 15, 0, 0))
        #expect(v.positions.count == CelestialBody.allCases.count)
        for p in v.positions {
            #expect(p.sign == ZodiacSign.from(longitude: p.longitude))
            #expect(p.degreesInSign >= 0 && p.degreesInSign < 30)
            #expect(p.retrograde == (p.speed < 0))
            #expect(abs(parseDegMin(p.degMinString) - p.degreesInSign) < 1.0 / 60 + 1e-6)
        }
    }

    /// The "d° mm′" formatter: minute rounding, the 59.7′→next-degree carry, and the
    /// sign-wrap that keeps degrees in 0–29° (never spilling into the next sign).
    @Test func degMinFormatter() {
        func s(_ lon: Double) -> String { BodyPosition(body: .sun, longitude: lon, speed: 1).degMinString }
        #expect(s(103.0 + 20.0 / 60) == "13° 20′")   // 13°20′ Cancer
        #expect(s(0.0) == "0° 00′")                  // 0°00′ Aries
        #expect(s(10.0 + 59.7 / 60) == "11° 00′")    // carries to the next degree
        #expect(s(59.99) == "29° 59′")               // late Taurus, no spill into Gemini
    }

    // MARK: Aspects view

    /// Each aspect the Aspects view lists carries a correct, self-consistent orb:
    /// `orb == |separation − exact angle|` and within the active orb allowance.
    @Test func aspectOrbsAreConsistent() {
        let v = vm(at: utc(2026, 6, 21, 0, 0))
        #expect(!v.aspects.isEmpty)
        for a in v.aspects {
            let sep = AstroMath.separation(pos(v, a.a).longitude, pos(v, a.b).longitude)
            #expect(abs(abs(sep - a.type.angle) - a.orb) < 1e-6)
            #expect(a.orb <= a.type.baseOrb * v.orbFactor + 1e-6)
        }
    }
}
