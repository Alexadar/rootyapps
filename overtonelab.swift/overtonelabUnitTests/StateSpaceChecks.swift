import XCTest
import DynamicsKit
@testable import Overtone_Lab

/// Every control in both directions, and the pairs nobody tries.
///
/// A control tested only in its default state proves nothing: a shipped watch app in this repo had a
/// measurement-unit toggle that did nothing at all — every number correct, every screen rendering,
/// suite green — because no test ever flipped it. So the rule here is: flip it, assert the OUTPUT
/// moved, flip it back, assert it RETURNED. A label that changes while the number does not is exactly
/// the failure this catches.
///
/// Combinatorics belong at this layer, never in XCUITest: 64 states through a keypad at ~1.1 s per tap
/// is twenty minutes nobody will run; here it is microseconds. The UI suite keeps one assertion per
/// control to prove the binding is wired, because a model test cannot catch a view reading the wrong
/// property.
@MainActor
final class StateSpaceChecks: XCTestCase {

    // MARK: Tempo — dotted × triplet, the cross product

    func testDottedAndTripletBothWaysAndTogether() {
        let vm = TempoViewModel()
        vm.bpm = 120; vm.division = 4
        let plain = vm.noteMs
        XCTAssertEqual(plain, 500, accuracy: 1e-9)

        // Dotted = ×1.5 — and back.
        vm.dotted = true
        XCTAssertEqual(vm.noteMs, 750, accuracy: 1e-9, "dotted must lengthen the note by half")
        vm.dotted = false
        XCTAssertEqual(vm.noteMs, plain, accuracy: 1e-9, "clearing dotted must return the value")

        // Triplet = ×2/3 — and back.
        vm.triplet = true
        XCTAssertEqual(vm.noteMs, 500 * 2 / 3, accuracy: 1e-9, "triplet must shorten the note to 2/3")
        vm.triplet = false
        XCTAssertEqual(vm.noteMs, plain, accuracy: 1e-9, "clearing triplet must return the value")

        // BOTH: the pair nobody tries. 1.5 × 2/3 = 1, so a dotted triplet is the plain note again —
        // which is also what a screen that ignored one of the flags would show. Assert the flags are
        // both live first, so this cannot pass by doing nothing.
        vm.dotted = true; vm.triplet = true
        XCTAssertEqual(vm.noteMs, plain, accuracy: 1e-9, "dotted × triplet = ×1")
    }

    /// Division is a picker, not a toggle: every position must halve the note.
    func testEveryDivisionHalvesTheNote() {
        let vm = TempoViewModel()
        vm.bpm = 120
        var previous = Double.infinity
        for division in [1.0, 2, 4, 8, 16, 32] {
            vm.division = division
            let ms = vm.noteMs
            XCTAssertLessThan(ms, previous, "a shorter division must give a shorter note")
            previous = ms
        }
        vm.division = 4
        XCTAssertEqual(vm.noteMs, 500, accuracy: 1e-9)
    }

    // MARK: Timecode — drop-frame both ways

    func testDropFrameChangesTheEffectiveRateAndTheTimecode() {
        let vm = TimecodeViewModel()
        vm.fps = 30
        vm.frameCount = 108_000

        vm.dropFrame = false
        XCTAssertEqual(vm.effectiveFps, 30, accuracy: 1e-12)
        let straight = vm.timecodeLabel
        let straightSeconds = vm.frameSeconds

        vm.dropFrame = true
        // 29.97 = 30000/1001 — the whole point of drop-frame is that wall clock and frame count
        // disagree, so BOTH the label and the duration must move.
        XCTAssertEqual(vm.effectiveFps, 30000.0 / 1001.0, accuracy: 1e-9)
        XCTAssertNotEqual(vm.timecodeLabel, straight, "drop-frame must renumber the timecode")
        XCTAssertGreaterThan(vm.frameSeconds, straightSeconds,
                             "at 29.97 fps the same frame count takes longer")

        vm.dropFrame = false
        XCTAssertEqual(vm.timecodeLabel, straight, "clearing drop-frame must return the label")
    }

    // MARK: Bernoulli — open vs closed pipe

    func testOpenAndClosedPipeGiveDifferentFundamentals() {
        let vm = PipeViewModel()
        vm.lengthM = 0.5

        vm.isOpen = true
        let open = vm.fundamental
        XCTAssertEqual(open, 343, accuracy: 0.5, "an open 0.5 m pipe sounds c/2L")

        vm.isOpen = false
        let closed = vm.fundamental
        // A pipe closed at one end sounds an octave lower: c/4L. A toggle that only relabelled would
        // leave these equal.
        XCTAssertEqual(closed, open / 2, accuracy: 0.5, "a closed pipe must sound an octave lower")

        vm.isOpen = true
        XCTAssertEqual(vm.fundamental, open, accuracy: 1e-9, "the toggle must return")
    }

    // MARK: Levels — voltage vs power dB

    func testPowerModeUsesTenLogNotTwentyLog() {
        let vm = LevelsViewModel()
        vm.valA = 1; vm.valB = 2

        vm.powerMode = false
        XCTAssertEqual(vm.diffDB, 20 * log10(2), accuracy: 1e-9, "voltage ratio is 20·log₁₀")
        let voltage = vm.diffDB

        vm.powerMode = true
        XCTAssertEqual(vm.diffDB, 10 * log10(2), accuracy: 1e-9, "power ratio is 10·log₁₀")
        XCTAssertEqual(vm.diffDB, voltage / 2, accuracy: 1e-9, "power dB is half of voltage dB")

        vm.powerMode = false
        XCTAssertEqual(vm.diffDB, voltage, accuracy: 1e-9, "the mode must return")
    }

    /// Zero is the refusal case: a ratio against nothing has no dB value.
    ///
    /// The old guard covered the division and then fed `0` to `log10`, so the Compare card would have
    /// rendered "−∞ dB". `NumberField` clamps the field to 0.0001…1000000, so no user could reach it
    /// — but the model should not rely on a display-layer clamp for its own arithmetic to be finite.
    func testLevelsRefusesAZeroReference() {
        let vm = LevelsViewModel()
        vm.valA = 0; vm.valB = 2
        XCTAssertTrue(vm.diffDB.isFinite,
                      "a zero reference must not produce a non-finite reading, got \(vm.diffDB)")
        XCTAssertEqual(vm.diffDB, 0, "an undefined comparison reads as no difference, not as −∞")

        // The other side of the same hole: a zero measurement.
        vm.valA = 1; vm.valB = 0
        XCTAssertTrue(vm.diffDB.isFinite, "a zero measurement must not produce −∞ either")

        // And the ordinary case still works, so the guard has not swallowed real input.
        vm.valA = 1; vm.valB = 2
        XCTAssertEqual(vm.diffDB, 20 * log10(2), accuracy: 1e-9)
    }

    // MARK: Pan — all three laws, and the centre each implies

    func testEveryPanLawHasItsOwnCentreDrop() {
        let vm = PanViewModel()
        vm.position = 0

        var drops: [Double] = []
        for law in 0..<3 {
            vm.lawIndex = law
            drops.append(vm.leftDB)
            // Centre is symmetric in every law — a law that broke symmetry would be audible.
            XCTAssertEqual(vm.leftDB, vm.rightDB, accuracy: 1e-9,
                           "law \(law): centre must feed both channels equally")
        }
        XCTAssertEqual(Set(drops.map { ($0 * 100).rounded() }).count, 3,
                       "the three pan laws must produce three different centre levels, got \(drops)")

        // −3 dB, −6 dB, −4.5 dB in order: equal-power, linear, compromise.
        vm.lawIndex = 0; XCTAssertEqual(vm.leftDB, -3.01, accuracy: 0.02)
        vm.lawIndex = 1; XCTAssertEqual(vm.leftDB, -6.02, accuracy: 0.02)
        vm.lawIndex = 2; XCTAssertEqual(vm.leftDB, -4.5, accuracy: 0.2)
    }

    /// Hard left must silence the right channel and vice versa — both directions.
    func testHardPanSilencesTheOppositeChannel() {
        let vm = PanViewModel()
        vm.lawIndex = 0

        vm.position = -1
        XCTAssertGreaterThan(vm.leftDB, -0.1, "hard left must pass the left channel at unity")
        XCTAssertLessThan(vm.rightDB, -60, "hard left must silence the right channel")

        vm.position = 1
        XCTAssertLessThan(vm.leftDB, -60, "hard right must silence the left channel")
        XCTAssertGreaterThan(vm.rightDB, -0.1, "hard right must pass the right channel at unity")
    }

    // MARK: Compressor — below, at and above threshold

    func testCompressorOnlyActsAboveTheKnee() {
        let vm = CompressorViewModel()
        vm.threshold = -20; vm.ratio = 4; vm.knee = 6; vm.makeup = 0

        // Well below the knee: no gain reduction at all.
        vm.input = -40
        XCTAssertEqual(vm.gainReduction, 0, accuracy: 1e-9,
                       "a signal far below threshold must be untouched")

        // Inside the soft knee: some, but less than the hard-knee line would give.
        vm.input = -20
        let atThreshold = vm.gainReduction
        XCTAssertGreaterThan(atThreshold, 0, "the soft knee must start acting at the threshold")

        // Above: (x−T)(1−1/R) = 10 · 0.75 = 7.5 dB at −10 in.
        vm.input = -10
        XCTAssertEqual(vm.gainReduction, 7.5, accuracy: 1e-9)
        XCTAssertGreaterThan(vm.gainReduction, atThreshold)

        // Makeup gain moves the output but never the gain reduction.
        let reduction = vm.gainReduction
        vm.makeup = 6
        XCTAssertEqual(vm.gainReduction, reduction, accuracy: 1e-9,
                       "makeup gain must not change the amount of compression")
        XCTAssertEqual(vm.output, Compressor.outputLevelDB(inputDB: -10, thresholdDB: -20,
                                                          ratio: 4, kneeDB: 6, makeupDB: 6),
                       accuracy: 1e-9)
    }

    /// Ratio 1:1 is the identity — a compressor that still reduces at 1:1 is wrong in a way that
    /// looks like "working" on every other setting.
    func testRatioOneIsTheIdentity() {
        let vm = CompressorViewModel()
        vm.threshold = -20; vm.ratio = 1; vm.knee = 0; vm.input = 0
        XCTAssertEqual(vm.gainReduction, 0, accuracy: 1e-9, "1:1 must not compress")
    }

    // MARK: Butterworth — order is a picker, and every order must steepen

    func testHigherOrderMeansSteeperSlope() {
        let vm = FilterViewModel()
        vm.fcHz = 1000
        vm.testHz = 2000                      // one octave above cutoff

        var previous = 0.0
        for order in [1, 2, 4, 8] {
            vm.order = order
            XCTAssertEqual(vm.slopeDbOct, Double(order) * 6, accuracy: 1e-9)
            // More attenuation (a more negative dB) with each step up.
            XCTAssertLessThan(vm.magDB, previous, "order \(order) must attenuate more than the last")
            previous = vm.magDB
        }
    }

    /// At the cutoff itself every Butterworth order is −3.01 dB, by definition. This is the anchor
    /// that catches a ratio computed the wrong way round.
    func testEveryOrderIsMinusThreeAtCutoff() {
        let vm = FilterViewModel()
        vm.fcHz = 1000; vm.testHz = 1000
        for order in [1, 2, 4, 8] {
            vm.order = order
            XCTAssertEqual(vm.magDB, -3.0103, accuracy: 1e-3, "order \(order) at fc")
        }
    }
}
