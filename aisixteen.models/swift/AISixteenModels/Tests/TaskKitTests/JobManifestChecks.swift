import Testing
import Foundation
import ModelKit
@testable import TaskKit

private let when = Date(timeIntervalSince1970: 1_786_000_000)

private let diffusion = ModelUse(role: .generate, id: "sd15cn", fingerprint: "abc123")
private let enlarger = ModelUse(role: .upscale, id: "realesrgan4x", fingerprint: "def456")
private let refiner = ModelUse(role: .refine, id: "sd15cn", fingerprint: "abc123")

private func manifest(prompt: String = "a slate coastline under fog",
                      seed: UInt32 = 7,
                      steps: Int = 28,
                      strength: Double = 0.35,
                      origins: [JobManifest.Origin] = [.init(x: 0, y: 0), .init(x: 448, y: 0)],
                      models: [ModelUse] = [diffusion, enlarger],
                      stage: JobManifest.Stage = .refining(tile: 1, of: 4)) -> JobManifest {
    JobManifest(id: "job-1",
                kind: .enhance(recordID: "rec-1"),
                prompt: prompt,
                negativePrompt: "worst quality",
                seed: seed,
                steps: steps,
                guidanceScale: 7.5,
                aspect: .phone,
                strength: strength,
                tile: 512,
                overlap: 64,
                workingSide: 1024,
                origins: origins,
                models: models,
                stage: stage,
                startedAt: when,
                updatedAt: when)
}

/// ORACLES:
///  • INVARIANT — a manifest survives a JSON round trip unchanged. It is written to disk and read
///    back by a *different launch of the process*; anything lost in that trip is state the resume
///    silently gets wrong.
///  • BEHAVIOUR — every parameter that can change a pixel must invalidate reuse, and nothing that
///    cannot may invalidate it. Both directions matter: too strict and resumption never fires, too
///    loose and two different pictures get spliced together.
/// MODEL CAVEAT: this suite decides whether work *may* be reused. Whether the restored diffusion
/// state actually reproduces the same picture is a separate check that needs a real model — the
/// split-run equality test.
@Suite("JobManifest — is this still the same work?")
struct JobManifestTests {

    @Test("a manifest survives being written and read back")
    func roundTrip() throws {
        let original = manifest()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(JobManifest.self, from: try encoder.encode(original))
        #expect(back == original)
    }

    @Test("every generative parameter invalidates reuse")
    func differencesInvalidate() {
        let base = manifest()
        #expect(!base.describesSameWork(as: manifest(prompt: "something else")))
        #expect(!base.describesSameWork(as: manifest(seed: 8)))
        #expect(!base.describesSameWork(as: manifest(steps: 20)))
        #expect(!base.describesSameWork(as: manifest(strength: 0.5)))
        #expect(!base.describesSameWork(as: manifest(origins: [.init(x: 0, y: 0)])))
        // A different model, and a different *build* of the same model, are both differences.
        #expect(!base.describesSameWork(as: manifest(models: [
            ModelUse(role: .generate, id: "sdxl", fingerprint: "abc123"), enlarger])))
        #expect(!base.describesSameWork(as: manifest(models: [
            ModelUse(role: .generate, id: "sd15cn", fingerprint: "rebuilt"), enlarger])))
        // And so is a stage that used a model this job did not, or stopped using one it did.
        #expect(!base.describesSameWork(as: manifest(models: [diffusion])))
        #expect(!base.describesSameWork(as: manifest(models: [diffusion, enlarger, refiner])))
    }

    @Test("the order models were discovered in is not a difference")
    func modelOrderDoesNotMatter() {
        // The installed list is built by walking directories, and nothing guarantees the order twice
        // running. If order counted, resumption would fire or not at random.
        #expect(manifest(models: [diffusion, enlarger])
            .describesSameWork(as: manifest(models: [enlarger, diffusion])))
    }

    @Test("progress is not a generative parameter and must not invalidate reuse")
    func progressDoesNotInvalidate() {
        // The whole point: a job that got further is still the same job. If `stage` were compared,
        // resumption could never fire — the stored manifest always differs from the fresh one.
        let base = manifest(stage: .refining(tile: 1, of: 4))
        let further = manifest(stage: .refining(tile: 3, of: 4))
        #expect(base.describesSameWork(as: further))
    }

    @Test("a finished job is never offered, and neither is one whose models have moved")
    func offerRules() {
        let installed = [diffusion, enlarger, refiner]
        let unfinished = manifest(stage: .refining(tile: 2, of: 4))

        #expect(unfinished.canBeResumed(with: installed))
        #expect(!manifest(stage: .finishing).canBeResumed(with: installed))

        // Any model the job used, gone or rebuilt, kills it — including the *upscaler*, which the
        // first version of this did not record at all. A changed enlarger with the diffusion pack
        // untouched would have resumed happily and blended two networks' tiles across the overlap.
        #expect(!unfinished.canBeResumed(with: [diffusion, refiner]))
        #expect(!unfinished.canBeResumed(with: [
            diffusion, refiner, ModelUse(role: .upscale, id: "ultrasharp4x", fingerprint: "def456")]))
        #expect(!unfinished.canBeResumed(with: [
            diffusion, refiner, ModelUse(role: .upscale, id: "realesrgan4x", fingerprint: "rebuilt")]))
        #expect(!unfinished.canBeResumed(with: []))
    }

    @Test("a job is not punished for models it never used")
    func extraModelsAreFine() {
        // Adding an upscaler pack must not invalidate an Enhance that only ever refined.
        let enhanceOnly = manifest(models: [refiner], stage: .refining(tile: 2, of: 4))
        #expect(enhanceOnly.canBeResumed(with: [refiner]))
        #expect(enhanceOnly.canBeResumed(with: [diffusion, enlarger, refiner]))
    }

    @Test("the same model serving two subtasks is two records, and both are checked")
    func subtasksAreSeparate() {
        // Stages 1 and 3 run the same pack today. Recorded per subtask so the day they diverge, a
        // manifest written before it still means what it said.
        let both = manifest(models: [diffusion, refiner], stage: .diffusing(step: 4, of: 28))
        #expect(both.canBeResumed(with: [diffusion, refiner]))
        #expect(!both.canBeResumed(with: [diffusion]), "the refine model was not checked")
        #expect(!both.canBeResumed(with: [refiner]), "the generate model was not checked")
    }

    @Test("the chip keeps the numbers when it drops the words")
    func chipSummary() {
        // The one abbreviation that would be wrong is turning a count into a percentage. Units may
        // go; the numerator and denominator may not.
        #expect(JobManifest.Stage.refining(tile: 2, of: 9).chipSummary == "enhancing · 2 of 9")
        #expect(JobManifest.Stage.diffusing(step: 17, of: 28).chipSummary == "generating · 17 of 28")
        #expect(JobManifest.Stage.upscaling(tile: 6, of: 9).chipSummary == "enlarging · 6 of 9")
        for stage in [JobManifest.Stage.refining(tile: 2, of: 9),
                      .diffusing(step: 17, of: 28),
                      .upscaling(tile: 6, of: 9)] {
            #expect(!stage.chipSummary.contains("%"), "a count must never become a percentage")
            #expect(stage.chipSummary.count < 26, "it has to fit a one-line chip")
        }
    }

    @Test("the stage summary uses the same words the job used while running")
    func stageSummary() {
        #expect(JobManifest.Stage.diffusing(step: 17, of: 28).summary == "generating, step 17 of 28")
        #expect(JobManifest.Stage.refining(tile: 2, of: 4).summary == "enhancing, 2 of 4 tiles")
        #expect(JobManifest.Stage.upscaling(tile: 6, of: 9).summary == "enlarging, 6 of 9 tiles")
    }
}

/// ORACLES:
///  • INVARIANT — the ledger reports exactly the tiles present, and asks for exactly those absent.
///    A tile wrongly reported done is a missing patch of picture that nothing will ever report.
///  • BEHAVIOUR — unrecognised files are ignored rather than treated as corruption.
@Suite("TileLedger — what is left to do")
struct TileLedgerTests {

    @Test("filenames are zero-padded so they sort in working order")
    func filenames() {
        #expect(TileLedger.filename(0) == "tile-000.png")
        #expect(TileLedger.filename(7) == "tile-007.png")
        #expect(TileLedger.filename(15) == "tile-015.png")
        #expect(["tile-010.png", "tile-002.png"].sorted() == ["tile-002.png", "tile-010.png"])
    }

    @Test("completed indices are read back from a listing")
    func completed() {
        let found = TileLedger.completed(in: ["tile-000.png", "tile-003.png", "tile-012.png"])
        #expect(found == [0, 3, 12])
    }

    @Test("files we did not write are ignored, not fatal")
    func foreignFiles() {
        let found = TileLedger.completed(in: [".DS_Store", "job.json", "tile-001.png", "notes.txt",
                                              "tile-abc.png", "tile-002.jpg"])
        #expect(found == [1], "only well-formed tile files count")
    }

    @Test("remaining is exactly the gaps, in order")
    func remaining() {
        #expect(TileLedger.remaining(total: 4, completed: [0, 2]) == [1, 3])
        #expect(TileLedger.remaining(total: 4, completed: []) == [0, 1, 2, 3])
        #expect(TileLedger.remaining(total: 4, completed: [0, 1, 2, 3]).isEmpty)
    }

    @Test("a ledger from a larger grid cannot suppress work in a smaller one")
    func staleLedgerDoesNotHideWork() {
        // Second line of defence: the manifest already refuses to resume across a grid change, and
        // the failure this guards against — a silently missing patch of picture — is bad enough to
        // deserve two.
        #expect(TileLedger.remaining(total: 4, completed: [0, 1, 2, 3, 9, 15]) == [])
        #expect(TileLedger.remaining(total: 4, completed: [9, 15]) == [0, 1, 2, 3])
    }

    @Test("progress counts only tiles inside the grid")
    func progress() {
        #expect(TileLedger.progress(total: 4, completed: [0, 1]) == (2, 4))
        #expect(TileLedger.progress(total: 4, completed: [0, 1, 9]) == (2, 4))
        #expect(TileLedger.progress(total: 0, completed: []) == (0, 0))
    }
}
