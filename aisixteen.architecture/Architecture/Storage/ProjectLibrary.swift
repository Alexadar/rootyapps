import Foundation
import FormatKit
import Observation
import ProjectKit
import RedesignKit
import SwiftUI

/// The library, as the app sees it.
///
/// Wraps `ProjectKit.ProjectStore` — which knows about folders and sidecars and nothing else —
/// and adds the parts that are specifically about being an app: where the root is, whether files
/// have arrived, and what the caption should say.
@MainActor
@Observable
final class ProjectLibrary {

    private(set) var location: StorageLocation?
    private(set) var projects: [SpaceProject] = []
    private(set) var isLoaded = false

    @ObservationIgnored private var store: ProjectStore?
    @ObservationIgnored private var watcher: ProjectWatcher?
    @ObservationIgnored private let appVersion: String

    init(appVersion: String = Bundle.main.marketingVersion) {
        self.appVersion = appVersion
    }

    // ── truthful copy ────────────────────────────────────────────────────────────────────────

    /// "In your iCloud folder — yours, in Files, on all your devices" or "On this device".
    ///
    /// Two locations, two truths. Never a word that implies an account: iCloud here is the user's
    /// own folder, there is nothing to sign in to, and nothing that can be taken away.
    var caption: String { StorageText.caption(isCloud: location?.isCloud ?? false) }
    var emptyState: String { StorageText.emptyState(isCloud: location?.isCloud ?? false) }

    // ── lifecycle ────────────────────────────────────────────────────────────────────────────

    func start() async {
        // Resolving the ubiquity container blocks on the sync daemon, so it happens off the main
        // actor and the first frame is not held for it.
        let location = await Task.detached(priority: .userInitiated) {
            ProjectLocator.resolveWithOverrides()
        }.value

        self.location = location
        let store = ProjectLocator.store(for: location, appVersion: appVersion)
        self.store = store

        let watcher = ProjectWatcher(location: location)
        watcher.onChange = { [weak self] in Task { @MainActor in self?.reload() } }
        watcher.start()
        self.watcher = watcher

        reload()
        isLoaded = true
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    func reload() {
        guard let store else { return }
        projects = (try? store.projects()) ?? []
    }

    // ── download state ───────────────────────────────────────────────────────────────────────

    /// A project whose sidecar has not arrived. Shown, not hidden — the folder is visible in Files
    /// and pretending it is not there would be the bigger lie.
    func downloadState(for project: SpaceProject) -> ItemState? {
        guard let watcher, let root = location?.root else { return nil }
        let relative = project.folder.lastPathComponent + "/" + ProjectFile.sidecar
        _ = root
        return watcher.state(forRelativePath: relative)
    }

    func downloadState(for variation: VariationRecord, in project: SpaceProject) -> ItemState? {
        guard let watcher else { return nil }
        let relative = [project.folder.lastPathComponent,
                        ProjectFile.variationsFolder,
                        variation.imageURL.lastPathComponent].joined(separator: "/")
        return watcher.state(forRelativePath: relative)
    }

    /// Fetch the cheap things first: the sidecar and the thumbnail are a few kilobytes and are
    /// what turn a ghost into a named tile. The full picture waits until the user opens it.
    func requestDownload(of project: SpaceProject) {
        watcher?.requestDownload(of: project.folder.appendingPathComponent(ProjectFile.sidecar))
        watcher?.requestDownload(of: project.thumbnailURL)
    }

    func requestDownload(of variation: VariationRecord) {
        watcher?.requestDownload(of: variation.imageURL)
    }

    // ── writing ──────────────────────────────────────────────────────────────────────────────

    func createProject(displayName: String,
                       mode: ProjectKit.SpaceMode,
                       recipe: ProjectRecipe,
                       depthProvenance: ProjectKit.DepthProvenance,
                       sourceData: Data,
                       depthData: Data?,
                       sourceSize: CGSize) throws -> SpaceProject {
        guard let store else { throw LibraryError.notReady }
        let project = try store.createProject(displayName: displayName,
                                              mode: mode,
                                              createdAt: Date(),
                                              recipe: recipe,
                                              depthProvenance: depthProvenance,
                                              sourceData: sourceData,
                                              depthData: depthData,
                                              sourcePixelWidth: Int(sourceSize.width),
                                              sourcePixelHeight: Int(sourceSize.height))
        reload()
        return project
    }

    func appendVariation(to project: SpaceProject,
                         sidecar: VariationSidecar,
                         image: PreviewImage) throws {
        guard let store else { throw LibraryError.notReady }
        guard let png = Bitmap.png(from: image) else { throw LibraryError.encodingFailed }
        let thumbnail = Bitmap.thumbnailData(from: image, maxPixel: 480)
        try store.appendVariation(to: project.folder,
                                  sidecar: sidecar,
                                  imageData: png,
                                  thumbnailData: thumbnail)
        reload()
    }

    func rename(_ project: SpaceProject, to name: String) throws {
        guard let store else { throw LibraryError.notReady }
        _ = try store.rename(project, to: name)
        reload()
    }

    func delete(_ project: SpaceProject) throws {
        guard let store else { throw LibraryError.notReady }
        try store.delete(project)
        reload()
    }

    func delete(_ variation: VariationRecord, in project: SpaceProject) throws {
        guard let store else { throw LibraryError.notReady }
        try store.deleteVariation(variation, in: project)
        reload()
    }

    func project(id: String) -> SpaceProject? {
        projects.first { $0.id == id }
    }

    enum LibraryError: Error {
        case notReady
        case encodingFailed
    }
}

extension Bundle {
    var marketingVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
