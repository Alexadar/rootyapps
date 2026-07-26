import Testing
import Foundation
@testable import PitchKit

/// Oracles (external, cited):
///  • ISO 16 / MIDI tuning: A4 = 440 Hz = MIDI 69; f = 440·2^((n−69)/12).
///  • Scientific pitch: C4 (middle C) ≈ 261.626 Hz, A0 = 27.5 Hz.
///  • Cents: 1200·log₂(ratio). Doppler: f′ = f·(c+v_o)/(c−v_s).
@Suite struct PitchOracle {

    @Test func noteToFrequency() {
        #expect(abs(Pitch.noteToHz(midi: 69) - 440) < 1e-9)          // A4
        #expect(abs(Pitch.noteToHz(midi: 60) - 261.6256) < 1e-3)     // C4
        #expect(abs(Pitch.noteToHz(midi: 21) - 27.5) < 1e-9)         // A0
        #expect(abs(Pitch.noteToHz(midi: 81) - 880) < 1e-9)          // A5 (octave up)
        // round-trip
        #expect(abs(Pitch.hzToNote(440) - 69) < 1e-9)
        #expect(Pitch.noteName(midi: 60) == "C4")
        #expect(Pitch.noteName(midi: 69) == "A4")
    }

    @Test func wavelengthAndCents() {
        #expect(abs(Pitch.wavelengthM(hz: 440) - 0.7795) < 1e-3)     // 343/440
        #expect(abs(Pitch.centsBetween(440, 880) - 1200) < 1e-9)     // octave
        #expect(abs(Pitch.centsBetween(200, 300) - 701.955) < 1e-3)  // just fifth 3:2
    }

    @Test func harmonicsAndBeats() {
        #expect(abs(Harmonics.harmonicHz(fundamental: 100, n: 3) - 300) < 1e-9)
        // 7th harmonic is ~31 cents flat of 12-TET.
        #expect(abs(Harmonics.centsFromET(n: 7) - (-31.17)) < 0.1)
        #expect(abs(Beats.beatHz(440, 443) - 3) < 1e-9)              // 3 Hz beating
    }

    @Test func doppler() {
        // Source approaching at 30 m/s, c = 343: 1000 Hz → 1095.8 Hz.
        #expect(abs(Doppler.observedHz(source: 1000, vSource: 30) - 1095.847) < 0.01)
        // Receding source → lower pitch.
        #expect(Doppler.observedHz(source: 1000, vSource: -30) < 1000)
    }

    @Test func guards() {
        #expect(Pitch.wavelengthM(hz: 0) == 0)
        #expect(Pitch.hzToNote(0) == 0)
    }
}
