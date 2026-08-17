import Foundation

/// Every file operation the store performs, behind a protocol.
///
/// Two implementations, chosen by where the library actually lives: coordinated access inside the
/// iCloud container, direct access on a local fallback. Coordination is not free — it takes a lock
/// and can block — so it is applied where another device might genuinely be writing, and nowhere
/// else.
public protocol FileAccess: Sendable {
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    /// Deleting a project deletes a tree, not a file.
    func removeDirectory(_ url: URL) throws
    func move(_ url: URL, to destination: URL) throws
    func contentsOfDirectory(_ url: URL) throws -> [URL]
    func createDirectoryIfNeeded(_ url: URL) throws
    func exists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    func modificationDate(_ url: URL) -> Date?
}

public struct DirectFileAccess: FileAccess {
    /// `FileManager.default` rather than an injected instance: `FileManager` is not `Sendable`,
    /// and the shared instance is documented as thread-safe for exactly these operations. The
    /// seam that matters for testing is the ROOT URL, not the file manager — every test points the
    /// store at its own temporary directory.
    private var fileManager: FileManager { .default }

    public init() {}

    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func remove(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func removeDirectory(_ url: URL) throws { try remove(url) }

    public func move(_ url: URL, to destination: URL) throws {
        try fileManager.moveItem(at: url, to: destination)
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: url,
                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])
    }

    public func createDirectoryIfNeeded(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }

    public func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        let found = fileManager.fileExists(atPath: url.path, isDirectory: &directory)
        return found && directory.boolValue
    }

    public func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

/// `NSFileCoordinator` around every operation, for the iCloud container.
///
/// The same folder can be written by this app on another device at the same moment. Without
/// coordination a read can catch a file mid-replace, and the symptom is a truncated JSON sidecar
/// that looks like data corruption rather than a race.
public struct CoordinatedFileAccess: FileAccess {
    private let direct: DirectFileAccess
    private let purposeIdentifier: String

    public init(purposeIdentifier: String = "oleksandr.aisixteen.architecture") {
        self.direct = DirectFileAccess()
        self.purposeIdentifier = purposeIdentifier
    }

    private func coordinator() -> NSFileCoordinator {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.purposeIdentifier = purposeIdentifier
        return coordinator
    }

    private func coordinate<T>(_ url: URL,
                               options: NSFileCoordinator.ReadingOptions,
                               _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator().coordinate(readingItemAt: url, options: options, error: &coordinationError) { actual in
            result = Result { try body(actual) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private func coordinateWrite<T>(_ url: URL,
                                    options: NSFileCoordinator.WritingOptions,
                                    _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { actual in
            result = Result { try body(actual) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    public func read(_ url: URL) throws -> Data {
        try coordinate(url, options: []) { try direct.read($0) }
    }

    public func write(_ data: Data, to url: URL) throws {
        try coordinateWrite(url, options: .forReplacing) { try direct.write(data, to: $0) }
    }

    public func remove(_ url: URL) throws {
        guard direct.exists(url) else { return }
        try coordinateWrite(url, options: .forDeleting) { try direct.remove($0) }
    }

    public func removeDirectory(_ url: URL) throws { try remove(url) }

    public func move(_ url: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        coordinator().coordinate(writingItemAt: url, options: .forMoving,
                                 writingItemAt: destination, options: .forReplacing,
                                 error: &coordinationError) { source, target in
            do { try direct.move(source, to: target) } catch { moveError = error }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        try coordinate(url, options: []) { try direct.contentsOfDirectory($0) }
    }

    public func createDirectoryIfNeeded(_ url: URL) throws {
        guard !direct.exists(url) else { return }
        try direct.createDirectoryIfNeeded(url)
    }

    public func exists(_ url: URL) -> Bool { direct.exists(url) }
    public func isDirectory(_ url: URL) -> Bool { direct.isDirectory(url) }
    public func modificationDate(_ url: URL) -> Date? { direct.modificationDate(url) }
}
