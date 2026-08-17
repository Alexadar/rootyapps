import Foundation
import GenerationKit

public enum LibraryError: Error, Equatable {
    case rootUnavailable
    case notFound(id: String)
    case unreadableSidecar(id: String)
}

/// The library, over whatever folder it is handed.
///
/// **The root is injected.** That single decision is what makes "iCloud is switched off" a tested
/// path rather than an emergency branch: the iCloud container and the local fallback folder are the
/// same code with a different URL, and the suite runs both.
///
/// No database. Files plus sidecars, listed on demand. A gallery of a few hundred wallpapers is a
/// few hundred 200-byte reads — cheaper than keeping an index in sync across devices, and it cannot
/// disagree with what is actually on disk, which an index eventually does.
public struct WallpaperLibrary: Sendable {
    public let root: URL
    private let access: any FileAccess
    private let appVersion: String

    public init(root: URL, access: any FileAccess = DirectFileAccess(), appVersion: String = "1.0.0") {
        self.root = root
        self.access = access
        self.appVersion = appVersion
    }

    public func prepare() throws {
        try access.createDirectoryIfNeeded(root)
    }

    public func imageURL(for id: String) -> URL {
        root.appendingPathComponent(WallpaperFilename.imageName(id))
    }

    public func sidecarURL(for id: String) -> URL {
        root.appendingPathComponent(WallpaperFilename.sidecarName(id))
    }

    // MARK: Reading

    /// Everything in the folder, newest first — the order the gallery grid shows.
    ///
    /// A stem with a sidecar but no image is skipped: that is what a half-finished sync looks like,
    /// and the caller wants a tile with a picture. A stem with an image but no sidecar is also
    /// skipped rather than shown promptless, because "regenerate from this prompt" is the whole
    /// reason the prompt is stored and a tile that cannot do it is a broken tile.
    public func records() throws -> [WallpaperRecord] {
        guard access.exists(root) else { return [] }
        let stems = Set(try access.contentsOfDirectory(root)
            .compactMap { WallpaperFilename.stem(forFileNamed: $0.lastPathComponent) })

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return stems.compactMap { stem -> WallpaperRecord? in
            let image = imageURL(for: stem)
            let sidecar = sidecarURL(for: stem)
            guard access.exists(image), access.exists(sidecar) else { return nil }
            guard let data = try? access.read(sidecar),
                  let metadata = try? decoder.decode(WallpaperMetadata.self, from: data)
            else { return nil }
            return WallpaperRecord(id: stem, metadata: metadata, imageURL: image, sidecarURL: sidecar)
        }
        // Newest first. The tie-break on id keeps the order stable for two wallpapers finished in
        // the same second — without it the grid reshuffles on every refresh.
        .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func record(id: String) throws -> WallpaperRecord {
        guard let found = try records().first(where: { $0.id == id }) else {
            throw LibraryError.notFound(id: id)
        }
        return found
    }

    // MARK: Writing

    /// Saves an encoded image and its sidecar, returning the record.
    ///
    /// The sidecar is written **after** the image on purpose. A metadata query on another device
    /// fires as soon as the first file appears; if the sidecar landed first, that device would see
    /// a record whose picture does not exist yet and would have to handle a state that this
    /// ordering simply prevents.
    @discardableResult
    public func save(imageData: Data,
                     prompt: String,
                     seed: UInt32,
                     aspect: AspectRatio,
                     createdAt: Date) throws -> WallpaperRecord {
        try prepare()
        let stem = WallpaperFilename.stem(createdAt: createdAt, seed: seed)
        let metadata = WallpaperMetadata(prompt: prompt, seed: seed, aspect: aspect,
                                         createdAt: createdAt, appVersion: appVersion)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // the user can open this file

        try access.write(imageData, to: imageURL(for: stem))
        try access.write(try encoder.encode(metadata), to: sidecarURL(for: stem))

        return WallpaperRecord(id: stem, metadata: metadata,
                               imageURL: imageURL(for: stem), sidecarURL: sidecarURL(for: stem))
    }

    /// Removes both files. Missing ones are not an error — a delete that half-succeeded earlier
    /// must be completable, not stuck.
    public func delete(id: String) throws {
        try access.remove([imageURL(for: id), sidecarURL(for: id)])
    }

    public func imageData(for record: WallpaperRecord) throws -> Data {
        try access.read(record.imageURL)
    }
}
