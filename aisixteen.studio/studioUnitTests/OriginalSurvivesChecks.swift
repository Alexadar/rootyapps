import XCTest
import CoreGraphics
import RecipeKit
import EnhanceKit
import EditsKit
@testable import Studio

/// **"The original survives" — through the app, on every exit path.**
///
/// `EditsKit` proves the file is sealed. This proves that driving the real `EditModel` through every
/// way an edit can end never disturbs it, which is the version of the promise a user experiences.
@MainActor
final class OriginalSurvivesChecks: XCTestCase {

    func testAfterACompletedPass() async {
        let fixture = makeEditFixture()
        fixture.model.enhance()
        await waitUntil("the pass") { fixture.model.phase == .complete }
        assertIntact(fixture)
    }

    func testAfterACancelledPass() async {
        let fixture = makeEditFixture(enhancer: HangingEnhancer())
        fixture.model.enhance()
        await waitUntil("the pass to start") { fixture.model.phase.isRunning }
        fixture.model.cancel()
        await waitUntil("idle") { fixture.model.phase == .idle }
        assertIntact(fixture)
    }

    func testAfterAFailedPass() async {
        let fixture = makeEditFixture(enhancer: FailingPhotoEnhancer(failAtStep: 3,
                                                                     error: .outOfMemory,
                                                                     speed: .instant))
        fixture.model.enhance()
        await waitUntil("the failure") { fixture.model.phase.isFailed }
        assertIntact(fixture)
    }

    func testAfterStrengthGoesToZero() async {
        let fixture = makeEditFixture()
        fixture.model.enhance()
        await waitUntil("the pass") { fixture.model.phase == .complete }
        fixture.model.strength = .zero
        assertIntact(fixture)
    }

    func testAfterARevert() async {
        let fixture = makeEditFixture()
        fixture.model.enhance()
        await waitUntil("the pass") { fixture.model.phase == .complete }
        fixture.model.revert()
        assertIntact(fixture)
    }

    func testAfterExportingAsANewPhoto() async {
        let fixture = makeEditFixture()
        fixture.model.enhance()
        await waitUntil("the pass") { fixture.model.phase == .complete }

        // The bytes that would be handed to Photos. Producing them must not touch the source.
        XCTAssertNotNil(fixture.model.exportData())
        assertIntact(fixture)
    }

    func testAfterARerunAtAHigherStrength() async {
        let fixture = makeEditFixture()
        fixture.model.strength = .whisper
        fixture.model.enhance()
        await waitUntil("the first pass") { fixture.model.phase == .complete }

        fixture.model.strength = .strong
        fixture.model.enhance()
        await waitUntil("the second pass") {
            fixture.model.recipe.edit(for: .whole)?.rendered == .strong
        }
        assertIntact(fixture)
    }

    func testAfterPaintingAndEnhancingABrushedArea() async {
        let fixture = makeEditFixture()
        fixture.model.scope = .brush
        fixture.model.paintBrush(at: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)],
                                 radius: 10, erasing: false)
        fixture.model.enhance()
        await waitUntil("the pass") { fixture.model.phase == .complete }
        assertIntact(fixture)
    }

    func testAfterASubjectPassWhichAlsoWritesAMaskFile() async {
        let fixture = makeEditFixture()
        fixture.model.scope = .subject
        await waitUntil("the mask") { fixture.model.maskAvailability == .ready }
        fixture.model.enhance()
        await waitUntil("the pass") { fixture.model.phase == .complete }
        assertIntact(fixture)
    }

    func testAfterTheAppIsKilledMidPass() async {
        // Simulated by dropping the model on the floor while a pass is in flight, then reopening
        // the edit from disk — which is what a relaunch actually does.
        var fixture: (model: EditModel, library: EditLibrary, record: EditRecord)? = makeEditFixture(
            enhancer: HangingEnhancer())
        fixture!.model.enhance()
        await waitUntil("the pass to start") { fixture!.model.phase.isRunning }

        let library = fixture!.library
        let record = fixture!.record
        fixture = nil                                   // the process goes away mid-pass

        let reloaded = try? library.load().first
        XCTAssertNotNil(reloaded)
        XCTAssertNoThrow(try library.verifyOriginal(reloaded!))
        XCTAssertTrue(library.originalIsSealed(reloaded!))
    }

    func testAfterDeletingTheEditNothingElseInTheLibraryIsDisturbed() async throws {
        let fixture = makeEditFixture()
        let second = try fixture.library.create(originalData: Data(repeating: 7, count: 128),
                                                fileExtension: "png",
                                                displayName: "Other",
                                                seed: 99,
                                                createdAt: Date(timeIntervalSince1970: 1_786_100_000))
        try fixture.library.delete(fixture.record)

        let remaining = try fixture.library.load()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        XCTAssertNoThrow(try fixture.library.verifyOriginal(remaining[0]))
    }

    private func assertIntact(_ fixture: (model: EditModel, library: EditLibrary, record: EditRecord),
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertNoThrow(try fixture.library.verifyOriginal(fixture.record), file: file, line: line)
        XCTAssertTrue(fixture.library.originalIsSealed(fixture.record), file: file, line: line)
        XCTAssertTrue(fixture.model.originalIsIntact(), file: file, line: line)
    }
}
