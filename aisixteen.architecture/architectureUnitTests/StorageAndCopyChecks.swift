import FormatKit
import ProjectKit
import RedesignKit
import XCTest
@testable import Architecture

@MainActor
final class CheckpointStoreChecks: XCTestCase {

    private var root: URL!
    private var store: CheckpointStore!

    override func setUp() {
        root = Fixtures.temporaryDirectory("checkpoints")
        store = CheckpointStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func checkpoint(step: Int, digest: String = "abc") -> GenerationCheckpoint {
        GenerationCheckpoint(kind: "mock.v1", requestDigest: digest, step: step, totalSteps: 32,
                             deviceID: "device", state: Data([1, 2, 3]), createdAt: Date())
    }

    func testACheckpointRoundTrips() throws {
        let id = JobID("job-1")
        try store.write(checkpoint(step: 12), for: id)
        let read = store.read(for: id)
        XCTAssertEqual(read?.step, 12)
        XCTAssertEqual(read?.state, Data([1, 2, 3]))
        XCTAssertEqual(read?.kind, "mock.v1")
    }

    func testAHalfWrittenCheckpointIsUnreadableByConstruction() throws {
        // The record is the commit. A blob with no record beside it can never be mistaken for a
        // complete write, which is what makes "the process died mid-save" safe rather than subtle.
        let id = JobID("job-2")
        try store.write(checkpoint(step: 8), for: id)
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("job-2/checkpoint.json"))
        XCTAssertNil(store.read(for: id))
    }

    func testTheSweepDeletesOrphansAndKeepsLiveWork() throws {
        try store.write(checkpoint(step: 4), for: JobID("live"))
        try store.write(checkpoint(step: 4), for: JobID("dead"))
        // A crash during a render otherwise leaves megabytes behind forever, and nothing ever
        // looks at it again.
        store.sweep(keeping: [JobID("live")])

        XCTAssertNotNil(store.read(for: JobID("live")))
        XCTAssertNil(store.read(for: JobID("dead")))
    }

    func testTheSweepAlsoRemovesHalfWrittenState() throws {
        let id = JobID("torn")
        try store.write(checkpoint(step: 4), for: id)
        try FileManager.default.removeItem(at: root.appendingPathComponent("torn/checkpoint.json"))
        store.sweep(keeping: [id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("torn").path))
    }

    func testDiscardingRemovesEverythingForThatJob() throws {
        let id = JobID("job-3")
        try store.write(checkpoint(step: 4), for: id)
        store.discard(id)
        XCTAssertNil(store.read(for: id))
    }

    func testDeletingEveryCheckpointLosesNoUserData() throws {
        // The load-bearing property behind keeping checkpoints out of iCloud: they are scratch.
        let libraryRoot = Fixtures.temporaryDirectory("library")
        defer { try? FileManager.default.removeItem(at: libraryRoot) }

        let projects = ProjectStore(root: libraryRoot, access: DirectFileAccess(), appVersion: "1.0.0")
        let project = try projects.createProject(
            displayName: "Living room", mode: .interior, createdAt: Date(),
            recipe: ProjectRecipe(presetID: "scandi", prompt: "x", isEdited: false,
                                  baseSeed: 1, requestedVariations: 1),
            depthProvenance: .lidar, sourceData: Data("photo".utf8), depthData: Data("depth".utf8),
            sourcePixelWidth: 10, sourcePixelHeight: 10)
        try store.write(checkpoint(step: 4), for: JobID("job"))

        store.discardAll()

        let after = try projects.projects()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.displayName, project.displayName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.sourceURL.path))
    }

    func testTheQueueSurvivesARelaunchAndDropsFinishedWork() {
        var live = Job(id: JobID("live"), request: Fixtures.request(), enqueuedAt: Date())
        live.step = 9
        var done = Job(id: JobID("done"), request: Fixtures.request(variation: 2), enqueuedAt: Date())
        done.phase = .complete(outputID: "out")

        store.saveQueue([live, done])
        let loaded = store.loadQueue()

        XCTAssertEqual(loaded.map(\.id), [JobID("live")], "history belongs in the library, not in scratch")
        XCTAssertEqual(loaded.first?.step, 9)
    }

    func testAnEmptyQueueLeavesNoFileBehind() {
        store.saveQueue([Job(id: JobID("a"), request: Fixtures.request(), enqueuedAt: Date())])
        store.saveQueue([])
        XCTAssertTrue(store.loadQueue().isEmpty)
    }
}

@MainActor
final class StorageChecks: XCTestCase {

    func testTheLocalFallbackIsNotPurgeable() {
        let url = ProjectLocator.localFallbackRoot()
        // `Caches` is purgeable — the system deletes it under pressure, and the user's redesigns
        // are not a cache.
        XCTAssertFalse(url.path.contains("/Caches/"))
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertTrue(url.lastPathComponent == "Documents",
                      "everything the user is promised they can see lives in Documents")
    }

    func testTheTwoLocationsTellTwoDifferentTruths() {
        let cloud = StorageLocation.iCloud(URL(fileURLWithPath: "/cloud"))
        let local = StorageLocation.local(URL(fileURLWithPath: "/local"))
        XCTAssertTrue(cloud.isCloud)
        XCTAssertFalse(local.isCloud)
        XCTAssertNotEqual(StorageText.caption(isCloud: true), StorageText.caption(isCloud: false))
        XCTAssertNotEqual(StorageText.emptyState(isCloud: true), StorageText.emptyState(isCloud: false))
    }

    func testGhostStatesAreDistinguished() {
        // Two states, not one: a folder whose sidecar has not arrived, and a variation whose
        // picture has not.
        let downloading = ItemState(isDownloaded: false, fraction: 0.42)
        let there = ItemState(isDownloaded: true, fraction: 1)
        XCTAssertNotEqual(downloading, there)
        XCTAssertEqual(StorageText.downloading(percent: downloading.fraction), "Downloading 42%")
        XCTAssertEqual(StorageText.downloading(percent: 0), "Not downloaded yet")
    }
}

/// Guards that scan the source, plus negative verification that each one can actually fail.
///
/// A source-scanning guard that has never been shown a violation is a guard nobody knows works.
@MainActor
final class SourceGuardChecks: XCTestCase {

    private func sources() -> [(url: URL, text: String)] {
        Fixtures.swiftFiles(in: Fixtures.sourceDirectory).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url, text)
        }
    }

    func testTheScannerActuallySeesTheSource() {
        // If this is empty every other guard in this file passes vacuously.
        let files = sources()
        XCTAssertGreaterThan(files.count, 20, "the source scan found nothing — the other guards are vacuous")
        XCTAssertTrue(files.contains { $0.url.lastPathComponent == "GlassTreatments.swift" })
    }

    func testNoLegacyMaterialsAnywhere() {
        // `.ultraThinMaterial` and friends are the previous generation, and are what
        // `aisixteen.studio.old` is built on.
        let banned = ["ultraThinMaterial", "regularMaterial", "thinMaterial",
                      "thickMaterial", "ultraThickMaterial"]
        for (url, text) in sources() {
            for token in banned {
                XCTAssertFalse(Self.containsCode(text, token),
                               "\(url.lastPathComponent) uses .\(token)")
            }
        }
    }

    func testGlassEffectIsCalledInExactlyOnePlace() {
        // "A design with even one bare `.glassEffect` call site ships a screen that ignores
        // Reduce Transparency."
        let offenders = sources()
            .filter { Self.containsCode($0.text, ".glassEffect(") }
            .map { $0.url.lastPathComponent }
        XCTAssertEqual(offenders, ["GlassTreatments.swift"],
                       "glass must go through the chokepoint; offenders: \(offenders)")
    }

    func testTheEnvironmentIsReadInExactlyOnePlace() {
        // uitests.md §4b: test hooks must not ship, and `strings | grep` lies about whether a
        // DEBUG-only branch survived.
        let offenders = sources()
            .filter { $0.text.contains("ProcessInfo.processInfo.environment") }
            .map { $0.url.lastPathComponent }
        XCTAssertEqual(offenders, ["LaunchOverride.swift"], "offenders: \(offenders)")
    }

    /// A tripwire, not a rule: these two tokens are deliberately unwired today, and this test
    /// exists so that stops being silently true.
    ///
    /// A test that merely asserts an unused value's properties is a green check on dead weight —
    /// it makes a behaviour look verified when nothing calls it. This asserts the actual current
    /// state instead, so **wiring either token FAILS this test**, which is the point: the failure
    /// is the prompt to delete the "DECLARED AND NOT WIRED" markers in `Motion.swift`, retitle the
    /// two `_notYetWired` tests, and remove this guard.
    func testTheUnwiredMotionTokensAreStillUnwired() {
        for token in ["cancelReverse", "glassTransition"] {
            let callSites = sources()
                .filter { $0.url.lastPathComponent != "Motion.swift" }
                .filter { Self.containsCode($0.text, token) }
                .map { $0.url.lastPathComponent }
            XCTAssertTrue(callSites.isEmpty,
                          "`\(token)` is now called from \(callSites) — good. Remove its "
                          + "DECLARED AND NOT WIRED note in Motion.swift, drop the `_notYetWired` "
                          + "suffix from its test, and delete this guard.")
        }
    }

    // ── negative verification ────────────────────────────────────────────────────────────────

    func testEachGuardCatchesViolationsShapedUnlikeTheOnesIThoughtOf() {
        // Every guard above is only worth having if it fails when it should. These are deliberately
        // awkward shapes: trailing whitespace, a line continuation, an inline call mid-expression,
        // a labelled argument.
        XCTAssertTrue(Self.containsCode("Rectangle().background(.ultraThinMaterial)", "ultraThinMaterial"))
        XCTAssertTrue(Self.containsCode("  .background (\n    .regularMaterial )", "regularMaterial"))
        XCTAssertTrue(Self.containsCode("let v = a ? x.glassEffect(in: c) : y", ".glassEffect("))
        XCTAssertTrue(Self.containsCode("foo(bar: baz.glassEffect(  in: Circle()))", ".glassEffect("))

        // …and does NOT fire on the things that legitimately mention them.
        XCTAssertFalse(Self.containsCode("// never use .ultraThinMaterial here", "ultraThinMaterial"))
        XCTAssertFalse(Self.containsCode("/// `.glassEffect(` is banned outside this file", ".glassEffect("))
        XCTAssertFalse(Self.containsCode("    /* .glassEffect( */", ".glassEffect("))
    }

    /// True when `token` appears in real code rather than in a comment.
    ///
    /// Comment stripping is line-based and deliberately simple; the negative tests above are what
    /// establish it handles the shapes that actually occur.
    static func containsCode(_ text: String, _ token: String) -> Bool {
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            if let range = line.range(of: "//") { line = String(line[line.startIndex..<range.lowerBound]) }
            if let range = line.range(of: "/*") { line = String(line[line.startIndex..<range.lowerBound]) }
            if line.contains(token) { return true }
        }
        return false
    }
}

/// The words the app is allowed to say about where things are kept.
@MainActor
final class CopyChecks: XCTestCase {

    func testNoStorageStringImpliesAnAccountOrAService() {
        // iCloud here is the user's own folder. There is nothing to sign in to and nothing that can
        // be taken away, and the copy has to keep being true about that.
        let strings = [StorageText.iCloudCaption, StorageText.localCaption,
                       StorageText.iCloudEmpty, StorageText.localEmpty]
        for string in strings {
            for word in StorageText.forbiddenWords {
                XCTAssertFalse(string.lowercased().contains(word), "\"\(string)\" contains \"\(word)\"")
            }
        }
    }

    func testNoUserFacingStringPromisesBackgroundWork() {
        // This build is foreground-only by decision. A string that says the render continues while
        // the app is closed would be a promise the platform will not keep.
        let banned = ["while you're away", "even when closed", "in the background",
                      "keeps going when you leave", "continues after you close"]
        for (url, text) in Fixtures.swiftFiles(in: Fixtures.sourceDirectory).compactMap({ url -> (URL, String)? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url, text)
        }) {
            for phrase in banned {
                XCTAssertFalse(text.lowercased().contains(phrase),
                               "\(url.lastPathComponent) promises background work")
            }
        }
    }

    func testThePauseCopyIsTheHandoffsAndSaysWhatResumesIt() {
        XCTAssertEqual(GenerationPause.backgroundSuspended.title, "Waiting for you.")
        XCTAssertEqual(GenerationPause.phoneCall.title, "Paused during your call.")
        XCTAssertEqual(GenerationPause.thermal.title, "Running slower to keep the phone cool.")
        XCTAssertEqual(GenerationPause.lowBattery.title, "Paused at 10% battery.")
        // Each detail says what resumes it — that is the grammar all four share.
        for pause in GenerationPause.allCases {
            XCTAssertFalse(pause.detail.isEmpty)
            XCTAssertTrue(pause.detail.count > 20, "\(pause) has no explanation")
        }
    }

    func testTheCompletionNotificationCountsTheQueueHonestly() {
        XCTAssertEqual(RenderNotifier.body(spaceName: "Living room", styleName: "Scandinavian",
                                           remainingInQueue: 0),
                       "Your scandinavian living room is ready.")
        XCTAssertEqual(RenderNotifier.body(spaceName: "Living room", styleName: "Scandinavian",
                                           remainingInQueue: 1),
                       "Your scandinavian living room is ready. One more on the way.")
        XCTAssertEqual(RenderNotifier.body(spaceName: "Living room", styleName: "Scandinavian",
                                           remainingInQueue: 2),
                       "Your scandinavian living room is ready. 2 more on the way.")
    }
}
