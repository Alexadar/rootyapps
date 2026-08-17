import Foundation
import DirectionKit
import Observation
import ProjectKit
import RedesignKit
import SwiftUI

/// Turns "the user tapped Redesign" into a project on disk and N jobs in the queue, and puts each
/// finished variation back on disk.
///
/// It exists so `RedesignEngine` never has to know what a project is and `ProjectLibrary` never
/// has to know what a job is. The engine renders; the library stores; this decides what a render
/// means.
@MainActor
@Observable
final class RedesignCoordinator {

    let engine: RedesignEngine
    let library: ProjectLibrary
    let router: Router

    /// Project id → the folder it renders into.
    @ObservationIgnored private var folders: [String: URL] = [:]
    @ObservationIgnored private var startedAt: [JobID: Date] = [:]

    init(engine: RedesignEngine, library: ProjectLibrary, router: Router) {
        self.engine = engine
        self.library = library
        self.router = router
        engine.onVariationFinished = { [weak self] job, output in
            await self?.absorb(job, output: output)
        }
    }

    // ── starting ─────────────────────────────────────────────────────────────────────────────

    /// Create the project, then enqueue one job per variation.
    ///
    /// The project is written FIRST, and deliberately: the source photo and the depth map have to
    /// exist on disk before a request can point at them, and if the app dies mid-render the user
    /// still has the photo they took and the words they wrote.
    func start(shot: SourceShot,
               recipe: PromptRecipe,
               variations: Int) throws {
        let seed = UInt32.random(in: 1...UInt32.max)
        let mode: ProjectKit.SpaceMode = shot.mode == .interior ? .interior : .exterior
        let name = ProjectFolderName.automaticDisplayName(mode: mode, createdAt: Date())

        let projectRecipe = ProjectRecipe(presetID: recipe.presetID,
                                          prompt: recipe.prompt,
                                          isEdited: recipe.isEdited,
                                          baseSeed: seed,
                                          requestedVariations: variations)

        // The full-resolution float disparity is the truth on disk; the 512 × 512 conditioning
        // image is derived from it per request.
        let depthData = shot.hasDepth ? Self.encodeDepth(shot) : nil

        let project = try library.createProject(
            displayName: name,
            mode: mode,
            recipe: projectRecipe,
            depthProvenance: Self.provenance(shot.provenance),
            sourceData: shot.imageData,
            depthData: depthData,
            sourceSize: CGSize(width: shot.pixelSize.width, height: shot.pixelSize.height))

        folders[project.id] = project.folder

        let styleName = recipe.presetID.flatMap { PresetCatalog.preset(id: $0)?.name }
            ?? (recipe.isEdited ? "Your words" : "Redesign")

        var controls: [ControlSignal] = []
        if shot.hasDepth {
            controls.append(ControlSignal(
                kind: .depth,
                image: ImageHandle(url: project.depthURL, size: shot.depthSize),
                provenance: shot.provenance))
        }

        let requests = (1...variations).map { index in
            RedesignRequest(id: "\(project.id)-\(index)",
                            projectID: project.id,
                            variationIndex: index,
                            variationCount: variations,
                            source: ImageHandle(url: project.sourceURL, size: shot.pixelSize),
                            controls: controls,
                            mode: shot.mode == .interior ? .interior : .exterior,
                            prompt: recipe.prompt,
                            presetID: recipe.presetID,
                            seed: projectRecipe.seed(forVariation: index),
                            spaceName: name,
                            styleName: styleName)
        }

        for request in requests { startedAt[JobID(request.id)] = Date() }
        engine.enqueue(requests)
        router.started(projectID: project.id)
    }

    /// "Try again" — the same prompt, a new seed.
    func again(project: SpaceProject) throws {
        guard let sidecar = project.sidecar else { return }
        let nextIndex = (project.variations.map(\.index).max() ?? 0) + 1
        let seed = UInt32.random(in: 1...UInt32.max)
        let styleName = sidecar.recipe.presetID.flatMap { PresetCatalog.preset(id: $0)?.name }
            ?? "Redesign"

        var controls: [ControlSignal] = []
        if FileManager.default.fileExists(atPath: project.depthURL.path) {
            controls.append(ControlSignal(
                kind: .depth,
                image: ImageHandle(url: project.depthURL,
                                   size: PixelSize(width: 0, height: 0)),
                provenance: Self.provenance(sidecar.depthProvenance)))
        }

        let request = RedesignRequest(
            id: "\(project.id)-\(nextIndex)",
            projectID: project.id,
            variationIndex: nextIndex,
            variationCount: nextIndex,
            source: ImageHandle(url: project.sourceURL,
                                size: PixelSize(width: sidecar.sourcePixelWidth,
                                                height: sidecar.sourcePixelHeight)),
            controls: controls,
            mode: sidecar.mode == .interior ? .interior : .exterior,
            prompt: sidecar.recipe.prompt,
            presetID: sidecar.recipe.presetID,
            seed: seed,
            spaceName: sidecar.displayName,
            styleName: styleName)

        folders[project.id] = project.folder
        startedAt[JobID(request.id)] = Date()
        engine.enqueue([request])
        router.started(projectID: project.id)
    }

    // ── finishing ────────────────────────────────────────────────────────────────────────────

    private func absorb(_ job: Job, output: RedesignOutput) async {
        guard let folder = folders[job.request.projectID],
              let project = library.projects.first(where: { $0.folder == folder })
                ?? library.project(id: job.request.projectID) else { return }

        let elapsed = startedAt[job.id].map { Date().timeIntervalSince($0) } ?? 0
        startedAt[job.id] = nil

        let sidecar = VariationSidecar(index: job.request.variationIndex,
                                       seed: output.seed,
                                       createdAt: output.createdAt,
                                       elapsedSeconds: elapsed,
                                       stepsRun: output.stepsRun,
                                       resumedFromStep: output.resumedFromStep,
                                       prompt: job.request.prompt,
                                       presetID: job.request.presetID)

        try? library.appendVariation(to: project, sidecar: sidecar, image: output.image)
        router.finished(projectID: job.request.projectID, variation: job.request.variationIndex)
    }

    // ── bridging the two SpaceMode enums ─────────────────────────────────────────────────────

    /// `RedesignKit` and `ProjectKit` each declare their own `DepthProvenance`, on purpose: neither
    /// package depends on the other, which is what keeps both Foundation-only and independently
    /// testable. The cost is this function, and it is a cost worth paying once.
    static func provenance(_ value: RedesignKit.DepthProvenance) -> ProjectKit.DepthProvenance {
        switch value {
        case .lidar: return .lidar
        case .dualCamera: return .dualCamera
        case .embedded: return .embedded
        case .estimated: return .estimated
        case .synthetic: return .synthetic
        }
    }

    static func provenance(_ value: ProjectKit.DepthProvenance) -> RedesignKit.DepthProvenance {
        switch value {
        case .lidar: return .lidar
        case .dualCamera: return .dualCamera
        case .embedded: return .embedded
        case .estimated: return .estimated
        case .synthetic, .none: return .synthetic
        }
    }

    /// Depth is stored as raw little-endian `Float32` plus a small header, not as TIFF.
    ///
    /// A single-channel 32-bit float TIFF is what the plan called for and what ImageIO will not
    /// reliably round-trip; raw floats with the dimensions in front are unambiguous, exactly as
    /// precise, and readable by the Python side of `../aisixteen.models` in three lines.
    static func encodeDepth(_ shot: SourceShot) -> Data {
        var data = Data()
        var width = UInt32(shot.depthSize.width).littleEndian
        var height = UInt32(shot.depthSize.height).littleEndian
        withUnsafeBytes(of: &width) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &height) { data.append(contentsOf: $0) }
        shot.depthValues.withUnsafeBufferPointer { buffer in
            data.append(UnsafeBufferPointer(start: buffer.baseAddress, count: buffer.count))
        }
        return data
    }

    static func decodeDepth(_ data: Data) -> (values: [Float], size: PixelSize)? {
        guard data.count >= 8 else { return nil }
        let width = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian })
        let height = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian })
        let expected = width * height * MemoryLayout<Float>.size
        guard width > 0, height > 0, data.count >= 8 + expected else { return nil }

        var values = [Float](repeating: 0, count: width * height)
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination, from: 8..<(8 + expected))
        }
        return (values, PixelSize(width: width, height: height))
    }
}
