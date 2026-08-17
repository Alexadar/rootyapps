import Foundation
import GenerationKit

/// Everything stored beside a wallpaper.
///
/// **Why a sidecar file and not PNG metadata.** Three reasons, all of them things that happen. A
/// file synced from another device may not be downloaded yet — its EXIF is unreadable, but a 200-byte
/// sidecar arrives first and the grid can still show the prompt. Reading a chunk out of a
/// twelve-megapixel PNG to list a grid means decoding every image in the gallery. And the user can
/// see this folder in the Files app: a JSON next to a PNG is legible and copyable; a private EXIF
/// tag is neither, and would silently not survive being airdropped somewhere.
///
/// A single index file was the other option and is worse: two devices writing it concurrently
/// produce an iCloud conflict over the whole library rather than over one picture.
public struct WallpaperMetadata: Codable, Sendable, Equatable {
    /// Schema version. Present from day one so a later field can be added without guessing whether
    /// an old sidecar simply lacked it or was written by something broken.
    public var version: Int
    public var prompt: String
    public var seed: UInt32
    public var width: Int
    public var height: Int
    public var createdAt: Date
    /// Which build made it. Useful the first time a model update changes what a prompt produces.
    public var appVersion: String

    public static let currentVersion = 1

    public init(prompt: String, seed: UInt32, aspect: AspectRatio, createdAt: Date, appVersion: String) {
        self.version = Self.currentVersion
        self.prompt = prompt
        self.seed = seed
        self.width = aspect.width
        self.height = aspect.height
        self.createdAt = createdAt
        self.appVersion = appVersion
    }

    public var aspect: AspectRatio { AspectRatio(width: width, height: height) }
}

/// One wallpaper in the library: its identity, its metadata and where its two files are.
public struct WallpaperRecord: Sendable, Equatable, Identifiable {
    /// The shared filename stem of the image and its sidecar. Stable, sortable, and the same on
    /// every device — so it is also the identity.
    public let id: String
    public let metadata: WallpaperMetadata
    public let imageURL: URL
    public let sidecarURL: URL

    public init(id: String, metadata: WallpaperMetadata, imageURL: URL, sidecarURL: URL) {
        self.id = id
        self.metadata = metadata
        self.imageURL = imageURL
        self.sidecarURL = sidecarURL
    }

    public var prompt: String { metadata.prompt }
    public var seed: UInt32 { metadata.seed }
    public var aspect: AspectRatio { metadata.aspect }
    public var createdAt: Date { metadata.createdAt }
}

/// How a record is named on disk.
///
/// `2026-08-10T14-22-05Z-3f9c1a` — an ISO-8601 instant with the colons swapped for hyphens, then a
/// short hex tag. The date is first because it makes the folder sort newest-last in Finder without
/// the app's help, which matters when the user opens it in Files; the tag is there because two
/// wallpapers can be finished inside the same second and the seed distinguishes them.
///
/// Colons cannot appear in a filename the user will see: legal on APFS, but they are the classic
/// path separator on older Mac software and break naive shell handling.
public enum WallpaperFilename {

    public static let imageExtension = "png"
    public static let sidecarExtension = "json"

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The stem for a wallpaper. Deterministic: the same instant and seed always name the same file,
    /// so a retry after a half-finished write overwrites rather than accumulating.
    public static func stem(createdAt: Date, seed: UInt32) -> String {
        let stamp = formatter.string(from: createdAt).replacingOccurrences(of: ":", with: "-")
        let tag = String(format: "%06x", seed & 0x00FF_FFFF)
        return "\(stamp)-\(tag)"
    }

    public static func imageName(_ stem: String) -> String { "\(stem).\(imageExtension)" }
    public static func sidecarName(_ stem: String) -> String { "\(stem).\(sidecarExtension)" }

    /// The stem for a file on disk, or `nil` if it is not one of ours. Used when walking a folder
    /// the user can also drop things into — an unrelated PDF in the iCloud folder must be ignored,
    /// not crash a listing.
    public static func stem(forFileNamed name: String) -> String? {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension.lowercased()
        guard ext == imageExtension || ext == sidecarExtension else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? nil : stem
    }
}
