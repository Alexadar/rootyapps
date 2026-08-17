import XCTest
import RecipeKit
import EditsKit
@testable import Studio

/// The iCloud-available / iCloud-unavailable axis.
///
/// A user with iCloud switched off is not an edge case — it is a supported configuration, and the
/// only way it stays supported is if it is tested. The two things that must differ are *where* the
/// files go and *what the app says about it*; everything else must be identical.
final class StorageChecks: XCTestCase {

    func testTheCaptionTellsTheTruthAboutWhereEditsLive() {
        let cloud = StorageLocation.iCloud(URL(fileURLWithPath: "/cloud"))
        let local = StorageLocation.local(URL(fileURLWithPath: "/local"))

        XCTAssertEqual(cloud.captionSuffix, "in your iCloud folder")
        XCTAssertEqual(local.captionSuffix, "on this device")
        XCTAssertNotEqual(cloud.captionSuffix, local.captionSuffix,
                          "the two states must not read the same — that would be the lie")
    }

    func testThePromiseMatchesWhereFilesWillActuallyGo() {
        let cloud = StorageLocation.iCloud(URL(fileURLWithPath: "/cloud"))
        let local = StorageLocation.local(URL(fileURLWithPath: "/local"))

        XCTAssertTrue(cloud.emptyStatePromise.contains("iCloud"))
        XCTAssertFalse(local.emptyStatePromise.contains("iCloud"),
                       "promising iCloud with iCloud off is exactly the failure to avoid")
        XCTAssertTrue(local.libraryPromise.contains("nothing syncs"))
    }

    func testNoStorageCopyDescribesICloudAsAServiceOrAnAccount() {
        // ⚠️ User-owned storage language only. iCloud is the user's folder, not a server.
        let copy = [StorageLocation.iCloud(URL(fileURLWithPath: "/c")),
                    StorageLocation.local(URL(fileURLWithPath: "/l"))]
            .flatMap { [$0.captionSuffix, $0.libraryPromise, $0.emptyStatePromise] }
            .joined(separator: " ")

        for banned in ["account", "server", "upload", "cloud storage", "sign in", "our servers"] {
            XCTAssertFalse(copy.localizedCaseInsensitiveContains(banned), "found \"\(banned)\"")
        }
    }

    func testBothLocationsExposeTheirRootAndTheirKind() {
        let url = URL(fileURLWithPath: "/somewhere")
        XCTAssertEqual(StorageLocation.iCloud(url).root, url)
        XCTAssertEqual(StorageLocation.local(url).root, url)
        XCTAssertTrue(StorageLocation.iCloud(url).isCloud)
        XCTAssertFalse(StorageLocation.local(url).isCloud)
    }

    func testTheLocalFallbackIsNotTheCachesDirectory() {
        // Caches can be purged by the system. Losing an edit because the disk got tight is not an
        // acceptable outcome for "iCloud is off".
        let root = LibraryLocator.localFallbackRoot()
        XCTAssertFalse(root.path.contains("/Caches/"), root.path)
        XCTAssertEqual(root.lastPathComponent, "Edits")
    }

    func testTheContainerIdentifierMatchesTheEntitlementAndTheInfoPlist() {
        // A mismatch here does not fail to build — it silently resolves to nil at runtime and the
        // app quietly becomes local-only for everyone.
        XCTAssertEqual(LibraryLocator.containerIdentifier, "iCloud.oleksandr.aisixteen.studio")
    }

    func testTheSameLibraryCodeRunsOverBothRoots() throws {
        for location in [StorageLocation.iCloud(makeTemporaryDirectory()),
                         StorageLocation.local(makeTemporaryDirectory())] {
            // Coordination is the only difference, and it must not change the outcome.
            let library = LibraryLocator.library(for: location, appVersion: "1.0")
            try library.prepare()
            let record = try library.create(originalData: Data(repeating: 3, count: 256),
                                            fileExtension: "png",
                                            displayName: "IMG_0001",
                                            seed: 1,
                                            createdAt: Date(timeIntervalSince1970: 1_786_000_000))

            XCTAssertNoThrow(try library.verifyOriginal(record))
            XCTAssertTrue(library.originalIsSealed(record))
            XCTAssertEqual(try library.load().count, 1)
        }
    }
}

/// The privacy promise is made in exactly three places, once each (`1j`).
final class PrivacyCopyChecks: XCTestCase {

    func testTheImportFooterMakesThePromiseWithoutSellingIt() {
        XCTAssertEqual(PrivacyCopy.importFooter,
                       "No account · No network · Your photo never leaves this device")
    }

    func testTheExportFooterNamesTheDeviceItRanOn() {
        XCTAssertEqual(PrivacyCopy.exportFooter(deviceName: "iPhone"),
                       "Enhanced on this iPhone. Never uploaded.")
        XCTAssertEqual(PrivacyCopy.exportFooter(deviceName: "Mac"),
                       "Enhanced on this Mac. Never uploaded.")
    }

    func testTheExportSheetHasTwoRowsAndNeitherIsAnUpsell() {
        // Two, not three: "Replace in Photos" is deliberately absent so the app never needs more
        // than add-only access. Flagged to the owner as a deviation from board 1e.
        XCTAssertEqual(ExportOption.allCases, [.saveAsNew, .share])
        XCTAssertFalse(ExportOption.allCases.contains { $0.title.contains("Replace") })
    }
}
