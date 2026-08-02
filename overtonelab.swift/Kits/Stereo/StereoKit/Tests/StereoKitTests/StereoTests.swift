import Testing
import Foundation
@testable import StereoKit

// Oracle = exact first-order polar geometry (ΔL, ΔT) + the published stereo recording angles of the
// standard near-coincident arrays: ORTF 96°, NOS 81°, DIN 101° (Sengpiel; DPA "Microphone
// University"; Williams, "The Stereophonic Zoom", AES 1984). The SRA model's two trading constants
// are calibrated to those rigs; here we validate it reproduces them within ±2°.
@Suite("Stereo / SRA")
struct StereoTests {
    // MARK: exact geometry
    @Test func polarWorkedValues() {
        #expect(abs(Stereo.polar(.cardioid, degrees: 0) - 1) < 1e-12)
        #expect(abs(Stereo.polar(.cardioid, degrees: 90) - 0.5) < 1e-12)
        #expect(abs(Stereo.polar(.cardioid, degrees: 180) - 0) < 1e-12)
        #expect(abs(Stereo.polar(.figure8, degrees: 0) - 1) < 1e-12)
        #expect(abs(Stereo.polar(.figure8, degrees: 90) - 0) < 1e-12)
        // Super-cardioid rear null where cos θ = −a/(1−a) = −0.577 → θ ≈ 125.26°.
        #expect(abs(Stereo.polar(.supercardioid, degrees: 125.26)) < 2e-3)
    }

    @Test func levelDifferenceWorkedValue() {
        // Cardioids at 110° (φ=55°), source 30° off-centre:
        // 20·log10(P(−25°)/P(85°)) = 20·log10(0.953154/0.543578) = 4.874 dB.
        #expect(abs(Stereo.levelDifferenceDB(sourceDeg: 30, micAngleDeg: 110, pattern: .cardioid) - 4.874) < 1e-2)
        #expect(Stereo.levelDifferenceDB(sourceDeg: 0, micAngleDeg: 110, pattern: .cardioid) == 0)   // centre = 0
    }

    @Test func timeDifferenceWorkedValue() {
        // 17 cm at 90°: 0.17/343 = 495.63 µs; at 30° it scales by sin30 = 0.5.
        #expect(abs(Stereo.timeDifferenceUs(sourceDeg: 90, spacingCm: 17) - 495.63) < 0.1)
        #expect(abs(Stereo.timeDifferenceUs(sourceDeg: 30, spacingCm: 17) - 247.81) < 0.1)
        #expect(Stereo.timeDifferenceUs(sourceDeg: 0, spacingCm: 17) == 0)                            // coincident-angle = 0
    }

    // MARK: SRA validated against the published standard rigs
    @Test func recordingAngleReproducesStandards() {
        #expect(abs(Stereo.recordingAngleDeg(micAngleDeg: 110, spacingCm: 17, pattern: .cardioid) - 96) < 2)   // ORTF
        #expect(abs(Stereo.recordingAngleDeg(micAngleDeg: 90,  spacingCm: 30, pattern: .cardioid) - 81) < 2)   // NOS
        #expect(abs(Stereo.recordingAngleDeg(micAngleDeg: 90,  spacingCm: 20, pattern: .cardioid) - 101) < 2)  // DIN
    }

    @Test func nearestPresetIdentifiesRigs() {
        #expect(Stereo.nearestPreset(micAngleDeg: 110, spacingCm: 17, pattern: .cardioid).name == "ORTF")
        #expect(Stereo.nearestPreset(micAngleDeg: 90,  spacingCm: 30, pattern: .cardioid).name == "NOS")
        #expect(Stereo.nearestPreset(micAngleDeg: 90,  spacingCm: 0,  pattern: .figure8).name == "Blumlein")
    }

    @Test func sraSanity() {
        // Less spacing (at the same angle) → less time cue → the image fills later → WIDER SRA.
        let tight = Stereo.recordingAngleDeg(micAngleDeg: 90, spacingCm: 10, pattern: .cardioid)
        let wide  = Stereo.recordingAngleDeg(micAngleDeg: 90, spacingCm: 40, pattern: .cardioid)
        #expect(tight > wide)
        // Coincident (spacing 0) depends only on ΔL, and is finite and positive.
        let xy = Stereo.recordingAngleDeg(micAngleDeg: 90, spacingCm: 0, pattern: .cardioid)
        #expect(xy > 0 && xy <= 180)
    }
}
