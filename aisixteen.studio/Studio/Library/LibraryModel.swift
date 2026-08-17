import SwiftUI
import CoreGraphics
import Observation
import RecipeKit
import EditsKit

/// The library's contents, and the thumbnails for them.
///
/// Thumbnails are cached in memory only. They are cheap to remake from files the user owns, and a
/// thumbnail cache on disk inside the iCloud container would sync derived data between the user's
/// devices — paying for bytes twice and putting files in their folder that they did not make.
@MainActor
@Observable
final class LibraryModel {

    private(set) var records: [EditRecord] = []
    private(set) var location: StorageLocation
    private(set) var isLoading = false

    private let library: EditLibrary
    private var enhancedThumbnails: [EditIdentifier: CGImage] = [:]
    private var originalThumbnails: [EditIdentifier: CGImage] = [:]

    init(location: StorageLocation, library: EditLibrary) {
        self.location = location
        self.library = library
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        let library = self.library
        let loaded = await Task.detached(priority: .userInitiated) { () -> [EditRecord] in
            try? library.prepare()
            return (try? library.load()) ?? []
        }.value

        records = loaded
        for record in loaded {
            await loadThumbnails(for: record)
        }
    }

    func thumbnail(for record: EditRecord) -> CGImage? { enhancedThumbnails[record.id] }
    func originalThumbnail(for record: EditRecord) -> CGImage? { originalThumbnails[record.id] }

    /// Reads the original and, if there is one, the enhanced copy.
    ///
    /// A record with no enhanced file is normal — an edit that was imported and then reverted, or
    /// one whose bytes have not come down from iCloud yet. The tile shows the original in that case
    /// rather than a blank rectangle.
    private func loadThumbnails(for record: EditRecord) async {
        guard record.availability.isLocal else { return }
        let library = self.library

        let pair = await Task.detached(priority: .utility) { () -> (CGImage?, CGImage?) in
            let original = (try? library.readOriginal(record)).flatMap(ImageCoder.decode)
            let enhanced = ((try? library.readEnhanced(record)) ?? nil).flatMap(ImageCoder.decode)
            return (Self.thumbnail(original), Self.thumbnail(enhanced ?? original))
        }.value

        originalThumbnails[record.id] = pair.0
        enhancedThumbnails[record.id] = pair.1
    }

    /// Downscales for the grid. A 48-megapixel photo held at full size per tile is how a library
    /// screen gets terminated for memory on a phone.
    nonisolated private static func thumbnail(_ image: CGImage?, maximumEdge: Int = 400) -> CGImage? {
        guard let image else { return nil }
        let longest = max(image.width, image.height)
        guard longest > maximumEdge else { return image }

        let scale = Double(maximumEdge) / Double(longest)
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    // MARK: Import

    /// Copies an imported photo into a new edit folder and seals the original.
    ///
    /// Returns `nil` for anything that will not decode — a file the picker offered but CoreGraphics
    /// cannot open. Better an ignored pick than an edit whose original is a file the app can never
    /// show.
    func importPhoto(data: Data, displayName: String, now: Date = Date()) async -> (EditRecord, CGImage)? {
        guard let decoded = ImageCoder.decode(data) else { return nil }
        let normalised = ImageCoder.normalisingOrientation(decoded, ImageCoder.orientation(of: data))

        let library = self.library
        let seed = UInt32.random(in: 1...UInt32.max)
        let record = await Task.detached(priority: .userInitiated) { () -> EditRecord? in
            try? library.prepare()
            return try? library.create(originalData: data,
                                       fileExtension: Self.fileExtension(of: data),
                                       displayName: displayName,
                                       seed: seed,
                                       createdAt: now)
        }.value

        guard let record else { return nil }
        await reload()
        return (record, normalised)
    }

    func open(_ record: EditRecord) -> CGImage? {
        guard let data = try? library.readOriginal(record),
              let decoded = ImageCoder.decode(data) else { return nil }
        return ImageCoder.normalisingOrientation(decoded, ImageCoder.orientation(of: data))
    }

    func delete(_ record: EditRecord) async {
        let library = self.library
        await Task.detached(priority: .utility) { try? library.delete(record) }.value
        await reload()
    }

    var editLibrary: EditLibrary { library }

    /// Sniffs the container from the bytes so the stored original keeps the extension it really is,
    /// rather than whatever the picker felt like calling it.
    nonisolated private static func fileExtension(of data: Data) -> String {
        guard data.count > 12 else { return "img" }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes[4...7] == [0x66, 0x74, 0x79, 0x70] { return "heic" }   // ISO-BMFF 'ftyp'
        return "img"
    }
}
