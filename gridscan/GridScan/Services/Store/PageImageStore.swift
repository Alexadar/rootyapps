import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// File custody for large binaries: imported originals + per-page renders + thumbnails.
/// SwiftData rows never hold image data (CKAsset candidates in v2). Layout:
///   Application Support/GridScan/Documents/<docUUID>/original.<ext>
///   Application Support/GridScan/Documents/<docUUID>/pages/page-<i>.heic|png
///   Application Support/GridScan/Documents/<docUUID>/pages/thumb-<i>.heic|png
enum PageImageStore {

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("GridScan/Documents", isDirectory: true)
    }

    static func directory(documentID: UUID) -> URL {
        root.appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    static func pagesDirectory(documentID: UUID) -> URL {
        directory(documentID: documentID).appendingPathComponent("pages", isDirectory: true)
    }

    @discardableResult
    static func copyOriginal(from source: URL, documentID: UUID) throws -> URL {
        let dir = directory(documentID: documentID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("original." + source.pathExtension.lowercased())
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    /// Writes a page render + its thumbnail. HEIC when the encoder is available, PNG
    /// otherwise (simulators sometimes lack HEIC encode) — the actual URL is returned.
    @discardableResult
    static func writePage(_ image: CGImage, index: Int, documentID: UUID) throws -> URL {
        let dir = pagesDirectory(documentID: documentID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = try write(image, to: dir, name: "page-\(index)")
        if let thumb = thumbnail(of: image, maxSide: 480) {
            _ = try? write(thumb, to: dir, name: "thumb-\(index)")
        }
        return url
    }

    static func pageURL(documentID: UUID, index: Int) -> URL? {
        firstExisting(in: pagesDirectory(documentID: documentID), name: "page-\(index)")
    }

    static func thumbnailURL(documentID: UUID, index: Int) -> URL? {
        firstExisting(in: pagesDirectory(documentID: documentID), name: "thumb-\(index)")
    }

    /// Document split support: copy selected page files (re-indexed from 0) to a new doc.
    static func copyPages(from source: UUID, pageIndices: [Int], to dest: UUID) {
        let destDir = pagesDirectory(documentID: dest)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        for (newIndex, oldIndex) in pageIndices.enumerated() {
            for prefix in ["page", "thumb"] {
                guard let src = firstExisting(in: pagesDirectory(documentID: source),
                                              name: "\(prefix)-\(oldIndex)") else { continue }
                let out = destDir.appendingPathComponent("\(prefix)-\(newIndex)."
                                                         + src.pathExtension)
                try? FileManager.default.copyItem(at: src, to: out)
            }
        }
    }

    static func removeDirectory(documentID: UUID) {
        try? FileManager.default.removeItem(at: directory(documentID: documentID))
    }

    /// Files first, row last — sweep directories whose row never landed.
    static func sweepOrphans(knownIDs: Set<UUID>) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  !knownIDs.contains(id) else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    // MARK: encoding

    private static func write(_ image: CGImage, to dir: URL, name: String) throws -> URL {
        for (type, ext) in [(UTType.heic, "heic"), (UTType.png, "png")] {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                          type.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                if CGImageDestinationFinalize(dest) { return url }
            }
        }
        throw CocoaError(.fileWriteUnknown)
    }

    private static func firstExisting(in dir: URL, name: String) -> URL? {
        for ext in ["heic", "png"] {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func thumbnail(of image: CGImage, maxSide: Int) -> CGImage? {
        let w = image.width, h = image.height
        guard max(w, h) > maxSide else { return image }
        let scale = Double(maxSide) / Double(max(w, h))
        let nw = Int(Double(w) * scale), nh = Int(Double(h) * scale)
        guard let ctx = CGContext(data: nil, width: nw, height: nh,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }
}
