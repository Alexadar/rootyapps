import Testing
import Foundation
@testable import FormantKit

/// Oracles (external, cited):
///  • Quarter-wave tube: neutral vocal tract L = 17.5 cm, c ≈ 350 m/s → F1/F2/F3 ≈ 500/1500/2500 Hz
///    (the classic "schwa" formants).
///  • Vowel formant means: Peterson & Barney (1952), JASA — men's averages.
@Suite struct FormantOracle {

    @Test func neutralTractFormants() {
        #expect(abs(Formants.formantHz(tractLengthM: 0.175, n: 1) - 500) < 1)
        #expect(abs(Formants.formantHz(tractLengthM: 0.175, n: 2) - 1500) < 1)
        #expect(abs(Formants.formantHz(tractLengthM: 0.175, n: 3) - 2500) < 1)
        // Odd-harmonic spacing: F2/F1 = 3, F3/F1 = 5.
        let f1 = Formants.formantHz(tractLengthM: 0.175, n: 1)
        #expect(abs(Formants.formantHz(tractLengthM: 0.175, n: 2) / f1 - 3) < 1e-9)
    }

    @Test func lengthScaling() {
        // A shorter tract (child) raises formants; half the length doubles them.
        #expect(abs(Formants.scaled(500, fromLengthM: 0.175, toLengthM: 0.0875) - 1000) < 1e-9)
        #expect(Formants.formantHz(tractLengthM: 0.15, n: 1) > Formants.formantHz(tractLengthM: 0.20, n: 1))
    }

    @Test func vowelTable() {
        // Peterson-Barney anchors.
        let a = Formants.vowels.first { $0.ipa == "ɑ" }!
        #expect(a.f1 == 730 && a.f2 == 1090)
        let i = Formants.vowels.first { $0.ipa == "i" }!
        #expect(i.f1 == 270 && i.f2 == 2290)
        #expect(Formants.vowels.count == 10)
    }

    @Test func guards() {
        #expect(Formants.formantHz(tractLengthM: 0, n: 1) == 0)
    }
}
