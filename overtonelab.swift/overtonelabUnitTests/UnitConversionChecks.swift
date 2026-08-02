import XCTest
@testable import Overtone_Lab

/// The conversions that live in the app, not in a Kit.
///
/// Every Kit takes SI: metres, farads, henries, m³, seconds. Every screen offers the units an
/// engineer actually reads off a spec sheet: cm, µF, mH, litres, minutes. The multiplication between
/// the two happens in the ViewModel — so it is the one layer of arithmetic that the Kits' oracle tests
/// **structurally cannot see**, and a factor of 1000 in the wrong direction here produces a number
/// that is wrong by three orders of magnitude while every Kit test stays green.
///
/// These run in microseconds, which is the point: the same coverage through XCUITest would be minutes
/// of tapping (§C.2), and the combinatorial cases below would never be run at all.
@MainActor
final class UnitConversionChecks: XCTestCase {

    // MARK: Passive — kΩ, µF, mH into ohms, farads, henries

    func testRCUsesKilohmsAndMicrofarads() {
        let vm = PassiveViewModel()
        vm.rcR = 1        // kΩ
        vm.rcC = 1        // µF
        // 1/(2π · 1000 Ω · 1e-6 F) = 159.1549 Hz. A missing ×1000 would read 159 kHz; a missing
        // 1e-6 would read 0.16 Hz. Both are obviously wrong on screen and invisible to the Kit.
        XCTAssertEqual(vm.rcHz, 159.15494309189535, accuracy: 1e-9)
    }

    func testRLUsesKilohmsAndMillihenries() {
        let vm = PassiveViewModel()
        vm.rlR = 1        // kΩ
        vm.rlL = 10       // mH
        // R/(2πL) = 1000/(2π · 0.01) = 15915.49 Hz
        XCTAssertEqual(vm.rlHz, 15915.494309189534, accuracy: 1e-6)
    }

    func testLCUsesMillihenriesAndMicrofarads() {
        let vm = PassiveViewModel()
        vm.lcL = 1        // mH
        vm.lcC = 1        // µF
        // 1/(2π√(LC)) = 1/(2π√(1e-3 · 1e-6)) = 5032.92 Hz
        XCTAssertEqual(vm.lcHz, 5032.9212104487045, accuracy: 1e-6)
    }

    /// Doubling a capacitance must halve a corner frequency. Catches a conversion applied to the
    /// wrong operand — which a single-point check cannot see, because one point fits many bugs.
    func testRCScalesInverselyWithCapacitance() {
        let vm = PassiveViewModel()
        vm.rcR = 1; vm.rcC = 1
        let at1uF = vm.rcHz
        vm.rcC = 2
        XCTAssertEqual(vm.rcHz, at1uF / 2, accuracy: 1e-9)
    }

    // MARK: Webster — cm and litres

    func testHornAreasComeFromCentimetreDiameters() {
        let vm = HornViewModel()
        vm.throatDiaCm = 2.5
        vm.mouthDiaCm = 40
        vm.lengthCm = 60
        // A = π(d/2)² in m²: a 40 cm mouth is 0.12566 m², not 1256 m² and not 1.2566 m².
        XCTAssertEqual(vm.mouthArea, Double.pi * pow(0.2, 2), accuracy: 1e-12)
        XCTAssertEqual(vm.throatArea, Double.pi * pow(0.0125, 2), accuracy: 1e-12)
        // flare = ln(Am/At)/L with L in METRES — dividing by 60 instead of 0.6 would put the cutoff
        // 100× too low and still look like a plausible horn.
        XCTAssertEqual(vm.flareM, log(vm.mouthArea / vm.throatArea) / 0.6, accuracy: 1e-9)
    }

    func testHelmholtzTakesLitresAsCubicMetres() {
        let vm = HornViewModel()
        vm.neckDiaCm = 5
        vm.cavityLiters = 20
        vm.neckLenCm = 10
        // 20 L = 0.02 m³. Feeding 20 m³ would drop the resonance by √1000 ≈ 31.6×.
        let sane = vm.helmholtzHz
        XCTAssertTrue((20...500).contains(sane),
                      "a 20 L cavity with a 5 cm neck resonates in the tens-to-hundreds of Hz, got \(sane)")
        // And the effective neck length adds the 0.85·r end correction, in metres.
        XCTAssertEqual(vm.effLenM, 0.10 + 0.85 * 0.025, accuracy: 1e-12)
    }

    // MARK: Bernoulli — mm in, mm out, metres in between

    func testEndCorrectionRoundTripsThroughMillimetres() {
        let vm = PipeViewModel()
        vm.radiusMm = 20
        // Flanged end correction is 0.82·r (Rayleigh); at r = 20 mm that is 16.4 mm. If the ×1000
        // back-conversion were dropped the screen would read 0.02 mm.
        XCTAssertEqual(vm.endFlangedMm, 16.4, accuracy: 0.05)
        // Unflanged (0.61·r) must be the smaller of the two — a swapped pair is silent otherwise.
        XCTAssertLessThan(vm.endUnflangedMm, vm.endFlangedMm)
    }

    // MARK: Mersenne — newtons to pounds-force

    func testTensionConvertsToPoundsForce() {
        let vm = StringsViewModel()
        vm.freq = 110; vm.lengthM = 0.65; vm.mu = 0.005
        XCTAssertEqual(vm.tensionN, 4 * pow(110, 2) * pow(0.65, 2) * 0.005, accuracy: 1e-9)
        // 1 lbf = 4.4482216 N. Multiplying instead of dividing would be ~20× off.
        XCTAssertEqual(vm.tensionLbf, vm.tensionN / 4.4482216, accuracy: 1e-9)
        XCTAssertLessThan(vm.tensionLbf, vm.tensionN, "a force in lbf is a smaller number than in N")
    }

    // MARK: File — minutes to seconds

    func testFileSizeTreatsTheFieldAsMinutes() {
        let vm = FileViewModel()
        vm.sampleRate = 44100; vm.bitDepth = 16; vm.channels = 2; vm.minutes = 3
        // 44100 · 2 B · 2 ch · 180 s = 31,752,000 B. Forgetting ×60 would report 529 kB for 3 minutes.
        XCTAssertEqual(vm.bytes, 31_752_000, accuracy: 1)
        XCTAssertEqual(vm.megabytes, 31.752, accuracy: 1e-9)
    }

    // MARK: Thiele — litres and centimetres

    func testPortLengthUsesLitresAndCentimetres() {
        let vm = ThieleViewModel()
        vm.vbPorted = 50        // L
        vm.fb = 35              // Hz
        vm.portDiaCm = 10       // cm
        vm.portCount = 1
        // A 10 cm port tuning a 50 L box to 35 Hz is on the order of tens of cm. A litres-as-m³ slip
        // makes it kilometres; a cm-as-m slip makes it microscopic.
        XCTAssertTrue((1...200).contains(vm.portLenCm),
                      "port length must land in centimetres, got \(vm.portLenCm)")
    }
}
