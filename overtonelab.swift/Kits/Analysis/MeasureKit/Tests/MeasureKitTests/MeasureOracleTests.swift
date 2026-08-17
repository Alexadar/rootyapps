import Testing
import Foundation
@testable import MeasureKit

/// Oracles (external, cited):
///  • Tempo convention: BPM = 60 / beat period in seconds. A 120 BPM click has beats 0.5 s apart.
///  • ITU-R BS.1770 loudness is reported in LUFS; a −23 LUFS programme reads −23 (EBU R128 target).
///  • MIDI note numbering (MIDI 1.0): C4 = 60, semitone = 1.
///
/// ## The boundary is the whole contract
///
/// This suite asserts only what has ground truth: a known click reads its BPM, a known level reads
/// its level, a known tonic reads its note. **Section labels and pace are passed through untested by
/// design** (DESIGN_GUIDELINES §10) — they have no external oracle, and asserting them would freeze
/// one implementation's opinion into a test that looks authoritative and is not.
@Suite struct MeasureOracle {

    // MARK: - BPM

    @Test func aTwoBeatClickReadsItsTempo() {
        // 120 BPM = one beat every 0.5 s.
        #expect(Measure.bpm(beatTimes: [0, 0.5]).map { abs($0 - 120) < 1e-9 } == true)
        #expect(Measure.bpm(beatTimes: [0, 0.5, 1.0, 1.5, 2.0]).map { abs($0 - 120) < 1e-9 } == true)
        // 60 BPM and 90 BPM, to prove it is not returning a constant.
        #expect(Measure.bpm(beatTimes: [0, 1.0, 2.0]).map { abs($0 - 60) < 1e-9 } == true)
        #expect(Measure.bpm(beatTimes: [0, 2.0 / 3.0]).map { abs($0 - 90) < 1e-9 } == true)
    }

    /// ⚠ THE RULE THAT KEEPS THE SCREEN HONEST. Fewer than two beats is not a slow tempo, it is no
    /// tempo — and a 0 would render as a real reading.
    @Test func fewerThanTwoBeatsIsNilAndNeverZero() {
        #expect(Measure.bpm(beatTimes: []) == nil)
        #expect(Measure.bpm(beatTimes: [1.234]) == nil)
        // Two identical stamps are one beat reported twice: still not a tempo.
        #expect(Measure.bpm(beatTimes: [2.0, 2.0]) == nil)
    }

    @Test func beatOrderDoesNotMatterAndOneStrayOnsetDoesNot() {
        let inOrder = Measure.bpm(beatTimes: [0, 0.5, 1.0, 1.5])
        let shuffled = Measure.bpm(beatTimes: [1.5, 0, 1.0, 0.5])
        #expect(inOrder == shuffled)
        // A single doubled onset (an extra beat halfway) must not halve the answer: the median
        // interval is still 0.5 s. A mean would drift here, which is why this is a median.
        let withStray = Measure.bpm(beatTimes: [0, 0.5, 0.75, 1.0, 1.5, 2.0])
        #expect(withStray.map { abs($0 - 120) < 1e-9 } == true)
    }

    // MARK: - Bars

    @Test func barsAreWholeBarsOnly() {
        #expect(Measure.barCount(beatCount: 16, beatsPerBar: 4) == 4)
        #expect(Measure.barCount(beatCount: 17, beatsPerBar: 4) == 4)   // a partial bar is not a bar
        #expect(Measure.barCount(beatCount: 18, beatsPerBar: 3) == 6)
        #expect(Measure.barCount(beatCount: 0, beatsPerBar: 4) == nil)
        #expect(Measure.barCount(beatCount: 8, beatsPerBar: 0) == nil)
    }

    // MARK: - Loudness

    @Test func aMinus23LUFSProgrammeReadsMinus23() {
        #expect(Measure.integratedLUFS(-23).map { abs($0 + 23) < 1e-12 } == true)
        #expect(Measure.integratedLUFS(-14).map { abs($0 + 14) < 1e-12 } == true)
        #expect(Measure.integratedLUFS(nil) == nil)
        // Silence measures as -inf, which is not a reading.
        #expect(Measure.integratedLUFS(-.infinity) == nil)
        #expect(Measure.integratedLUFS(.nan) == nil)
    }

    /// Peaks above 0 dBFS are real and must survive: inter-sample overs are the thing an engineer
    /// opened this for. Clamping would hide the defect being measured.
    @Test func peaksAboveZeroSurvive() {
        #expect(Measure.peakDB(0.8).map { abs($0 - 0.8) < 1e-12 } == true)
        #expect(Measure.peakDB(-1.2).map { abs($0 + 1.2) < 1e-12 } == true)
        #expect(Measure.peakDB(nil) == nil)
        #expect(Measure.peakDB(.infinity) == nil)
    }

    // MARK: - Key

    @Test func keyNamesAndTonicNotes() {
        #expect(Measure.keyName(tonic: "F#", isMinor: true) == "F# minor")
        #expect(Measure.keyName(tonic: "C", isMinor: false) == "C major")
        #expect(Measure.keyName(tonic: "A", isMinor: nil) == "A")       // mode unknown, tonic known
        #expect(Measure.keyName(tonic: nil, isMinor: false) == nil)
        #expect(Measure.keyName(tonic: "H", isMinor: false) == nil)     // not a pitch class here
    }

    @Test func tonicMapsToMIDIWithC4At60() {
        #expect(Measure.tonicMIDI(tonic: "C") == 60)                    // MIDI 1.0: C4 = 60
        #expect(Measure.tonicMIDI(tonic: "A") == 69)                    // A4 = 69 = 440 Hz
        #expect(Measure.tonicMIDI(tonic: "C", octave: 3) == 48)
        #expect(Measure.tonicMIDI(tonic: nil) == nil)
    }
}
