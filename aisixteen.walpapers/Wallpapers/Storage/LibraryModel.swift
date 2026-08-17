import Foundation
import SwiftUI
import ImageIO
import GenerationKit
import LibraryKit
import FormatKit

/// The gallery's state.
///
/// One API over two very different sources: an `NSMetadataQuery` when the library is in iCloud
/// (which is also how a file synced from another device is noticed, and how its download progress is
/// known), and a directory watch when it is local. Views never learn which.
@MainActor
@Observable
final class LibraryModel {

    /// A wallpaper as the grid needs it: the record, plus whether its bytes are actually here.
    struct Item: Identifiable, Equatable {
        let record: WallpaperRecord
        /// `false` for a wallpaper made on another device that iCloud has not fetched yet. The tile
        /// shows a ghost with real progress rather than a broken image.
        var isDownloaded: Bool
        /// 0–1 while downloading, `nil` when there is nothing to report.
        var downloadFraction: Double?

        var id: String { record.id }
    }

    private(set) var location: StorageLocation?
    private(set) var items: [Item] = []
    private(set) var isLoading = true
    private(set) var loadError: String?

    /// The newest wallpaper, used as the ambient backdrop behind the Create screen.
    private(set) var mostRecentImage: PlatformImage?

    private var library: WallpaperLibrary?
    private var watcher: LibraryWatcher?
    /// Keyed by **id and size**, not by id alone.
    ///
    /// The gallery asks for 600 px and the Create screen's hero asks for 240 px, for the same
    /// wallpaper. With the id as the only key, whichever call landed first won — so opening the app
    /// on Create and then switching to Gallery showed a 240 px thumbnail blown up across a grid
    /// tile, which reads as the app having saved a low-quality picture.
    private var thumbnails: [ThumbnailKey: PlatformImage] = [:]

    private struct ThumbnailKey: Hashable {
        let id: String
        /// Rounded to whole pixels: `CGFloat` is a poor dictionary key, and no caller asks for a
        /// fractional size.
        let maxPixel: Int
    }
    private let appVersion: String

    init(appVersion: String = Bundle.main.shortVersion) {
        self.appVersion = appVersion
    }

    var caption: String {
        guard let location else { return "" }
        return "\(ByteText.wallpaperCount(items.count)) · \(location.captionSuffix)"
    }

    var isEmpty: Bool { items.isEmpty && !isLoading }

    // MARK: Lifecycle

    func start() async {
        // Resolving the ubiquity container blocks; keep it off the main actor so launch does not
        // hitch on a sync daemon that may be slow or asleep.
        let resolved = await Task.detached(priority: .userInitiated) {
            LibraryLocator.resolve()
        }.value
        await start(at: resolved)
    }

    /// The same startup against a named location, so tests can run the real reading and caching code
    /// over a temporary folder instead of the user's actual library.
    func start(at resolved: StorageLocation) async {
        location = resolved
        let library = LibraryLocator.library(for: resolved, appVersion: appVersion)
        self.library = library
        try? library.prepare()

        watcher = LibraryWatcher(location: resolved) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        watcher?.start()
        await refresh()
    }

    func refresh() async {
        guard let library else { return }
        let states = watcher?.itemStates() ?? [:]

        let loaded: Result<[WallpaperRecord], Error> = await Task.detached(priority: .userInitiated) {
            Result { try library.records() }
        }.value

        switch loaded {
        case .failure(let error):
            loadError = error.localizedDescription
        case .success(let records):
            loadError = nil
            items = records.map { record in
                let state = states[record.imageURL.lastPathComponent]
                return Item(record: record,
                            isDownloaded: state?.isDownloaded ?? true,
                            downloadFraction: state?.fraction)
            }
            await loadMostRecentImage()
        }
        isLoading = false
    }

    // MARK: Reading

    /// A downsampled thumbnail for the grid.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` decodes only what it needs; loading twelve-megapixel
    /// PNGs to fill a two-column grid is how a gallery runs a device out of memory.
    func thumbnail(for item: Item, maxPixel: CGFloat = 600) async -> PlatformImage? {
        let key = ThumbnailKey(id: item.id, maxPixel: Int(maxPixel.rounded()))
        if let cached = thumbnails[key] { return cached }
        guard item.isDownloaded else { return nil }
        let url = item.record.imageURL

        let image = await Task.detached(priority: .userInitiated) { () -> PlatformImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return Bitmap.platformImage(cg: cg, width: cg.width, height: cg.height)
        }.value

        if let image { thumbnails[key] = image }
        return image
    }

    /// The full picture, for the single-image view and for setting the desktop.
    func fullImage(for item: Item) async -> PlatformImage? {
        guard let library else { return nil }
        let record = item.record
        return await Task.detached(priority: .userInitiated) { () -> PlatformImage? in
            guard let data = try? library.imageData(for: record) else { return nil }
            return Bitmap.platformImage(pngData: data)
        }.value
    }

    /// Asks iCloud for a file that has not arrived yet. Called when the user opens a ghost tile —
    /// nothing is fetched speculatively, because the user's data allowance is theirs.
    func requestDownload(_ item: Item) {
        guard !item.isDownloaded else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: item.record.imageURL)
        try? FileManager.default.startDownloadingUbiquitousItem(at: item.record.sidecarURL)
    }

    // MARK: Writing

    @discardableResult
    func save(_ image: GeneratedImage) async throws -> WallpaperRecord {
        guard let library else { throw LibraryError.rootUnavailable }
        let record = try await Task.detached(priority: .userInitiated) { () -> WallpaperRecord in
            guard let png = Bitmap.pngData(rgba: image.pixels,
                                           width: image.size.width,
                                           height: image.size.height) else {
                throw LibraryError.rootUnavailable
            }
            return try library.save(imageData: png,
                                    prompt: image.prompt,
                                    seed: image.seed,
                                    aspect: image.size,
                                    createdAt: image.createdAt)
        }.value
        await refresh()
        return record
    }

    /// Drop a cached bitmap because the file behind it changed.
    ///
    /// Enhance rewrites the master **at the same path**, so nothing about the record changes — same
    /// id, same URL — and the cache happily keeps serving the picture from before. That is why an
    /// enhanced wallpaper still showed the old thumbnail and opened the old image: not a stale
    /// refresh, a cache with no notion that bytes can change under a stable name.
    func invalidate(_ id: String) async {
        thumbnails = thumbnails.filter { $0.key.id != id }
        await refresh()
    }

    func delete(_ item: Item) async {
        guard let library else { return }
        let id = item.id
        await Task.detached(priority: .userInitiated) { try? library.delete(id: id) }.value
        thumbnails = thumbnails.filter { $0.key.id != id }
        await refresh()
    }

    // MARK: -

    private func loadMostRecentImage() async {
        guard let newest = items.first, newest.isDownloaded else {
            mostRecentImage = nil
            return
        }
        // Small: it is blurred to sixty points before anyone sees it.
        mostRecentImage = await thumbnail(for: newest, maxPixel: 240)
    }
}

extension Bundle {
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}
