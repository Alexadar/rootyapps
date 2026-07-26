import Testing
import Foundation
@testable import TimingKit

/// Oracles (external, cited):
///  • Musical time convention: quarter note = one beat; ms = 60000/BPM.
///  • Sample clock: samples = seconds · sampleRate.
///  • Comb filtering: first null at f = 1/(2·delay).
///  • SMPTE ST 12-1 timecode, incl. 29.97 drop-frame (drop 2 frames/min except every 10th).
@Suite struct TimingOracle {

    @Test func tempoNoteLengths() {
        #expect(abs(Tempo.beatMs(bpm: 120) - 500) < 1e-9)                    // ¼ @120 = 500 ms
        #expect(abs(Tempo.noteMs(bpm: 120, division: 4) - 500) < 1e-9)
        #expect(abs(Tempo.noteMs(bpm: 120, division: 8) - 250) < 1e-9)       // ⅛
        #expect(abs(Tempo.noteMs(bpm: 120, division: 4, dotted: true) - 750) < 1e-9)
        #expect(abs(Tempo.noteMs(bpm: 120, division: 4, triplet: true) - 333.3333) < 1e-3)
        #expect(abs(Tempo.barMs(bpm: 120, beats: 4, beatUnit: 4) - 2000) < 1e-9)   // 4/4 bar
        #expect(abs(Tempo.bpm(beatMs: 500) - 120) < 1e-9)                    // round-trip
    }

    @Test func samplesAndVarispeed() {
        #expect(abs(Tempo.msToSamples(ms: 1000, sampleRate: 48000) - 48000) < 1e-9)
        #expect(abs(Tempo.samplesToMs(samples: 44100, sampleRate: 44100) - 1000) < 1e-9)
        #expect(abs(Tempo.varispeedSemitones(rateRatio: 2) - 12) < 1e-9)     // 2× = +12 st
        #expect(abs(Tempo.rateRatio(semitones: 12) - 2) < 1e-9)
    }

    @Test func delayTimes() {
        #expect(abs(Delay.noteDelayMs(bpm: 120, division: 8) - 250) < 1e-9)
        #expect(abs(Delay.rateHz(ms: 250) - 4) < 1e-9)                       // 250 ms = 4 Hz
        #expect(abs(Delay.distanceMs(meters: 3.43) - 10) < 1e-6)            // 3.43 m ≈ 10 ms
        #expect(abs(Delay.metersForMs(10) - 3.43) < 1e-6)                   // round-trip
        #expect(abs(Delay.combFirstNullHz(delayMs: 1) - 500) < 1e-9)       // 1 ms → 500 Hz
    }

    @Test func timecodeNonDrop() {
        // 1 hour: 30 fps = 108000, 25 fps = 90000, 24 fps = 86400.
        #expect(SMPTE.frameCount(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0), fps: 30) == 108000)
        #expect(SMPTE.frameCount(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0), fps: 25) == 90000)
        #expect(SMPTE.frameCount(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0), fps: 24) == 86400)
        // round-trip
        let tc = SMPTE.timecode(frameCount: 90000, fps: 25)
        #expect(tc == Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0))
    }

    @Test func timecodeDropFrame() {
        // SMPTE 29.97 DF: label 01:00:00:00 lands at real frame 107892 (108000 − 108 dropped).
        let n = SMPTE.frameCount(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0), fps: 30, dropFrame: true)
        #expect(n == 107892)
        // round-trip back to the label.
        #expect(SMPTE.timecode(frameCount: 107892, fps: 30, dropFrame: true)
                == Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0))
        // The first drop happens at 00:01:00 — frames ;00 and ;01 are skipped.
        let oneMin = SMPTE.timecode(frameCount: 1800, fps: 30, dropFrame: true)
        #expect(oneMin == Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2))
    }

    @Test func guards() {
        #expect(Tempo.noteMs(bpm: 0, division: 4) == 0)
        #expect(Delay.combFirstNullHz(delayMs: 0) == 0)
    }
}
