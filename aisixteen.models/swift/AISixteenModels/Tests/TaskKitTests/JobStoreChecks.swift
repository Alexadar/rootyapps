import XCTest
import CoreML
import CoreGraphics
import ModelKit
@testable import TaskKit

/// The disk half of resumability.
///
/// `JobKit` decides *whether* half-finished work may be reused, and is tested without a filesystem.
/// This suite covers the part that can only fail against real files: the checkpoint codec, tiles
/// surviving a write/read cycle, and discovery across what is effectively a second launch.
///
/// The checkpoint codec gets the most attention because its failure mode is the quiet one. A lossy
/// round trip does not crash and does not throw — it resumes into slightly different latents and
/// produces a *slightly different picture from the same seed*, which reads as a flaw in the model.
/// So the assertion is exact equality of every scalar, not approximate.
final class JobStoreChecks: XCTestCase {

    private var sandbox: URL!
    private var realRoot: URL!

    override func setUp() {
        super.setUp()
        realRoot = JobStore.jobsRoot
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("job-store-checks-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        JobStore.jobsRoot = sandbox
    }

    override func tearDown() {
        JobStore.jobsRoot = realRoot
        try? FileManager.default.removeItem(at: sandbox)
        super.tearDown()
    }

    private func manifest(id: String = "job-1",
                          prompt: String = "a slate coastline under fog",
                          fingerprint: String = "model-a",
                          updatedAt: Date = Date(timeIntervalSince1970: 1_786_000_000),
                          stage: JobManifest.Stage = .refining(tile: 1, of: 4)) -> JobManifest {
        JobManifest(id: id,
                    kind: .enhance(recordID: "rec-1"),
                    prompt: prompt,
                    negativePrompt: "worst quality",
                    seed: 7,
                    steps: 28,
                    guidanceScale: 7.5,
                    aspect: .phone,
                    strength: 0.35,
                    tile: 512,
                    overlap: 64,
                    workingSide: 1024,
                    origins: [.init(x: 0, y: 0), .init(x: 448, y: 0)],
                    models: [ModelUse(role: .generate, id: "sd15cn", fingerprint: fingerprint)],
                    stage: stage,
                    startedAt: Date(timeIntervalSince1970: 1_786_000_000),
                    updatedAt: updatedAt)
    }

    // MARK: The checkpoint codec

    private func checkpoint() -> JobStore.Checkpoint {
        // The real shapes: a classifier-free-guidance latent batch and the two scheduler outputs
        // `DPMSolverMultistep` carries. Small enough to compare scalar by scalar, same rank and
        // layout as the thing that actually gets written.
        func array(_ seed: Int) -> MLShapedArray<Float32> {
            let count = 2 * 4 * 8 * 8
            let scalars = (0..<count).map { Float32(sin(Double($0 + seed))) }
            return MLShapedArray<Float32>(scalars: scalars, shape: [2, 4, 8, 8])
        }
        return JobStore.Checkpoint(step: 14,
                                   lowerOrderStepped: 2,
                                   latents: [array(0)],
                                   modelOutputs: [array(100), array(200)])
    }

    func testACheckpointRoundTripsWithoutLosingASingleScalar() throws {
        let original = checkpoint()
        let data = try XCTUnwrap(JobStore.encode(original))
        let back = try XCTUnwrap(JobStore.decode(data))

        XCTAssertEqual(back.step, original.step)
        XCTAssertEqual(back.lowerOrderStepped, original.lowerOrderStepped)
        XCTAssertEqual(back.latents.count, original.latents.count)
        XCTAssertEqual(back.modelOutputs.count, original.modelOutputs.count)

        for (restored, expected) in zip(back.latents + back.modelOutputs,
                                        original.latents + original.modelOutputs) {
            XCTAssertEqual(restored.shape, expected.shape, "shape lost in the round trip")
            XCTAssertEqual(restored.scalars, expected.scalars,
                           "exact equality, not approximate — a last-bit difference here resumes "
                           + "into a different picture from the same seed")
        }
    }

    func testTheCodecSurvivesTheAwkwardFloats() throws {
        // Denormals, infinities and a NaN. These are what a text-based format quietly mangles, and
        // latents mid-schedule do reach very small magnitudes.
        let odd: [Float32] = [0, -0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
                              .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
                              .infinity, -.infinity, .nan]
        let source = JobStore.Checkpoint(
            step: 0, lowerOrderStepped: 0,
            latents: [MLShapedArray<Float32>(scalars: odd, shape: [odd.count])],
            modelOutputs: [])
        let back = try XCTUnwrap(JobStore.decode(try XCTUnwrap(JobStore.encode(source))))
        let scalars = back.latents[0].scalars

        XCTAssertEqual(scalars.count, odd.count)
        for (restored, expected) in zip(scalars, odd) where !expected.isNaN {
            XCTAssertEqual(restored.bitPattern, expected.bitPattern,
                           "compared bit-for-bit, so -0 and 0 are not confused")
        }
        XCTAssertTrue(scalars.last!.isNaN, "a NaN must come back a NaN, not a zero")
    }

    func testATruncatedCheckpointIsRefusedRatherThanDecodedIntoNonsense() throws {
        let data = try XCTUnwrap(JobStore.encode(checkpoint()))
        // A crash during the write is exactly how a short file appears. Half a latent restored as
        // if it were whole is worse than starting the stage again.
        XCTAssertNil(JobStore.decode(data.prefix(data.count - 4)))
        XCTAssertNil(JobStore.decode(data.prefix(8)))
        XCTAssertNil(JobStore.decode(Data()))
    }

    func testAnEmptyCheckpointIsStillAValidOne() throws {
        // Step zero, before the scheduler has produced anything. The decoder must not treat "no
        // model outputs yet" as corruption.
        let source = JobStore.Checkpoint(step: 0, lowerOrderStepped: 0, latents: [], modelOutputs: [])
        let back = try XCTUnwrap(JobStore.decode(try XCTUnwrap(JobStore.encode(source))))
        XCTAssertEqual(back.step, 0)
        XCTAssertTrue(back.latents.isEmpty)
        XCTAssertTrue(back.modelOutputs.isEmpty)
    }

    func testACheckpointSurvivesTheDiskAndIsAbsentBeforeOneIsWritten() throws {
        let store = JobStore(manifest: manifest())
        try store.begin()
        XCTAssertNil(store.readCheckpoint(), "a fresh job has nothing to resume from")

        store.writeCheckpoint(checkpoint())
        let back = try XCTUnwrap(store.readCheckpoint())
        XCTAssertEqual(back.step, 14)
        XCTAssertEqual(back.latents[0].scalars, checkpoint().latents[0].scalars)
    }

    // MARK: Tiles

    func testATileComesBackTheSizeItWentIn() throws {
        let store = JobStore(manifest: manifest())
        try store.begin()
        let tiles = store.tiles(.refine)
        try tiles.prepare()
        XCTAssertTrue(tiles.completed().isEmpty)

        try tiles.store(Self.solidImage(side: 64), at: 3)
        XCTAssertEqual(tiles.completed(), [3], "only the tile actually written counts")

        let back = try XCTUnwrap(tiles.load(3))
        XCTAssertEqual(back.width, 64)
        XCTAssertEqual(back.height, 64)
        XCTAssertNil(tiles.load(0), "a tile never written must read as absent, not as blank")
    }

    func testTheTwoStagesCannotReadEachOthersTiles() throws {
        // Both number their tiles from zero over different grids. One shared directory would let
        // stage 2's tile 0 be restored as stage 3's — a patch of the right picture at the wrong
        // scale, blended in, with nothing reporting a problem.
        let store = JobStore(manifest: manifest())
        try store.begin()
        let upscale = store.tiles(.upscale), refine = store.tiles(.refine)
        try upscale.prepare()
        try refine.prepare()

        try upscale.store(Self.solidImage(side: 64), at: 0)

        XCTAssertEqual(upscale.completed(), [0])
        XCTAssertTrue(refine.completed().isEmpty, "stage 3 saw stage 2's work as its own")
        XCTAssertNil(refine.load(0))
    }

    func testClearingOneStageLeavesTheOtherAlone() throws {
        let store = JobStore(manifest: manifest())
        try store.begin()
        let upscale = store.tiles(.upscale), refine = store.tiles(.refine)
        try upscale.prepare()
        try refine.prepare()
        try upscale.store(Self.solidImage(side: 32), at: 0)
        try refine.store(Self.solidImage(side: 32), at: 0)

        // Stage 2's tiles are consumed once its canvas is composed; keeping them would let stage 3
        // of a later identical job resume into work already spent.
        upscale.clear()
        XCTAssertTrue(upscale.completed().isEmpty)
        XCTAssertEqual(refine.completed(), [0])
    }

    // MARK: Discovery, as a second launch sees it

    func testAnInterruptedJobIsOfferedAndAFinishedOneIsNot() throws {
        try JobStore(manifest: manifest(id: "unfinished")).begin()

        let done = JobStore(manifest: manifest(id: "done"))
        try done.begin()
        done.record(stage: .finishing)

        let offered = JobStore.resumableJobs(matching: Self.installed("model-a"))
        XCTAssertEqual(offered.map(\.id), ["unfinished"])
    }

    func testAJobFromAnotherModelIsDeletedRatherThanOffered() throws {
        try JobStore(manifest: manifest(id: "stale", fingerprint: "model-a")).begin()

        // The model arrives as an asset pack and can be updated underneath a paused job. Offering
        // to resume it would promise a picture that can no longer be produced.
        XCTAssertTrue(JobStore.resumableJobs(matching: Self.installed("model-b")).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            JobStore.jobsRoot.appendingPathComponent("stale").path),
            "an unofferable job must not be left on disk taking up space forever")
    }

    func testJobsTouchedInTheSameMillisecondStillHaveAnOrder() throws {
        // Not a nicety: without a tie-break the resume card offers whichever job the filesystem
        // happened to enumerate first, and the same app state produces different offers on
        // different launches.
        for id in ["b", "a", "c"] {
            try JobStore(manifest: manifest(id: id)).begin()
        }
        let twice = (0..<2).map { _ in JobStore.resumableJobs(matching: Self.installed("model-a")).map(\.id) }
        XCTAssertEqual(twice[0], twice[1], "the same jobs came back in a different order")
        XCTAssertEqual(twice[0], ["c", "b", "a"])
    }

    func testTheMostRecentlyTouchedJobComesFirst() throws {
        try JobStore(manifest: manifest(id: "older",
                                        updatedAt: Date(timeIntervalSince1970: 1_786_000_000),
                                        stage: .refining(tile: 1, of: 4))).begin()
        try JobStore(manifest: manifest(id: "newer",
                                        updatedAt: Date(timeIntervalSince1970: 1_786_000_060),
                                        stage: .refining(tile: 2, of: 4))).begin()

        XCTAssertEqual(JobStore.resumableJobs(matching: Self.installed("model-a")).first?.id, "newer")
    }

    func testRecordingProgressSurvivesToTheNextLaunch() throws {
        let store = JobStore(manifest: manifest(id: "in-flight"))
        try store.begin()
        store.record(stage: .refining(tile: 3, of: 4))

        let seen = try XCTUnwrap(JobStore.resumableJobs(matching: Self.installed("model-a")).first)
        XCTAssertEqual(seen.stage, .refining(tile: 3, of: 4))
        XCTAssertEqual(seen.stage.summary, "enhancing, 3 of 4 tiles")
    }

    func testOnlyAFewInterruptedJobsSurviveALaunch() throws {
        // Every abandoned job costs a checkpoint plus its upscale tiles. Without a cap they
        // accumulate for the life of the install, and only the newest is ever offered.
        // Timestamps set explicitly rather than by writing in a loop: `updatedAt` is stored to the
        // millisecond, and six jobs written back to back land inside one — which tests the
        // tie-break, not the ordering.
        for index in 0..<(JobStore.keptJobs + 3) {
            try JobStore(manifest: manifest(
                id: "job-\(index)",
                updatedAt: Date(timeIntervalSince1970: 1_786_000_000 + Double(index)),
                stage: .diffusing(step: index, of: 28))).begin()
        }

        let kept = JobStore.resumableJobs(matching: Self.installed("model-a"))
        XCTAssertEqual(kept.count, JobStore.keptJobs)
        XCTAssertEqual(kept.first?.id, "job-\(JobStore.keptJobs + 2)", "the newest must be first")

        let onDisk = try FileManager.default.contentsOfDirectory(atPath: JobStore.jobsRoot.path)
        XCTAssertEqual(onDisk.count, JobStore.keptJobs, "the older jobs are still taking up space")
    }

    func testDiscardRemovesEverything() throws {
        let store = JobStore(manifest: manifest(id: "unwanted"))
        try store.begin()
        let tiles = store.tiles(.refine)
        try tiles.prepare()
        try tiles.store(Self.solidImage(side: 32), at: 0)
        store.writeCheckpoint(checkpoint())

        store.discard()
        XCTAssertTrue(JobStore.resumableJobs(matching: Self.installed("model-a")).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            JobStore.jobsRoot.appendingPathComponent("unwanted").path))
    }

    func testAJunkDirectoryIsIgnoredRatherThanFatal() throws {
        try JobStore(manifest: manifest(id: "good")).begin()
        let junk = JobStore.jobsRoot.appendingPathComponent("not-a-job", isDirectory: true)
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: junk.appendingPathComponent("job.json"))

        XCTAssertEqual(JobStore.resumableJobs(matching: Self.installed("model-a")).map(\.id), ["good"])
    }

    /// What `ModelCatalog` would report with a given diffusion build installed.
    private static func installed(_ fingerprint: String) -> [ModelUse] {
        [ModelUse(role: .generate, id: "sd15cn", fingerprint: fingerprint)]
    }

    // MARK: Model fingerprint, against a real directory

    func testAModelBundleIsSizedByItsContentsNotItsDirectoryEntry() throws {
        // Compiled Core ML models are DIRECTORIES. `fileSize` is nil for a directory, so summing it
        // naively fingerprinted every model as `name:0:mtime` — the size component looked live and
        // contributed nothing. Measured: ControlledUnet.mlmodelc reports 224 bytes as a directory
        // entry against 648 MB of contents.
        let bundle = sandbox.appendingPathComponent("Unet.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("weights"),
                                                withIntermediateDirectories: true)
        try Data(repeating: 7, count: 5_000).write(to: bundle.appendingPathComponent("model.espresso"))
        try Data(repeating: 9, count: 3_000)
            .write(to: bundle.appendingPathComponent("weights/0.bin"))

        XCTAssertEqual(JobStore.bytes(of: bundle), 8_000,
                       "a model bundle must be sized by walking into it")
    }

    func testReinstallingTheAppDoesNotStrandPausedJobs() throws {
        // Modification dates change on every reinstall and every TestFlight update even when the
        // bytes are identical. A fingerprint that moved with them answered "was this app
        // reinstalled" when it was asked "are these the same weights", and threw away resumable
        // work for it.
        let resources = sandbox.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let model = resources.appendingPathComponent("Unet.mlmodelc")
        try Data(repeating: 0, count: 4_096).write(to: model)

        let before = JobStore.fingerprint(ofModelAt: resources)
        // An hour later, not `Date()`. `ModelFingerprint` truncates to whole seconds, so touching a
        // file that was written moments ago produces the identical string and the test passes for
        // the wrong reason — it did, until this line was widened.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)],
                                              ofItemAtPath: model.path)
        XCTAssertEqual(before, JobStore.fingerprint(ofModelAt: resources),
                       "a touched mtime is not a changed model")
    }

    func testTheFingerprintChangesWhenTheModelFilesDo() throws {
        let resources = sandbox.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let unet = resources.appendingPathComponent("Unet.mlmodelc")
        try Data(repeating: 0, count: 1024).write(to: unet)

        let before = JobStore.fingerprint(ofModelAt: resources)
        XCTAssertEqual(before.count, 16)
        XCTAssertEqual(before, JobStore.fingerprint(ofModelAt: resources), "unstable between calls")

        try Data(repeating: 0, count: 2048).write(to: unet)
        XCTAssertNotEqual(before, JobStore.fingerprint(ofModelAt: resources),
                          "a changed byte count must change the fingerprint")
    }

    func testAMissingModelDirectoryStillYieldsAFingerprint() {
        // Before the asset pack has downloaded. It must produce *some* stable value rather than
        // crash — and one that differs from a real model, so nothing resumes against nothing.
        let missing = sandbox.appendingPathComponent("nowhere")
        XCTAssertEqual(JobStore.fingerprint(ofModelAt: missing).count, 16)
    }

    // MARK: Helpers

    private static func solidImage(side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()!
    }
}
