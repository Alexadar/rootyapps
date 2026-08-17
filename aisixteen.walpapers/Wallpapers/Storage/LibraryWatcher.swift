import Foundation

/// Notices when the library changes, by whichever mechanism the storage location needs.
///
/// The two sources are genuinely different problems. An iCloud folder changes because *another
/// device* wrote to it, and the only thing that reports that — along with whether a file's bytes
/// have actually arrived — is `NSMetadataQuery`. A local folder only ever changes because this app
/// wrote to it, and a `DispatchSource` vnode watch is enough. Both are collapsed to one callback so
/// `LibraryModel` has a single path.
@MainActor
final class LibraryWatcher {

    /// What iCloud knows about one file.
    struct ItemState {
        var isDownloaded: Bool
        var fraction: Double?
    }

    private let location: StorageLocation
    private let onChange: () -> Void

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryHandle: CInt = -1
    private var states: [String: ItemState] = [:]

    init(location: StorageLocation, onChange: @escaping () -> Void) {
        self.location = location
        self.onChange = onChange
    }

    deinit {
        // `deinit` cannot hop to the main actor, and the vnode descriptor must not leak.
        if directoryHandle >= 0 { close(directoryHandle) }
    }

    func start() {
        location.isCloud ? startMetadataQuery() : startDirectoryWatch()
    }

    func stop() {
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        query = nil
        directorySource?.cancel()
        directorySource = nil
    }

    func itemStates() -> [String: ItemState] { states }

    // MARK: iCloud

    private func startMetadataQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Everything in our folder. The predicate cannot be narrowed to an extension without also
        // excluding the sidecars, and we want both.
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        query.valueListAttributes = [
            NSMetadataUbiquitousItemDownloadingStatusKey,
            NSMetadataUbiquitousItemPercentDownloadedKey,
            NSMetadataUbiquitousItemIsDownloadingKey,
        ]

        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering,
                     NSNotification.Name.NSMetadataQueryDidUpdate] {
            let observer = NotificationCenter.default.addObserver(forName: name,
                                                                 object: query,
                                                                 queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.absorb() }
            }
            observers.append(observer)
        }

        self.query = query
        query.start()
    }

    private func absorb() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var next: [String: ItemState] = [:]
        for row in 0..<query.resultCount {
            guard let item = query.result(at: row) as? NSMetadataItem,
                  let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String
            else { continue }

            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? NSNumber

            // `.current` means the local copy is the newest. `.downloaded` means a copy exists but
            // is out of date — still openable, so still "here" as far as the grid is concerned.
            let downloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
                          || status == NSMetadataUbiquitousItemDownloadingStatusDownloaded
            next[name] = ItemState(isDownloaded: downloaded,
                                   fraction: percent.map { $0.doubleValue / 100 })
        }

        states = next
        // Every update is forwarded, including ones that only move a download percentage: the ghost
        // tiles show that percentage, so "nothing important changed" is not ours to decide here.
        onChange()
    }

    // MARK: Local

    private func startDirectoryWatch() {
        let path = location.root.path
        try? FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        directoryHandle = open(path, O_EVTONLY)
        guard directoryHandle >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: directoryHandle,
                                                               eventMask: [.write, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        source.setCancelHandler { [handle = directoryHandle] in
            if handle >= 0 { close(handle) }
        }
        directoryHandle = -1     // ownership has moved to the cancel handler
        directorySource = source
        source.resume()
    }
}
