import Foundation

/// How the library touches the disk.
///
/// A seam, because writing into an iCloud container and writing into a plain folder are not the
/// same operation: the first must go through `NSFileCoordinator` or another device's sync daemon
/// can read a half-written file, and a delete that is not coordinated gets undone by the next sync.
/// The library itself does not care — it asks for bytes to be written, and this decides how.
///
/// Tests use `DirectFileAccess`, which is also the correct implementation for the local fallback
/// folder: nothing else is looking at it, so coordinating would only add latency.
public protocol FileAccess: Sendable {
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func remove(_ urls: [URL]) throws
    func contentsOfDirectory(_ url: URL) throws -> [URL]
    func createDirectoryIfNeeded(_ url: URL) throws
    func exists(_ url: URL) -> Bool
}

/// Plain `FileManager`. Correct for the local fallback folder and for tests.
public struct DirectFileAccess: FileAccess {
    public init() {}

    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    public func write(_ data: Data, to url: URL) throws {
        // Atomic: a wallpaper is watched by a metadata query, and a partially written PNG that
        // becomes visible for a moment shows up as a corrupt tile.
        try data.write(to: url, options: .atomic)
    }

    public func remove(_ urls: [URL]) throws {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])
    }

    public func createDirectoryIfNeeded(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// `NSFileCoordinator`-wrapped access, for the iCloud ubiquity container.
///
/// Without this, two failures are routine rather than rare: another device's sync reads a PNG
/// mid-write and stores a truncated file, and a delete races the daemon which then restores the
/// item it still believes exists. Both look like bugs in the app.
public struct CoordinatedFileAccess: FileAccess {
    private let direct = DirectFileAccess()
    private let purposeIdentifier: String

    public init(purposeIdentifier: String = "AISixteen Wallpapers") {
        self.purposeIdentifier = purposeIdentifier
    }

    public func read(_ url: URL) throws -> Data {
        try coordinate(reading: url) { try direct.read($0) }
    }

    public func write(_ data: Data, to url: URL) throws {
        try coordinate(writing: url, options: .forReplacing) { try direct.write(data, to: $0) }
    }

    public func remove(_ urls: [URL]) throws {
        for url in urls where direct.exists(url) {
            try coordinate(writing: url, options: .forDeleting) { try direct.remove([$0]) }
        }
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        try coordinate(reading: url) { try direct.contentsOfDirectory($0) }
    }

    public func createDirectoryIfNeeded(_ url: URL) throws {
        guard !direct.exists(url) else { return }
        try coordinate(writing: url, options: .forReplacing) { try direct.createDirectoryIfNeeded($0) }
    }

    public func exists(_ url: URL) -> Bool { direct.exists(url) }

    // MARK: -

    private func coordinate<T>(reading url: URL, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.purposeIdentifier = purposeIdentifier
        var result: Result<T, Error>?
        var coordinationError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { actual in
            result = Result { try body(actual) }
        }
        if let coordinationError { throw coordinationError }
        return try result!.get()
    }

    private func coordinate(writing url: URL,
                            options: NSFileCoordinator.WritingOptions,
                            _ body: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.purposeIdentifier = purposeIdentifier
        var result: Result<Void, Error>?
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { actual in
            result = Result { try body(actual) }
        }
        if let coordinationError { throw coordinationError }
        try result!.get()
    }
}
