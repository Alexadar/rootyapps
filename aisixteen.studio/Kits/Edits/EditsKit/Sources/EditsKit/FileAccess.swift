import Foundation

/// How the library touches the disk.
///
/// Two implementations, one difference: the iCloud container has another process reading and
/// writing it, the local fallback does not. Coordination is only used where it earns its latency —
/// but the *code above this protocol is identical for both*, which is what makes "iCloud switched
/// off" a tested configuration rather than an untested branch.
public protocol FileAccess: Sendable {
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    func createDirectory(_ url: URL) throws
    func contentsOfDirectory(_ url: URL) throws -> [URL]
    func exists(_ url: URL) -> Bool
    func setPermissions(_ permissions: Int, on url: URL) throws
    func permissions(of url: URL) throws -> Int
}

/// The local folder. No coordinator, because nothing else is looking at it.
public struct DirectFileAccess: FileAccess {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func remove(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: url,
                                                   includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])
    }

    public func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }

    public func setPermissions(_ permissions: Int, on url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    public func permissions(of url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}

/// The iCloud container. Every read and write goes through `NSFileCoordinator` so the sync daemon
/// and this app never see each other's half-written files.
public struct CoordinatedFileAccess: FileAccess {

    private let direct: DirectFileAccess

    public init(fileManager: FileManager = .default) {
        self.direct = DirectFileAccess(fileManager: fileManager)
    }

    public func read(_ url: URL) throws -> Data {
        try coordinate(reading: url) { try direct.read($0) }
    }

    public func write(_ data: Data, to url: URL) throws {
        try coordinate(writing: url) { try direct.write(data, to: $0) }
    }

    public func remove(_ url: URL) throws {
        // `.forDeleting` is not decoration: it tells the daemon to stop presenting the item first,
        // which is what stops a delete racing a sync and reappearing a minute later.
        try coordinate(writing: url, options: .forDeleting) { try direct.remove($0) }
    }

    public func createDirectory(_ url: URL) throws {
        try direct.createDirectory(url)
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        try direct.contentsOfDirectory(url)
    }

    public func exists(_ url: URL) -> Bool { direct.exists(url) }

    public func setPermissions(_ permissions: Int, on url: URL) throws {
        try direct.setPermissions(permissions, on: url)
    }

    public func permissions(of url: URL) throws -> Int { try direct.permissions(of: url) }

    private func coordinate<T>(reading url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        // The accessor's URL is the one to use, not the one passed in: the coordinator may hand
        // back a different location when the item is being moved underneath us.
        NSFileCoordinator().coordinate(readingItemAt: url,
                                       options: NSFileCoordinator.ReadingOptions(),
                                       error: &coordinatorError,
                                       byAccessor: { (readURL: URL) in
            result = Result { try body(readURL) }
        })
        if let coordinatorError { throw coordinatorError }
        return try result!.get()
    }

    private func coordinate(writing url: URL,
                            options: NSFileCoordinator.WritingOptions = [],
                            _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url,
                                       options: options,
                                       error: &coordinatorError,
                                       byAccessor: { (writeURL: URL) in
            result = Result { try body(writeURL) }
        })
        if let coordinatorError { throw coordinatorError }
        try result!.get()
    }
}
