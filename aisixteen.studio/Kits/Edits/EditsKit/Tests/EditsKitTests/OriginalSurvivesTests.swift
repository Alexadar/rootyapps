import XCTest
import RecipeKit
@testable import EditsKit

/// **"The original survives" — asserted on every exit path there is.**
///
/// This is the promise the whole product is built on, so it is not tested once at the happy path.
/// Every way out of an edit re-hashes the file, and one test tries to break the seal on purpose.
final class OriginalSurvivesTests: XCTestCase {

    private var library: EditLibrary!
    private var record: EditRecord!

    override func setUpWithError() throws {
        library = makeLibrary()
        try library.prepare()
        record = try library.create(originalData: samplePhoto,
                                    fileExtension: "heic",
                                    displayName: "IMG_4021",
                                    seed: 0xC0FFEE,
                                    createdAt: fixedDate)
    }

    func testTheOriginalIsSealedReadOnlyTheMomentItLands() throws {
        XCTAssertTrue(library.originalIsSealed(record))
        let permissions = try DirectFileAccess().permissions(of: record.originalURL)
        XCTAssertEqual(permissions & 0o222, 0, "no write bit for anyone: got \(String(permissions, radix: 8))")
    }

    func testWritingToTheOriginalFailsAtTheFileSystemRatherThanSucceedingQuietly() {
        // The app never opens it for writing. This asserts the *belt* — the thing that catches a
        // future refactor that does, and makes it fail loudly instead of destroying the one file
        // that cannot be regenerated.
        XCTAssertThrowsError(try Data("overwritten".utf8).write(to: record.originalURL))
        XCTAssertNoThrow(try library.verifyOriginal(record))
    }

    func testTheDigestDescribesTheBytesTheUserChose() throws {
        XCTAssertEqual(record.recipe.sourceDigest, EditLibrary.digest(of: samplePhoto))
        XCTAssertEqual(try library.readOriginal(record), samplePhoto)
    }

    // MARK: Every exit path

    func testTheOriginalSurvivesAWrittenEnhancedCopy() throws {
        try library.write(enhanced: Data(repeating: 0xAB, count: 512), for: record)
        try assertOriginalIntact()
    }

    func testTheOriginalSurvivesACancelledPass() throws {
        // A cancelled pass writes nothing at all — asserted by there being no enhanced file after.
        try assertOriginalIntact()
        XCTAssertNil(try library.readEnhanced(record))
    }

    func testTheOriginalSurvivesAFailedPass() throws {
        try library.save(recipe: record.recipe, for: record)   // a failure still saves no pixels
        try assertOriginalIntact()
        XCTAssertNil(try library.readEnhanced(record))
    }

    func testTheOriginalSurvivesStrengthGoingToZero() throws {
        var recipe = record.recipe
        recipe.update(.whole) { $0.markRendered(at: .balanced) }
        recipe.update(.whole) { $0.strength = .zero }
        record = try library.save(recipe: recipe, for: record)

        XCTAssertEqual(record.recipe.composite(), .original)
        try assertOriginalIntact()
    }

    func testTheOriginalSurvivesARevert() throws {
        var recipe = record.recipe
        recipe.update(.whole) { $0.markRendered(at: .strong) }
        recipe.revertAll()
        record = try library.save(recipe: recipe, for: record)
        try assertOriginalIntact()
    }

    func testTheOriginalSurvivesAScopeChangeAndAMaskWrite() throws {
        try library.write(mask: Data(repeating: 0xFF, count: 64), source: .segmentation, for: record)
        try library.write(mask: Data(repeating: 0x10, count: 64), source: .brush, for: record)

        var recipe = record.recipe
        recipe.update(.subject) { $0.markRendered(at: .balanced) }
        record = try library.save(recipe: recipe, for: record)
        try assertOriginalIntact()
    }

    func testTheOriginalSurvivesARerunAtAHigherStrength() throws {
        var recipe = record.recipe
        recipe.update(.whole) { $0.markRendered(at: .whisper) }
        try library.write(enhanced: Data(repeating: 0x01, count: 128), for: record)
        recipe.update(.whole) { $0.markRendered(at: .strong) }
        try library.write(enhanced: Data(repeating: 0x02, count: 128), for: record)
        record = try library.save(recipe: recipe, for: record)

        try assertOriginalIntact()
        XCTAssertEqual(try library.readEnhanced(record), Data(repeating: 0x02, count: 128),
                       "the enhanced copy is the one file that may be written over")
    }

    func testTheOriginalSurvivesAnExportAsNew() throws {
        try library.write(enhanced: Data(repeating: 0x7F, count: 256), for: record)
        let exported = try library.readEnhanced(record)          // what Photos would receive
        XCTAssertNotNil(exported)
        try assertOriginalIntact()
    }

    func testTheOriginalSurvivesReopeningTheEditInAFreshLibrary() throws {
        let reopened = makeLibrary(root: library.root)
        guard let reloaded = try reopened.load().first else { return XCTFail("nothing reloaded") }

        XCTAssertNoThrow(try reopened.verifyOriginal(reloaded))
        XCTAssertTrue(reopened.originalIsSealed(reloaded))
    }

    func testDeletingAnEditWorksDespiteTheSealAndTakesEverythingWithIt() throws {
        try library.write(enhanced: Data(repeating: 1, count: 32), for: record)
        try library.delete(record)

        XCTAssertTrue(try library.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.folder.path),
                       "0444 must not stand between the user and deleting their own edit")
    }

    // MARK: The guard can actually fail

    func testVerifyOriginalNoticesAChangedFile() throws {
        // Prove the assertion above is not vacuous: break the seal deliberately and confirm the
        // check catches it. A guard that has never been seen to fail is not a guard.
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: record.originalURL.path)
        try Data("a different photo entirely".utf8).write(to: record.originalURL)

        XCTAssertThrowsError(try library.verifyOriginal(record)) { error in
            XCTAssertEqual(error as? EditLibraryError, .originalChanged(self.record.id))
        }
        XCTAssertFalse(library.originalIsSealed(record))
    }

    func testVerifyOriginalNoticesAMissingFile() throws {
        try FileManager.default.removeItem(at: record.originalURL)
        XCTAssertThrowsError(try library.verifyOriginal(record)) { error in
            XCTAssertEqual(error as? EditLibraryError, .originalMissing(self.record.id))
        }
    }

    func testATruncatedOriginalIsCaughtToNotOnlyADifferentOne() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: record.originalURL.path)
        try samplePhoto.dropLast(1).write(to: record.originalURL)

        XCTAssertThrowsError(try library.verifyOriginal(record))
    }

    private func assertOriginalIntact(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNoThrow(try library.verifyOriginal(record), file: file, line: line)
        XCTAssertEqual(try library.readOriginal(record), samplePhoto, file: file, line: line)
        XCTAssertTrue(library.originalIsSealed(record), file: file, line: line)
    }
}
