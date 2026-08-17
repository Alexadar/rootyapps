import Foundation
import RecipeKit

/// One edit's folder name, and its identity everywhere else.
///
/// Sortable by construction — the timestamp leads — so a library listing is chronological without
/// reading a single file's metadata, which matters when half the folder is in iCloud and not yet
/// downloaded.
public struct EditIdentifier: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// `2026-08-12-0104-c0ffee`. The seed is in the name so two edits made in the same minute
    /// cannot collide, and so a folder in Finder can be matched back to a recipe by eye.
    public static func make(createdAt: Date, seed: UInt32) -> EditIdentifier {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: createdAt)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d",
                           parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                           parts.hour ?? 0, parts.minute ?? 0)
        return EditIdentifier(rawValue: "\(stamp)-\(String(seed, radix: 16))")
    }

    public var description: String { rawValue }
}

/// Whether the edit's files are actually here.
///
/// Board `1f`'s third tile. A file synced from another device exists as a stub until something asks
/// for it, and a library that pretended otherwise would show a blank tile with no explanation.
public enum EditAvailability: Sendable, Hashable {
    case local
    /// In iCloud, not yet on this device. `fraction` is `nil` until a download starts.
    case notDownloaded
    case downloading(fraction: Double?)

    public var isLocal: Bool { self == .local }

    /// What the tile says. Never "unavailable" — the file is not lost, it is elsewhere.
    public var caption: String? {
        switch self {
        case .local:        return nil
        case .notDownloaded: return "From your iPad"
        case .downloading:   return "Downloading…"
        }
    }
}

/// An edit as the library knows it: where its files are, what the recipe says, and whether the
/// bytes are actually on this device.
public struct EditRecord: Sendable, Hashable, Identifiable {

    public let id: EditIdentifier
    public let folder: URL
    public var recipe: EditRecipe
    public var availability: EditAvailability
    /// The name the user recognises — the imported file's stem, e.g. `IMG_4021`.
    public var displayName: String

    public init(id: EditIdentifier,
                folder: URL,
                recipe: EditRecipe,
                availability: EditAvailability = .local,
                displayName: String) {
        self.id = id
        self.folder = folder
        self.recipe = recipe
        self.availability = availability
        self.displayName = displayName
    }

    /// ⚠️ Read-only, always. Nothing in this app opens it for writing after the import.
    public var originalURL: URL { folder.appendingPathComponent(recipe.sourceFilename) }

    /// The only file the app ever writes over.
    public var enhancedURL: URL { folder.appendingPathComponent(EditLayout.enhancedFilename) }

    public var recipeURL: URL { folder.appendingPathComponent(EditLayout.recipeFilename) }

    public func maskURL(_ source: MaskSource) -> URL {
        folder.appendingPathComponent(EditLayout.masksFolder, isDirectory: true)
            .appendingPathComponent(source.filename)
    }

    /// The badge on the library tile (`1f`): the strength and scope it was made with.
    public var badge: String {
        guard let layer = recipe.composite().layers.last,
              let edit = recipe.edit(for: layer.scope) else { return "Original" }
        let strength = Int(edit.strength.value.rounded())
        return layer.scope == .whole ? "\(strength)" : "\(strength) · \(layer.scope.displayName)"
    }
}

/// The on-disk shape of one edit. One place, so nothing spells a filename twice.
///
/// ```
/// <root>/<edit-id>/
///   original.<ext>     0444, digest recorded — read-only forever
///   recipe.json        what to do to it
///   masks/…            segmentation.png, brush.png
///   enhanced.heic      the ONLY file the app writes
/// ```
public enum EditLayout {
    public static let recipeFilename = "recipe.json"
    public static let enhancedFilename = "enhanced.heic"
    public static let masksFolder = "masks"
    public static let originalStem = "original"
    /// The name the photo had when it was imported — `IMG_4021`. Kept beside the files rather than
    /// inside the folder name, which has to stay a sortable identifier.
    public static let nameFilename = "name.txt"

    /// Permissions on the original: readable by the owner and nobody's to write.
    ///
    /// This is a *belt* — the app also never opens it for writing — but it is the belt that catches
    /// a future refactor. `0444` makes an accidental write fail loudly at the file system instead of
    /// quietly succeeding and destroying the one file that cannot be regenerated.
    public static let originalPermissions: Int = 0o444

    public static func originalFilename(extension ext: String) -> String {
        let cleaned = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        return cleaned.isEmpty ? originalStem : "\(originalStem).\(cleaned)"
    }
}
