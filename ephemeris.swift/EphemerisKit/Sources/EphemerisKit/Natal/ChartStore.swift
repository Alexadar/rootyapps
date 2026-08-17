import Foundation



/// Where saved charts live.
///
/// A protocol so the UI can be built and tested against `InMemoryChartStore` before the on-disk
/// implementation exists — and so the eventual sync work swaps the backing without touching a view.
public protocol ChartStore: Sendable {
    /// Live charts, newest first. Tombstoned records are excluded.
    func all() throws -> [SavedChart]
    func chart(id: UUID) throws -> SavedChart?
    /// Insert or update. Stamps `modifiedAt` — callers must not set it themselves.
    func save(_ chart: SavedChart) throws
    /// Tombstones rather than erases, so the delete can propagate to other devices later.
    func delete(id: UUID) throws
    /// Everything including tombstones — for sync and for export.
    func allIncludingDeleted() throws -> [SavedChart]
}

/// The mock the UI is developed against.
public final class InMemoryChartStore: ChartStore, @unchecked Sendable {
    private var records: [UUID: SavedChart] = [:]
    private let lock = NSLock()

    public init(seed: [SavedChart] = []) {
        for c in seed { records[c.id] = c }
    }

    public func all() throws -> [SavedChart] {
        try allIncludingDeleted().filter { $0.deletedAt == nil }
    }

    public func allIncludingDeleted() throws -> [SavedChart] {
        lock.lock(); defer { lock.unlock() }
        return records.values.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func chart(id: UUID) throws -> SavedChart? {
        lock.lock(); defer { lock.unlock() }
        return records[id]
    }

    public func save(_ chart: SavedChart) throws {
        lock.lock(); defer { lock.unlock() }
        var c = chart
        c.modifiedAt = Date()
        records[c.id] = c
    }

    public func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard var c = records[id] else { return }
        c.deletedAt = Date()
        c.modifiedAt = Date()
        records[id] = c
    }
}

/// One file per chart, in Application Support.
///
/// ## Why one file per chart rather than one library file
///
/// It is the decision that removes most of the difficulty from syncing later. Two devices editing
/// *different* charts — which is nearly all real usage — can never conflict, because they are
/// writing different files. A single library document would produce a whole-file conflict for any
/// concurrent edit and hand you two entire libraries to reconcile. It also means a corrupt record
/// costs one chart instead of the library, and export is just a folder.
///
/// ## Why Application Support and not Caches
///
/// Application Support is included in device backup; Caches is not, and is evictable under storage
/// pressure. "My charts disappeared" is the single loudest complaint about the competing apps, so
/// this choice is the feature.
///
/// ## Atomic writes are not optional
///
/// Serialise to a temporary file, then rename. A rename is atomic; writing in place is not, and a
/// crash or a full disk midway through leaves a truncated JSON file that fails to decode — which is
/// how a library silently loses a record.
public final class FileChartStore: ChartStore, @unchecked Sendable {

    private let directory: URL
    private let fm = FileManager.default

    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true)
            self.directory = base.appendingPathComponent("Charts", isDirectory: true)
        }
        try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func all() throws -> [SavedChart] {
        try allIncludingDeleted().filter { $0.deletedAt == nil }
    }

    public func allIncludingDeleted() throws -> [SavedChart] {
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A single unreadable file must not take the whole library down with it — skip it and keep
        // going. Losing one chart is recoverable; refusing to open the library is not.
        return files.compactMap { try? decoder.decode(SavedChart.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func chart(id: UUID) throws -> SavedChart? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try decoder.decode(SavedChart.self, from: data)
    }

    public func save(_ chart: SavedChart) throws {
        var c = chart
        c.modifiedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // readable = exportable = auditable
        let data = try encoder.encode(c)

        let target = url(for: c.id)
        let temp = directory.appendingPathComponent(".\(c.id.uuidString).tmp")
        try data.write(to: temp)
        // Atomic: the record is either the old one or the new one, never a half-written file.
        _ = try fm.replaceItemAt(target, withItemAt: temp)
    }

    public func delete(id: UUID) throws {
        guard var c = try chart(id: id) else { return }
        c.deletedAt = Date()
        try save(c)
    }
}
