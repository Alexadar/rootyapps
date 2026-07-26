import Testing
import Foundation
@testable import MersenneKit

// Oracle = published physical law (Mersenne) + documented luthier geometry (12-TET frets,
// the historical "rule of eighteen" divisor 17.817). Identity/invariant + one cited constant.
@Suite("Strings — Mersenne's law & fret geometry")
struct StringsTests {
    @Test func octaveAt12thFret() {
        let L = 25.5
        #expect(abs(Strings.fretDistance(scale: L, fret: 12) - L / 2) < 1e-12)   // 12th fret halves the string
        #expect(abs(Strings.fretDistance(scale: L, fret: 24) - 0.75 * L) < 1e-12)
    }
    @Test func ruleOfEighteen() {
        // First fret sits at L/17.817 (the historical "rule of 18" — cited constant).
        let L = 25.5
        #expect(abs(Strings.fretDistance(scale: L, fret: 1) - L / 17.817) < 1e-3)
    }
    @Test func mersenneRoundTrip() {
        let f = 220.0, L = 0.65, mu = 0.005
        let T = Strings.tensionN(frequencyHz: f, lengthM: L, linearDensityKgPerM: mu)
        #expect(abs(Strings.frequencyHz(tensionN: T, lengthM: L, linearDensityKgPerM: mu) - f) < 1e-9)
    }
    @Test func octaveNeedsQuadrupleTension() {
        // T ∝ f²  ⇒  raising pitch an octave needs 4× the tension.
        let L = 0.65, mu = 0.005
        let t1 = Strings.tensionN(frequencyHz: 110, lengthM: L, linearDensityKgPerM: mu)
        let t2 = Strings.tensionN(frequencyHz: 220, lengthM: L, linearDensityKgPerM: mu)
        #expect(abs(t2 / t1 - 4) < 1e-9)
    }
}
