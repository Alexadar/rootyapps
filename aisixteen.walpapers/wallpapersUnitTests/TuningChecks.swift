import XCTest
import GenerationKit
@testable import Wallpapers

/// ORACLES:
///  • INVARIANT — the count shown equals the rows actually ticked. A card reading "4 of 6" with
///    three checkmarks is worse than no card.
///  • BEHAVIOUR — the screen appears whenever there is work left, not only on a first-ever launch.
///    That rule is why the designed screen was, in practice, never seen: one part completed and
///    every later launch fell through to a chip.
@MainActor
final class TuningChecks: XCTestCase {

    private let parts = [
        ModelPart(id: "textEncoder", name: "Text encoder", bytes: 140),
        ModelPart(id: "unet", name: "Image model", bytes: 648),
        ModelPart(id: "decoder", name: "Image decoder", bytes: 99),
    ]

    private var sandbox: URL!
    private var realMarker: URL!

    override func setUp() {
        super.setUp()
        realMarker = ModelWarmth.markerURL
        sandbox = makeTemporaryDirectory()
        ModelWarmth.markerURL = sandbox.appendingPathComponent("warmth.json")
    }

    override func tearDown() {
        ModelWarmth.markerURL = realMarker
        try? FileManager.default.removeItem(at: sandbox)
        super.tearDown()
    }

    // MARK: The screen shows whenever there is work

    func testAPartlyCompiledModelStillEarnsTheScreen() {
        // THE BUG THIS PINS. The screen used to require an entirely cold cache, so after the very
        // first part landed it never appeared again — the user saw a chip and never the checklist.
        ModelWarmth.note("textEncoder", under: ModelWarmth.key(for: parts))

        let gate = ModelGate()
        let skipping = gate.begin(tuning: parts)

        XCTAssertEqual(skipping, ["textEncoder"])
        XCTAssertEqual(gate.phase, .tuning(part: 1, of: 3))
        XCTAssertFalse(gate.showsShell, "there is work left, so the screen stands")
    }

    func testAFullyCompiledModelSkipsStraightToReady() {
        let key = ModelWarmth.key(for: parts)
        for part in parts { ModelWarmth.note(part.id, under: key) }

        let gate = ModelGate()
        _ = gate.begin(tuning: parts)
        XCTAssertEqual(gate.phase, .ready)
        XCTAssertTrue(gate.showsShell)
    }

    func testLookingAroundOpensTheAppWithoutFinishingTheCompile() {
        let gate = ModelGate()
        _ = gate.begin(tuning: parts)
        XCTAssertFalse(gate.showsShell)

        gate.lookAround()
        XCTAssertTrue(gate.showsShell, "the compile is not a blocking gate")
        XCTAssertEqual(gate.phase, .tuning(part: 0, of: 3), "and it is still running")
    }

    // MARK: The checklist

    func testEachFinishedPartTicksItsRowAndAdvancesTheCount() {
        let gate = ModelGate()
        _ = gate.begin(tuning: parts)

        gate.absorb(.began(part: parts[0], index: 1, of: 3))
        XCTAssertEqual(gate.checklist.row(for: parts[0]), .working)

        gate.absorb(.finished(part: parts[0], index: 1, of: 3, seconds: 4))
        XCTAssertEqual(gate.checklist.row(for: parts[0]), .ready)
        XCTAssertEqual(gate.checklist.completedCount, 1)
        XCTAssertEqual(gate.phase, .tuning(part: 1, of: 3))
    }

    func testTheCountAlwaysMatchesTheTickedRows() {
        let gate = ModelGate()
        _ = gate.begin(tuning: parts)
        for (index, part) in parts.enumerated() {
            gate.absorb(.began(part: part, index: index + 1, of: 3))
            gate.absorb(.finished(part: part, index: index + 1, of: 3, seconds: 1))
            XCTAssertEqual(gate.checklist.completedCount,
                           parts.filter { gate.checklist.row(for: $0) == .ready }.count)
        }
        XCTAssertEqual(gate.phase, .ready, "the last part opens the app")
    }

    func testAFinishedPartIsRecordedSoTheNextLaunchSkipsIt() {
        let gate = ModelGate()
        _ = gate.begin(tuning: parts)
        gate.absorb(.finished(part: parts[1], index: 2, of: 3, seconds: 9))

        XCTAssertEqual(ModelWarmth.compiled(under: ModelWarmth.key(for: parts)), ["unet"])
    }

    func testStandingDownKeepsFinishedWorkAndFreesTheWorkingRow() {
        let gate = ModelGate()
        _ = gate.begin(tuning: parts)
        gate.absorb(.began(part: parts[0], index: 1, of: 3))
        gate.absorb(.finished(part: parts[0], index: 1, of: 3, seconds: 1))
        gate.absorb(.began(part: parts[1], index: 2, of: 3))
        gate.absorb(.stoodDown(after: 1, of: 3))

        XCTAssertEqual(gate.checklist.row(for: parts[0]), .ready)
        XCTAssertEqual(gate.checklist.row(for: parts[1]), .waiting,
                       "a yielded part must not be left spinning for ever")
        XCTAssertEqual(gate.checklist.completedCount, 1)
    }

    func testAPartThatWillNotCompileDoesNotStallTheApp() {
        // Core ML falls back to the CPU: the picture still arrives, slower. A red row would alarm
        // the user about something they cannot act on, and would hold the counter for ever.
        let gate = ModelGate()
        _ = gate.begin(tuning: parts)
        for (index, part) in parts.enumerated() {
            gate.absorb(.failed(part: part, reason: "ANECCompile() FAILED"))
            _ = index
        }
        XCTAssertEqual(gate.phase, .ready)
    }

    // MARK: The pure reducer

    func testReadyNeverRegressesIntoTuning() {
        // A late event from a pass that stood down must not reopen the setup screen over a working
        // app — the one ordering bug that would be maddening and hard to see.
        XCTAssertEqual(ModelGate.reduce(.ready, on: .tuningBegan(parts: 6), wifiOnly: true), .ready)
        XCTAssertEqual(ModelGate.reduce(.ready, on: .tuningAdvanced(completed: 1, of: 6),
                                        wifiOnly: true), .ready)
    }

    func testTheCounterIsClamped() {
        XCTAssertEqual(ModelGate.reduce(.checking, on: .tuningAdvanced(completed: 99, of: 6),
                                        wifiOnly: true), .tuning(part: 6, of: 6))
        XCTAssertEqual(ModelGate.reduce(.checking, on: .tuningAdvanced(completed: -3, of: 6),
                                        wifiOnly: true), .tuning(part: 0, of: 6))
    }

    func testTuningIsNotFinished() {
        XCTAssertFalse(ModelGate.Phase.tuning(part: 2, of: 6).isFinished)
    }
}
