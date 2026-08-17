import Foundation

/// Charts in the app's iCloud folder — one file each, visible to the user, synced by the system.
///
/// ## Why iCloud Documents and not CloudKit
///
/// The requirement is a folder the user can *see* in Files. A private CloudKit database syncs
/// perfectly well and is invisible, so it cannot satisfy that on its own. A ubiquity container gives
/// both, and it makes export nearly free: the files already are the export.
///
/// It also answers the loudest complaint about the competing apps — charts vanishing — because the
/// user's data is not trapped in an opaque store they cannot inspect or back up.
///
/// ## Why one file per chart
///
/// Two devices editing *different* charts write different files and can never conflict, which is
/// almost all real usage. A single library document would raise a whole-file conflict for any
/// concurrent edit and hand back two entire libraries to reconcile. Per-file also means a corrupted
/// record costs one chart rather than the library.
///
/// ## Subfolders
///
/// Enumeration is recursive from day one even though everything is written flat today. The folder
/// *is* the grouping, so when subfolders arrive they need no schema field and no migration — only a
/// UI to create and move. Identity lives in the UUID filename, so a chart moved on one device is
/// still the same chart on another.
public final class ICloudChartStore: ChartStore, @unchecked Sendable {

    public enum StoreError: Error {
        /// iCloud Drive is off, or the container is not provisioned. Callers should fall back to a
        /// local store rather than presenting an empty library as if the user had no charts.
        case containerUnavailable
    }

    private let root: URL
    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "ephemeris.chartstore", qos: .userInitiated)

    /// - Parameter containerID: nil uses the app's default ubiquity container.
    public init(containerID: String? = nil) throws {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            throw StoreError.containerUnavailable
        }
        // `Documents` specifically: only this subdirectory is exposed to the user in Files, and the
        // whole point of the container is that the folder is visible.
        root = base.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Test seam — point at a plain directory and every behaviour except sync is exercisable.
    public init(localRoot: URL) throws {
        root = localRoot
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Reading

    public func all() throws -> [SavedChart] {
        try allIncludingDeleted().filter { $0.deletedAt == nil }
    }

    public func allIncludingDeleted() throws -> [SavedChart] {
        try urls().compactMap { url in
            // A single unreadable record must not take the library down with it. Losing sight of one
            // chart is recoverable; refusing to open the library is what makes people leave a review
            // saying everything disappeared.
            try? read(at: url)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func chart(id: UUID) throws -> SavedChart? {
        try urls().first { $0.deletingPathExtension().lastPathComponent == id.uuidString }
            .flatMap { try? read(at: $0) }
    }

    /// Recursive on purpose — see the note about subfolders above.
    private func urls() throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
    }

    private func read(at url: URL) throws -> SavedChart {
        // A file can exist in the container without its contents having arrived yet. Asking for the
        // download and reading through a coordinator is what turns a placeholder into real bytes;
        // reading directly returns nothing useful and looks like corruption.
        if (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus == .notDownloaded {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }

        var result: Result<SavedChart, Error> = .failure(StoreError.containerUnavailable)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { u in
            result = Result { try Self.decoder.decode(SavedChart.self, from: Data(contentsOf: u)) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    // MARK: - Writing

    public func save(_ chart: SavedChart) throws {
        var c = chart
        c.modifiedAt = Date()
        let data = try Self.encoder.encode(c)
        let target = url(for: c.id)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing,
                                       error: &coordinationError) { u in
            do {
                // Atomic: write beside the target, then swap. Writing in place means a crash or a
                // full disk mid-write leaves truncated JSON that fails to decode — which is exactly
                // how a chart "disappears".
                let temp = u.deletingLastPathComponent()
                    .appendingPathComponent(".\(c.id.uuidString).tmp")
                try data.write(to: temp)
                if fm.fileExists(atPath: u.path) {
                    _ = try fm.replaceItemAt(u, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: u)
                }
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// Tombstones rather than erases. A device that was offline when the delete happened would
    /// otherwise still hold the record and resurrect it on its next sync.
    public func delete(id: UUID) throws {
        guard var c = try chart(id: id) else { return }
        c.deletedAt = Date()
        try save(c)
    }

    private func url(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Conflicts

    /// Competing versions of one chart, if any.
    ///
    /// Per-file records keep this comprehensible: a conflict is always about a single named chart,
    /// never about the library. Resolution belongs to the UI — silently picking a winner is how a
    /// user loses an edit without ever being told.
    public func conflicts(for id: UUID) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url(for: id)) ?? []
    }

    public func resolve(id: UUID, keeping version: NSFileVersion) throws {
        try version.replaceItem(at: url(for: id))
        for other in conflicts(for: id) { other.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: url(for: id))
    }

    // MARK: - Coders

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // Readable and stably ordered: the file is the export, and a user may well open it.
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}
