import XCTest
import RecipeKit
@testable import EditsKit

/// The library, over both roots — because "iCloud switched off" is a supported configuration and
/// the only way it stays supported is if it is tested.
final class EditLibraryTests: XCTestCase {

    func testTheSameCodeRunsOverACoordinatedRootAndADirectOne() throws {
        for access in [AnyAccess(CoordinatedFileAccess()), AnyAccess(DirectFileAccess())] {
            let library = makeLibrary(access: access.base)
            try library.prepare()

            let record = try library.create(originalData: samplePhoto,
                                            fileExtension: "heic",
                                            displayName: "IMG_4021",
                                            seed: 0xC0FFEE,
                                            createdAt: fixedDate)

            XCTAssertEqual(try library.readOriginal(record), samplePhoto, "\(access.name)")
            XCTAssertEqual(try library.load().count, 1, "\(access.name)")
            XCTAssertNoThrow(try library.verifyOriginal(record), "\(access.name)")
        }
    }

    func testAnEditIdentifierSortsChronologicallyAndCannotCollideInOneMinute() {
        let a = EditIdentifier.make(createdAt: fixedDate, seed: 1)
        let b = EditIdentifier.make(createdAt: fixedDate, seed: 2)
        let later = EditIdentifier.make(createdAt: fixedDate.addingTimeInterval(3600), seed: 1)

        XCTAssertNotEqual(a, b)
        XCTAssertLessThan(a.rawValue, later.rawValue)
    }

    func testTheLibraryListsNewestFirst() throws {
        let library = makeLibrary()
        try library.prepare()
        let older = try library.create(originalData: samplePhoto, fileExtension: "heic",
                                       displayName: "Old", seed: 1, createdAt: fixedDate)
        let newer = try library.create(originalData: samplePhoto, fileExtension: "heic",
                                       displayName: "New", seed: 2,
                                       createdAt: fixedDate.addingTimeInterval(86_400))

        XCTAssertEqual(try library.load().map(\.id), [newer.id, older.id])
    }

    func testTheDisplayNameSurvivesAReload() throws {
        let library = makeLibrary()
        try library.prepare()
        _ = try library.create(originalData: samplePhoto, fileExtension: "heic",
                               displayName: "IMG_4021", seed: 7, createdAt: fixedDate)

        XCTAssertEqual(try library.load().first?.displayName, "IMG_4021")
    }

    func testOneCorruptRecipeDoesNotTakeTheWholeLibraryDown() throws {
        let library = makeLibrary()
        try library.prepare()
        let good = try library.create(originalData: samplePhoto, fileExtension: "heic",
                                      displayName: "Good", seed: 1, createdAt: fixedDate)
        let broken = try library.create(originalData: samplePhoto, fileExtension: "heic",
                                        displayName: "Broken", seed: 2,
                                        createdAt: fixedDate.addingTimeInterval(60))
        try Data("{ not json".utf8).write(to: broken.recipeURL)

        // The library is the only way back to the other edits; it must still open.
        XCTAssertEqual(try library.load().map(\.id), [good.id])
    }

    func testTheRecipeOnDiskIsReadableByAHumanInFiles() throws {
        let library = makeLibrary()
        try library.prepare()
        let record = try library.create(originalData: samplePhoto, fileExtension: "heic",
                                        displayName: "IMG_4021", seed: 0xC0FFEE, createdAt: fixedDate)

        let text = String(data: try Data(contentsOf: record.recipeURL), encoding: .utf8)!
        XCTAssertTrue(text.contains("\n"), "pretty-printed, so a curious user can read it")
        XCTAssertTrue(text.contains("sourceDigest"))
        XCTAssertTrue(text.contains("2026-"), "dates are ISO 8601, not a float since 2001")
    }

    func testTheBadgeNamesTheStrengthAndTheScopeItWasMadeWith() throws {
        let library = makeLibrary()
        try library.prepare()
        var record = try library.create(originalData: samplePhoto, fileExtension: "heic",
                                        displayName: "IMG_4021", seed: 1, createdAt: fixedDate)

        XCTAssertEqual(record.badge, "Original")

        record.recipe.update(.whole) { $0.markRendered(at: .subtle) }
        XCTAssertEqual(record.badge, "35")

        record.recipe.update(.subject) { $0.markRendered(at: .balanced) }
        XCTAssertEqual(record.badge, "55 · Subject")
    }

    func testAFolderWithNoUbiquityKeysReadsAsLocalRatherThanMissing() throws {
        let library = makeLibrary()
        try library.prepare()
        _ = try library.create(originalData: samplePhoto, fileExtension: "heic",
                               displayName: "IMG_4021", seed: 1, createdAt: fixedDate)

        XCTAssertEqual(try library.load().first?.availability, .local)
    }

    func testTheNotDownloadedTileSaysWhereTheFileIsNotThatItIsGone() {
        XCTAssertEqual(EditAvailability.local.caption, nil)
        XCTAssertEqual(EditAvailability.notDownloaded.caption, "From your iPad")
        XCTAssertEqual(EditAvailability.downloading(fraction: nil).caption, "Downloading…")
        XCTAssertFalse(EditAvailability.notDownloaded.isLocal)
    }

    func testAnOriginalWithNoExtensionStillGetsAName() {
        XCTAssertEqual(EditLayout.originalFilename(extension: "HEIC"), "original.heic")
        XCTAssertEqual(EditLayout.originalFilename(extension: ".jpg"), "original.jpg")
        XCTAssertEqual(EditLayout.originalFilename(extension: ""), "original")
        XCTAssertEqual(EditLayout.originalFilename(extension: "  "), "original")
    }
}

/// Boxes a `FileAccess` so a test can loop over both implementations and name the failing one.
struct AnyAccess {
    let base: FileAccess
    let name: String
    init(_ base: FileAccess) {
        self.base = base
        self.name = String(describing: type(of: base))
    }
}
