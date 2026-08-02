import Testing
import Foundation
@testable import SabineKit

// Oracle = published Sabine/Eyring formulas (the field authority) + invariants. Model-caveat app.
@Suite("Room acoustics")
struct AcousticsTests {
    @Test func sabineWorkedValue() {
        // V=1000 m³, A=120 sabins → RT60 = 0.161·1000/120 = 1.3417 s (Sabine's equation).
        #expect(abs(Acoustics.sabineRT60(volumeM3: 1000, absorptionSabins: 120) - 1.34167) < 1e-4)
    }
    @Test func eyringApproachesSabineForLowAbsorption() {
        // For small ā, −ln(1−ā) ≈ ā, so Eyring ≈ Sabine.
        let V = 500.0, S = 400.0, a = 0.05
        let sab = Acoustics.sabineRT60(volumeM3: V, absorptionSabins: S * a)
        let eyr = Acoustics.eyringRT60(volumeM3: V, surfaceM2: S, avgAbsorption: a)
        #expect(abs(sab - eyr) / sab < 0.03)
    }
    @Test func schroederAndModes() {
        #expect(abs(Acoustics.schroederHz(rt60: 1.0, volumeM3: 100) - 200) < 1e-9)   // 2000·√(1/100)
        #expect(abs(Acoustics.axialModeHz(lengthM: 5, order: 1) - 34.3) < 1e-9)       // c/(2·5)
    }
}
