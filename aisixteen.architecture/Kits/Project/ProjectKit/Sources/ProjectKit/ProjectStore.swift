import Foundation

/// Reads and writes projects under one root.
///
/// The root is injected, and that is the entire iCloud story: the container and the local fallback
/// are the same code over two different URLs. It is the only reason a user with iCloud switched
/// off exercises paths that were actually tested.
public struct ProjectStore: Sendable {

    public let root: URL
    public let access: any FileAccess
    public let appVersion: String

    public init(root: URL, access: any FileAccess, appVersion: String) {
        self.root = root
        self.access = access
        self.appVersion = appVersion
    }

    public enum StoreError: Error, Equatable {
        case notAProject(URL)
        case variationAlreadyExists(Int)
    }

    // ── reading ──────────────────────────────────────────────────────────────────────────────

    /// Every project folder under the root, newest first.
    ///
    /// A folder with no readable sidecar is still returned, as a ghost — it exists, the user can
    /// see it in Files, and hiding it would be a worse lie than showing it as "still arriving".
    public func projects() throws -> [SpaceProject] {
        try access.createDirectoryIfNeeded(root)
        let entries = try access.contentsOfDirectory(root)
        return entries
            .filter { access.isDirectory($0) }
            .compactMap { try? project(at: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func project(at folder: URL) throws -> SpaceProject {
        let sidecarURL = folder.appendingPathComponent(ProjectFile.sidecar)
        var sidecar: ProjectSidecar?
        if access.exists(sidecarURL), let data = try? access.read(sidecarURL) {
            sidecar = try? Self.decoder.decode(ProjectSidecar.self, from: data)
        }
        return SpaceProject(folder: folder,
                            sidecar: sidecar,
                            variations: try variations(in: folder),
                            sourceURL: folder.appendingPathComponent(ProjectFile.source),
                            depthURL: folder.appendingPathComponent(ProjectFile.depth),
                            thumbnailURL: folder.appendingPathComponent(ProjectFile.thumbnail))
    }

    /// The variations in a project, discovered from the folder rather than from an index.
    ///
    /// Three cases, and only one of them is a finished variation:
    ///   • sidecar + picture → a variation.
    ///   • sidecar, no picture → the record synced ahead of the image. Shown as pending, with a
    ///     real download percentage, never as a broken tile.
    ///   • picture, no sidecar → a half-finished sync in the other direction. SKIPPED, because
    ///     there is nothing truthful to say about it: no seed, no prompt, no date.
    public func variations(in folder: URL) throws -> [VariationRecord] {
        let directory = folder.appendingPathComponent(ProjectFile.variationsFolder, isDirectory: true)
        guard access.exists(directory) else { return [] }

        return try access.contentsOfDirectory(directory)
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { sidecarURL -> VariationRecord? in
                guard let data = try? access.read(sidecarURL),
                      let sidecar = try? Self.decoder.decode(VariationSidecar.self, from: data) else {
                    return nil
                }
                let imageURL = sidecarURL.deletingPathExtension().appendingPathExtension("png")
                return VariationRecord(index: sidecar.index,
                                       sidecar: sidecar,
                                       imageURL: imageURL,
                                       imageIsPresent: access.exists(imageURL))
            }
            .sorted { $0.index < $1.index }
    }

    // ── writing ──────────────────────────────────────────────────────────────────────────────

    /// Create a project folder and everything that identifies it.
    ///
    /// The write order matters and is not an implementation detail. A metadata query on another
    /// device fires on the FIRST file to arrive, so the pictures must exist before the record that
    /// describes them — otherwise the other device briefly shows a project whose source photo it
    /// cannot open.
    @discardableResult
    public func createProject(displayName: String,
                              mode: SpaceMode,
                              createdAt: Date,
                              recipe: ProjectRecipe,
                              depthProvenance: DepthProvenance,
                              sourceData: Data,
                              depthData: Data?,
                              sourcePixelWidth: Int,
                              sourcePixelHeight: Int) throws -> SpaceProject {
        let folderName = ProjectFolderName.make(displayName: displayName,
                                                createdAt: createdAt,
                                                seed: recipe.baseSeed)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)

        try access.createDirectoryIfNeeded(root)
        try access.createDirectoryIfNeeded(folder)
        try access.createDirectoryIfNeeded(folder.appendingPathComponent(ProjectFile.variationsFolder,
                                                                        isDirectory: true))

        try access.write(sourceData, to: folder.appendingPathComponent(ProjectFile.source))
        if let depthData {
            try access.write(depthData, to: folder.appendingPathComponent(ProjectFile.depth))
        }

        // Last: the sidecar is the commit record. A folder without it is a ghost, which the
        // library already knows how to render.
        let sidecar = ProjectSidecar(id: UUID().uuidString,
                                     displayName: displayName,
                                     mode: mode,
                                     createdAt: createdAt,
                                     appVersion: appVersion,
                                     recipe: recipe,
                                     depthProvenance: depthProvenance,
                                     sourcePixelWidth: sourcePixelWidth,
                                     sourcePixelHeight: sourcePixelHeight)
        try access.write(try Self.encoder.encode(sidecar),
                         to: folder.appendingPathComponent(ProjectFile.sidecar))

        return try project(at: folder)
    }

    /// Add a finished variation. Picture first, record second, for the reason above.
    public func appendVariation(to folder: URL,
                                sidecar: VariationSidecar,
                                imageData: Data,
                                thumbnailData: Data?) throws {
        let directory = folder.appendingPathComponent(ProjectFile.variationsFolder, isDirectory: true)
        try access.createDirectoryIfNeeded(directory)

        let imageName = ProjectFile.variationImage(index: sidecar.index, seed: sidecar.seed)
        let sidecarName = ProjectFile.variationSidecar(index: sidecar.index, seed: sidecar.seed)

        try access.write(imageData, to: directory.appendingPathComponent(imageName))
        try access.write(try Self.encoder.encode(sidecar),
                         to: directory.appendingPathComponent(sidecarName))

        // The project thumbnail follows the newest finished variation.
        if let thumbnailData {
            try access.write(thumbnailData, to: folder.appendingPathComponent(ProjectFile.thumbnail))
        }
    }

    /// Rename a project.
    ///
    /// The folder move is cosmetic and the sidecar is the truth, so the sidecar is written FIRST.
    /// If the move then fails — a file open in another app, a sync in progress — the user still
    /// sees the new name everywhere in the app, and only the folder in Files lags.
    public func rename(_ project: SpaceProject, to displayName: String) throws -> SpaceProject {
        guard var sidecar = project.sidecar else { throw StoreError.notAProject(project.folder) }
        sidecar.displayName = displayName
        try access.write(try Self.encoder.encode(sidecar),
                         to: project.folder.appendingPathComponent(ProjectFile.sidecar))

        let newName = ProjectFolderName.make(displayName: displayName,
                                             createdAt: sidecar.createdAt,
                                             seed: sidecar.recipe.baseSeed)
        let destination = root.appendingPathComponent(newName, isDirectory: true)
        if destination != project.folder && !access.exists(destination) {
            try? access.move(project.folder, to: destination)
        }
        let folder = access.exists(destination) ? destination : project.folder
        return try self.project(at: folder)
    }

    public func delete(_ project: SpaceProject) throws {
        try access.removeDirectory(project.folder)
    }

    public func deleteVariation(_ variation: VariationRecord, in project: SpaceProject) throws {
        let directory = project.folder.appendingPathComponent(ProjectFile.variationsFolder,
                                                              isDirectory: true)
        let sidecarName = ProjectFile.variationSidecar(index: variation.index,
                                                       seed: variation.sidecar.seed)
        try access.remove(variation.imageURL)
        try access.remove(directory.appendingPathComponent(sidecarName))
    }

    // ── coding ───────────────────────────────────────────────────────────────────────────────

    /// Pretty-printed with sorted keys, because the user can open these files. A sidecar that is
    /// one long line is a sidecar that says "not for you" to somebody who was promised the
    /// opposite.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
