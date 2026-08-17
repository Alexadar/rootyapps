import Foundation

/// One file's download state, as the library needs it.
struct ItemState: Equatable {
    var isDownloaded: Bool
    var fraction: Double
}

/// Notices when the library changes, whichever kind of folder it is.
///
/// Two completely different mechanisms behind one callback, because the library model should not
/// have to care which storage it got: `NSMetadataQuery` for the ubiquity container (it is the only
/// thing that reports download progress for files that exist elsewhere), and a `DispatchSource`
/// vnode watch for the local fallback (there is no metadata to query — files are simply there).
@MainActor
final class ProjectWatcher {

    private let location: StorageLocation
    private var query: NSMetadataQuery?
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var observers: [NSObjectProtocol] = []

    /// Keyed by path RELATIVE TO THE ROOT, not by `lastPathComponent`.
    ///
    /// `01-3f9c1a.png` is not unique across projects — every project's first variation can be
    /// called that — so a filename key silently reports one project's download progress on
    /// another's tile.
    private(set) var items: [String: ItemState] = [:]

    var onChange: (() -> Void)?

    init(location: StorageLocation) {
        self.location = location
    }

    func start() {
        switch location {
        case .iCloud: startMetadataQuery()
        case .local: startVnodeWatch()
        }
    }

    func stop() {
        query?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        query = nil
        source?.cancel()
        source = nil
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // ── iCloud ───────────────────────────────────────────────────────────────────────────────

    private func startMetadataQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        // Asking for these up front is what makes a percentage available at all; without them the
        // ghost tiles can only say "not here yet".
        query.valueListAttributes = [NSMetadataUbiquitousItemDownloadingStatusKey,
                                     NSMetadataUbiquitousItemPercentDownloadedKey,
                                     NSMetadataUbiquitousItemIsDownloadingKey]

        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering,
                     NSNotification.Name.NSMetadataQueryDidUpdate] {
            let token = NotificationCenter.default.addObserver(forName: name,
                                                               object: query,
                                                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.absorb(query) }
            }
            observers.append(token)
        }

        self.query = query
        query.start()
    }

    private func absorb(_ query: NSMetadataQuery) {
        // Updates are disabled around the read: the results array is live, and iterating it while
        // the query mutates it is a crash that only happens on a busy sync.
        query.disableUpdates()
        defer { query.enableUpdates() }

        var next: [String: ItemState] = [:]
        let rootPath = location.root.standardizedFileURL.path

        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            let relative = String(path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
            guard !relative.isEmpty else { continue }

            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double
            let downloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
                || status == NSMetadataUbiquitousItemDownloadingStatusDownloaded

            next[relative] = ItemState(isDownloaded: downloaded,
                                       fraction: downloaded ? 1 : (percent ?? 0) / 100)
        }

        items = next
        onChange?()
    }

    /// Fetch on demand, never speculatively.
    ///
    /// The library asks for `project.json` and `thumb.jpg` — a few kilobytes — so a space can show
    /// its real name and picture. A full variation PNG is fetched only when the user opens it.
    /// Their data allowance is theirs.
    func requestDownload(of url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    func state(forRelativePath path: String) -> ItemState? { items[path] }

    // ── local ────────────────────────────────────────────────────────────────────────────────

    private func startVnodeWatch() {
        try? FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        descriptor = open(location.root.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                                eventMask: [.write, .delete, .rename],
                                                                queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        self.source = source
        source.resume()
    }
}
