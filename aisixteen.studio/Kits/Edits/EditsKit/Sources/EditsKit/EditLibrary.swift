import Foundation
import CryptoKit
import RecipeKit

public enum EditLibraryError: Error, Equatable {
    /// The original's bytes no longer hash to what the recipe recorded. Nothing in this app can
    /// cause it; if it is ever thrown, something outside wrote to a file that must not change.
    case originalChanged(EditIdentifier)
    case originalMissing(EditIdentifier)
    case notReadable(String)
}

/// The folder of edits, and the rules about what may be written where.
///
/// ### The one rule
///
/// **The original is written exactly once, at import, and never again.** Everything else — the
/// enhanced copy, the masks, the recipe — is regenerable from it. That is what makes an edit
/// revertible forever, and it is why `write(enhanced:)` and `write(mask:)` exist as named methods
/// while there is deliberately no method that writes an original after `create`.
public final class EditLibrary {

    public let root: URL
    private let access: FileAccess
    private let appVersion: String

    public init(root: URL, access: FileAccess, appVersion: String) {
        self.root = root
        self.access = access
        self.appVersion = appVersion
    }

    public func prepare() throws {
        try access.createDirectory(root)
    }

    // MARK: Import — the only time an original is ever written

    /// Copies the imported bytes in, seals them, and writes the recipe that describes the untouched
    /// state of the photo.
    ///
    /// The digest is taken from the bytes **as handed in**, before anything touches the disk, so it
    /// describes what the user chose rather than what the file system happened to store.
    public func create(originalData: Data,
                       fileExtension: String,
                       displayName: String,
                       seed: UInt32,
                       createdAt: Date) throws -> EditRecord {
        let id = EditIdentifier.make(createdAt: createdAt, seed: seed)
        let folder = root.appendingPathComponent(id.rawValue, isDirectory: true)
        try access.createDirectory(folder)
        try access.createDirectory(folder.appendingPathComponent(EditLayout.masksFolder,
                                                                 isDirectory: true))

        let filename = EditLayout.originalFilename(extension: fileExtension)
        let originalURL = folder.appendingPathComponent(filename)
        try access.write(originalData, to: originalURL)
        // Sealed immediately, not at the end: a failure between the write and the chmod would
        // otherwise leave a writable original behind.
        try access.setPermissions(EditLayout.originalPermissions, on: originalURL)

        let recipe = EditRecipe(sourceFilename: filename,
                                sourceDigest: Self.digest(of: originalData),
                                seed: seed,
                                createdAt: createdAt,
                                appVersion: appVersion)

        let record = EditRecord(id: id, folder: folder, recipe: recipe, displayName: displayName)
        try access.write(Data(displayName.utf8),
                         to: folder.appendingPathComponent(EditLayout.nameFilename))
        try save(recipe: recipe, for: record)
        return record
    }

    // MARK: Writes that are allowed

    @discardableResult
    public func save(recipe: EditRecipe, for record: EditRecord) throws -> EditRecord {
        let encoder = JSONEncoder()
        // Readable in Files by a user who wants to know what the app did to their photo. That is
        // half the point of storing a recipe rather than only a rendered file.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try access.write(try encoder.encode(recipe), to: record.recipeURL)

        var updated = record
        updated.recipe = recipe
        return updated
    }

    public func write(enhanced data: Data, for record: EditRecord) throws {
        try access.write(data, to: record.enhancedURL)
    }

    public func write(mask data: Data, source: MaskSource, for record: EditRecord) throws {
        try access.createDirectory(record.folder.appendingPathComponent(EditLayout.masksFolder,
                                                                        isDirectory: true))
        try access.write(data, to: record.maskURL(source))
    }

    // MARK: Reads

    public func readOriginal(_ record: EditRecord) throws -> Data {
        guard access.exists(record.originalURL) else {
            throw EditLibraryError.originalMissing(record.id)
        }
        return try access.read(record.originalURL)
    }

    public func readEnhanced(_ record: EditRecord) throws -> Data? {
        guard access.exists(record.enhancedURL) else { return nil }
        return try access.read(record.enhancedURL)
    }

    public func readMask(_ source: MaskSource, for record: EditRecord) throws -> Data? {
        let url = record.maskURL(source)
        guard access.exists(url) else { return nil }
        return try access.read(url)
    }

    /// Newest first, which is what both the phone's library grid and the Mac's sidebar want.
    ///
    /// A folder that fails to load is **skipped, not thrown**: one corrupt recipe must not take the
    /// whole library down, because the library is the only way back to the other edits.
    public func load() throws -> [EditRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try access.contentsOfDirectory(root)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .compactMap { folder -> EditRecord? in
                let id = EditIdentifier(rawValue: folder.lastPathComponent)
                let recipeURL = folder.appendingPathComponent(EditLayout.recipeFilename)
                guard access.exists(recipeURL),
                      let data = try? access.read(recipeURL),
                      let recipe = try? decoder.decode(EditRecipe.self, from: data)
                else { return nil }

                return EditRecord(id: id,
                                  folder: folder,
                                  recipe: recipe,
                                  availability: availability(of: folder),
                                  displayName: Self.displayName(for: folder, recipe: recipe))
            }
            .sorted { $0.recipe.createdAt > $1.recipe.createdAt }
    }

    public func delete(_ record: EditRecord) throws {
        // The original is 0444, but unlinking is governed by the *folder's* permissions, so the
        // seal does not stand between the user and deleting their own edit.
        try access.remove(record.folder)
    }

    // MARK: The invariant

    /// Re-hashes the original and compares it with what the recipe recorded at import.
    ///
    /// Called on every exit path the tests exercise — cancel, failure, export, revert, delete. It is
    /// cheap next to a pass and it is the only thing that would notice the promise being broken.
    public func verifyOriginal(_ record: EditRecord) throws {
        guard access.exists(record.originalURL) else {
            throw EditLibraryError.originalMissing(record.id)
        }
        let data = try access.read(record.originalURL)
        guard Self.digest(of: data) == record.recipe.sourceDigest else {
            throw EditLibraryError.originalChanged(record.id)
        }
    }

    /// True when the file is still sealed read-only.
    public func originalIsSealed(_ record: EditRecord) -> Bool {
        guard let permissions = try? access.permissions(of: record.originalURL) else { return false }
        return permissions & 0o222 == 0
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Availability

    /// Whether the edit's bytes are on this device.
    ///
    /// Reads the ubiquity resource values; on the local fallback root those keys are absent, and
    /// absent correctly means `.local` — the file is right there.
    private func availability(of folder: URL) -> EditAvailability {
        let enhanced = folder.appendingPathComponent(EditLayout.enhancedFilename)
        let target = access.exists(enhanced) ? enhanced
                                             : folder.appendingPathComponent(EditLayout.recipeFilename)
        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey,
                                         .ubiquitousItemIsDownloadingKey]
        guard let values = try? target.resourceValues(forKeys: keys) else { return .local }

        if values.ubiquitousItemIsDownloading == true { return .downloading(fraction: nil) }
        switch values.ubiquitousItemDownloadingStatus {
        case .some(.current), .some(.downloaded), .none:
            return .local
        case .some(.notDownloaded):
            return .notDownloaded
        default:
            return .local
        }
    }

    private static func displayName(for folder: URL, recipe: EditRecipe) -> String {
        let sidecar = folder.appendingPathComponent(EditLayout.nameFilename)
        if let data = try? Data(contentsOf: sidecar),
           let name = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return folder.lastPathComponent
    }
}
