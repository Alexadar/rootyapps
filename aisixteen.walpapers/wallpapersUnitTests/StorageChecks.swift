import XCTest
import GenerationKit
import LibraryKit
@testable import Wallpapers

/// The iCloud-available / iCloud-unavailable axis.
///
/// A user with iCloud switched off is not an edge case — it is a supported configuration, and the
/// only way it stays supported is if it is tested. The two things that must differ are *where* the
/// files go and *what the app says about it*; everything else must be identical.
final class StorageChecks: XCTestCase {

    func testTheCaptionTellsTheTruthAboutWhereWallpapersLive() {
        let cloud = StorageLocation.iCloud(URL(fileURLWithPath: "/cloud"))
        let local = StorageLocation.local(URL(fileURLWithPath: "/local"))

        XCTAssertEqual(cloud.captionSuffix, "in your iCloud folder")
        XCTAssertEqual(local.captionSuffix, "on this device")
        XCTAssertNotEqual(cloud.captionSuffix, local.captionSuffix,
                          "the two states must not read the same — that would be the lie")
    }

    func testTheEmptyStatePromiseMatchesWhereFilesWillActuallyGo() {
        let cloud = StorageLocation.iCloud(URL(fileURLWithPath: "/cloud"))
        let local = StorageLocation.local(URL(fileURLWithPath: "/local"))

        XCTAssertTrue(cloud.emptyStatePromise.contains("iCloud"))
        XCTAssertFalse(local.emptyStatePromise.contains("iCloud"),
                       "promising iCloud with iCloud off is exactly the failure to avoid")
    }

    func testBothLocationsExposeTheirRootAndTheirKind() {
        let url = URL(fileURLWithPath: "/somewhere")
        XCTAssertEqual(StorageLocation.iCloud(url).root, url)
        XCTAssertEqual(StorageLocation.local(url).root, url)
        XCTAssertTrue(StorageLocation.iCloud(url).isCloud)
        XCTAssertFalse(StorageLocation.local(url).isCloud)
    }

    func testTheLocalFallbackIsNotTheCachesDirectory() {
        // Caches can be purged by the system. Losing a wallpaper the user liked because the disk
        // got tight is not an acceptable outcome for "iCloud is off".
        let root = LibraryLocator.localFallbackRoot()
        XCTAssertFalse(root.path.contains("/Caches/"), "got \(root.path)")
        XCTAssertTrue(root.lastPathComponent == "Wallpapers")
    }

    func testTheSameLibraryCodeRunsOverBothRoots() throws {
        let cloudish = StorageLocation.iCloud(makeTemporaryDirectory())
        let localish = StorageLocation.local(makeTemporaryDirectory())

        for location in [cloudish, localish] {
            // Coordination is the only difference, and it must not change the outcome.
            let library = LibraryLocator.library(for: location, appVersion: "1.0.0")
            try library.prepare()
            let saved = try library.save(imageData: Data([1, 2, 3]),
                                         prompt: "a slow river through basalt",
                                         seed: 42,
                                         aspect: .phone,
                                         createdAt: Date(timeIntervalSince1970: 1_786_000_000))
            let listed = try library.records()
            XCTAssertEqual(listed.count, 1, "\(location.captionSuffix)")
            XCTAssertEqual(listed.first?.prompt, "a slow river through basalt")
            XCTAssertEqual(listed.first?.id, saved.id)
            XCTAssertTrue(listed.first!.imageURL.path.hasPrefix(location.root.path))
        }
    }

    func testAWallpaperWrittenUnderOneRootIsReadableUnderTheOther() throws {
        // What happens when the user turns iCloud on or off between launches: the app must not
        // consider the other folder's files foreign.
        let root = makeTemporaryDirectory()
        let asCloud = LibraryLocator.library(for: .iCloud(root), appVersion: "1.0.0")
        let asLocal = LibraryLocator.library(for: .local(root), appVersion: "1.0.0")

        try asCloud.save(imageData: Data([9]), prompt: "paper cranes", seed: 7,
                         aspect: .pad, createdAt: Date(timeIntervalSince1970: 1_786_000_000))

        let readBack = try asLocal.records()
        XCTAssertEqual(readBack.count, 1)
        XCTAssertEqual(readBack.first?.prompt, "paper cranes")
        XCTAssertEqual(readBack.first?.aspect, AspectRatio.pad)
    }
}
