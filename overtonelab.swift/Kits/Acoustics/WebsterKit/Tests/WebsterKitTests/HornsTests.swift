import Testing
import Foundation
@testable import WebsterKit

// Oracle = published Webster horn / Helmholtz formulas + invariants. Model-caveat app (Hornresp cross-check = human step).
@Suite("Horns & Helmholtz")
struct HornsTests {
    @Test func helmholtzWorkedValue() {
        // A=0.0003 m², V=0.0005 m³, L=0.05 m → f = (343/2π)·√(0.0003/(0.0005·0.05)) ≈ 189.1 Hz.
        let f = Horns.helmholtzHz(neckAreaM2: 0.0003, cavityVolumeM3: 0.0005, neckLengthM: 0.05)
        #expect(abs(f - 189.1) < 0.5)
    }
    @Test func expHornCutoffAndFlare() {
        // Flare m = 4π·fc/c ; check round-trip for fc = 100 Hz.
        let m = 4 * Double.pi * 100 / 343
        #expect(abs(Horns.expHornCutoffHz(flareConstant: m) - 100) < 1e-9)
        // area doubles after x = ln2/m
        #expect(abs(Horns.expHornArea(mouthOrThroatA0: 1, flareConstant: m, x: log(2) / m) - 2) < 1e-9)
    }
}
