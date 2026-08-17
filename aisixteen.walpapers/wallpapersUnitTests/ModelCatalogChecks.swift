import XCTest
import GenerationKit
import TaskKit
@testable import Wallpapers

/// Which models are installed, and which subtask each one serves.
///
/// The app is about to have more than one model to choose between, and every piece of stored work
/// records what made it. Two failures matter here and neither is loud:
///
/// * **Mislabelling a pack.** A future pack read as the model it is not would run with the wrong
///   native size and the wrong assumptions about what is inside it.
/// * **Forgetting a stage's model.** Every job used to record only the diffusion pack. Swap the
///   ESRGAN model and the stored stage-2 tiles are stale, but the job still says it is resumable —
///   the resumed enlargement is then half one network and half another, blended across the overlap.
final class ModelCatalogChecks: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = makeTemporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: The pack declares itself

    func testADeclaredPackIsIdentifiedByItsID() throws {
        try write(declaration: #"{"id": "sd15cn", "family": "sd15", "nativeSide": 512}"#)
        let model = try XCTUnwrap(ModelCatalog.installed(at: root))
        XCTAssertEqual(model.id, "sd15cn")
        XCTAssertEqual(model.nativeSide, 512)
        XCTAssertTrue(model.hasControlNet)
    }

    func testAPackFromANewerBuildIsRefusedRatherThanGuessedAt() throws {
        // The pack is produced by a script in another repository and shipped separately, so a build
        // will eventually meet an id it has never heard of. Running it as though it were the model
        // this build does know would use the wrong native size against fixed-shape Core ML graphs.
        try write(declaration: #"{"id": "sdxl-turbo-9000"}"#)
        XCTAssertNil(ModelCatalog.installed(at: root))
    }

    func testAMalformedDeclarationDoesNotCrashOrLie() throws {
        try write(declaration: "{ this is not json")
        XCTAssertNil(ModelCatalog.installed(at: root),
                     "a corrupt declaration must not fall through to a guess")
    }

    func testTheDeclarationWinsOverTheShapeOnDisk() throws {
        // A pack that says what it is beats inference, always. Otherwise a future SDXL pack that
        // happened to ship a ControlNet directory would be read as sd15cn.
        try makeLegacyShape()
        try write(declaration: #"{"id": "sdxl-turbo-9000"}"#)
        XCTAssertNil(ModelCatalog.installed(at: root))
    }

    // MARK: Packs that predate the declaration

    func testThePackAlreadyOnTheDeviceIsStillRecognised() throws {
        // Converted before `model.json` existed, and installed on at least one phone.
        try makeLegacyShape()
        XCTAssertEqual(ModelCatalog.installed(at: root)?.id, "sd15cn")
    }

    func testTheFallbackIsNarrowEnoughToBeSafe() throws {
        // Inference is a stopgap for one known pack. Anything that is not exactly that shape must
        // come back nil rather than be optimistically labelled.
        XCTAssertNil(ModelCatalog.installed(at: root), "an empty directory is not a model")

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("ControlledUnet.mlmodelc"), withIntermediateDirectories: true)
        XCTAssertNil(ModelCatalog.installed(at: root), "a unet alone is not the Tile pack")

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("controlnet/SomethingElse.mlmodelc"),
            withIntermediateDirectories: true)
        XCTAssertNil(ModelCatalog.installed(at: root), "some other ControlNet is not the Tile one")
    }

    // MARK: The whole pipeline, from the real bundle

    func testEverySubtaskThatCanBeServedIsReported() throws {
        let installed = ModelCatalog.installedModels()
        try XCTSkipIf(installed.isEmpty, "No models in this bundle.")

        // Stages 1 and 3 come from the same pack today and are still two records, because they are
        // two subtasks. The day they are served by different packs, manifests written before it must
        // still mean what they said.
        let byRole = Dictionary(grouping: installed, by: \.role)
        XCTAssertEqual(byRole[.generate]?.count, 1)
        XCTAssertEqual(byRole[.refine]?.count, 1, "the Tile pack should serve refinement")
        XCTAssertEqual(byRole[.generate]?.first?.id, byRole[.refine]?.first?.id)

        for use in installed {
            XCTAssertFalse(use.id.isEmpty)
            XCTAssertEqual(use.fingerprint.count, 16, "\(use.role) has no usable fingerprint")
        }
    }

    func testTheUpscalerIsIdentifiedAndFingerprintedLikeAnyOtherModel() throws {
        try XCTSkipIf(Upscaler.bundledModelURL() == nil, "No upscaler in this bundle.")
        let use = try XCTUnwrap(ModelCatalog.installedModel(for: .upscale),
                                "stage 2's model was not recorded at all — the original bug")
        XCTAssertEqual(use.id, Upscaler.installedID)
        XCTAssertNotEqual(use.fingerprint,
                          ModelCatalog.installedModel(for: .generate)?.fingerprint,
                          "the enlarger is being fingerprinted as if it were the diffusion pack")
    }

    // MARK: -

    private func write(declaration: String) throws {
        try Data(declaration.utf8).write(to: root.appendingPathComponent(ModelCatalog.declarationFilename))
    }

    /// The shape of the pack that shipped before declarations existed.
    private func makeLegacyShape() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("ControlledUnet.mlmodelc"),
                                    withIntermediateDirectories: true)
        try manager.createDirectory(
            at: root.appendingPathComponent("controlnet/LllyasvielControlV11F1ESd15Tile.mlmodelc"),
            withIntermediateDirectories: true)
    }
}
