import Foundation
import Observation
import ProjectKit
import RedesignKit

/// Where the user is.
///
/// ⚠️ THE HANDOFF HAS NO ROUTER AT ALL. `RootView` switches between `CaptureView()` and
/// `LibraryView()` and there is no path from Capture to Direction to Generating to Result
/// anywhere in the bundle — the flow existed only as a sequence of static mockups.
///
/// `section` and `stage` are INDEPENDENT, and that is the important part. The queue keeps running
/// while the user browses the Library, so "which screen of the redesign flow" and "which half of
/// the app" are not the same question. Modelling them as one enum would mean opening the Library
/// cancelled your place in the flow.
@MainActor
@Observable
final class Router {

    enum Section: String, CaseIterable, Hashable {
        case redesign = "Redesign"
        case library = "Library"
    }

    enum Stage: Equatable {
        case capture
        case direction(SourceShot)
        case generating(projectID: String)
        case result(projectID: String, variation: Int)

        var isGenerating: Bool {
            if case .generating = self { return true }
            return false
        }
    }

    var section: Section = .redesign
    var stage: Stage = .capture
    /// The Mac sidebar's and the iPad rail's selection. Separate from `stage` because selecting a
    /// space in the sidebar is browsing, not navigating a flow.
    var selectedProjectID: String?
    /// Set when a rename sheet is open.
    var renamingProjectID: String?

    // ── the flow ─────────────────────────────────────────────────────────────────────────────

    func begin(_ shot: SourceShot) {
        section = .redesign
        stage = .direction(shot)
    }

    func started(projectID: String) {
        section = .redesign
        selectedProjectID = projectID
        stage = .generating(projectID: projectID)
    }

    /// Route to a finished variation — but only if the user is still watching this project.
    ///
    /// Somebody who wandered off to the Library while a three-minute render finished did not ask
    /// to be yanked back. The notification and the Live Activity are how they get told; the app
    /// jumping under their thumb is not.
    func finished(projectID: String, variation: Int) {
        guard section == .redesign,
              case .generating(let current) = stage,
              current == projectID else { return }
        stage = .result(projectID: projectID, variation: variation)
    }

    /// From a notification tap or a library tile: go there regardless of where the user was,
    /// because this time they asked.
    func openResult(projectID: String, variation: Int) {
        section = .redesign
        selectedProjectID = projectID
        stage = .result(projectID: projectID, variation: variation)
    }

    func openLibrary() {
        section = .library
    }

    func back() {
        switch stage {
        case .capture:
            section = .library
        case .direction:
            stage = .capture
        case .generating:
            section = .library
        case .result(let projectID, _):
            selectedProjectID = projectID
            section = .library
        }
    }

    /// "Regenerate with edits" — back to Direction with the recipe loaded.
    func editAgain(_ shot: SourceShot) {
        stage = .direction(shot)
    }

    func startOver() {
        stage = .capture
        section = .redesign
    }

    // ── deep links, for the UI suite ─────────────────────────────────────────────────────────

    /// `uitests.md` §11a: any interaction costs about 1.1 s because the accessibility tree is
    /// re-snapshotted, so a suite that navigates four screens to assert one label spends most of
    /// its time navigating. A deep link is the only order-of-magnitude lever there is.
    static func seeded() -> Router {
        let router = Router()
        switch LaunchOverride.value(LaunchOverride.screen) {
        case "library":
            router.section = .library
        case "capture":
            router.section = .redesign
            router.stage = .capture
        case "direction":
            // The screens past Capture need a shot to exist. The bundled sample supplies one, so
            // a deep link reaches them with zero taps — which is also how the frames get looked at
            // without driving the whole flow by hand.
            router.section = .redesign
            if let shot = Self.sampleShot() { router.stage = .direction(shot) }
        default:
            break
        }
        return router
    }

    static func sampleShot(mode: DirectionMode = .interior) -> SourceShot? {
        guard let data = SampleAssets.photoData(for: mode),
              let size = SampleAssets.pixelSize(of: data) else { return nil }
        let depthSize = PixelSize(width: 256, height: 256)
        return SourceShot(mode: mode,
                          imageData: data,
                          pixelSize: size,
                          depthValues: DepthSource.synthetic(size: depthSize),
                          depthSize: depthSize,
                          provenance: .synthetic)
    }
}
