import Foundation

/// The folder name: `<slug>-<timestamp>-<tag>`, e.g. `Living-room-2026-08-12T14-22-05Z-3f9c1a`.
///
/// It has to work in the Files app, because the whole storage promise is that the user can open
/// this folder themselves. That rules out a bare UUID (unreadable) and a bare display name
/// (collides the second someone redesigns their living room twice). The timestamp makes Finder
/// sort it usefully without the app's help, and the tag makes collisions impossible.
public enum ProjectFolderName {

    public static let separator = "-"
    static let tagLength = 6
    /// How many hyphen-separated components `stamp(_:)` produces.
    static let stampComponentCount = 5

    /// Characters that are legal on APFS but a problem somewhere else in the chain — a colon is
    /// the classic one, legal here and a path separator in the classic Mac world, which shows up
    /// as a mangled name the moment a folder is zipped or synced through anything older.
    static let allowed = CharacterSet.alphanumerics

    public static func slug(_ displayName: String) -> String {
        let scalars = displayName.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let trimmed = String(collapsed.prefix(48))
        return trimmed.isEmpty ? "Space" : trimmed
    }

    /// Colons become hyphens: `2026-08-12T14-22-05Z`.
    public static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
    }

    public static func tag(_ seed: UInt32) -> String {
        String(format: "%06x", seed & 0xFF_FFFF)
    }

    public static func make(displayName: String, createdAt: Date, seed: UInt32) -> String {
        [slug(displayName), stamp(createdAt), tag(seed)].joined(separator: separator)
    }

    /// Recover the human part for a ghost space, whose sidecar has not synced yet.
    public static func displayName(fromFolder folder: String) -> String {
        let parts = folder.components(separatedBy: separator)
        // `2026-08-12T14-22-00Z` splits into FIVE components (2026, 08, 12T14, 22, 00Z) because the
        // date and the time are hyphen-separated but the T is not. Plus the tag, that is six —
        // so the slug is everything before the last six, and a folder with six or fewer components
        // was not written by this app.
        guard parts.count > stampComponentCount + 1 else { return folder }
        return parts.dropLast(stampComponentCount + 1).joined(separator: " ")
    }

    public static func date(fromFolder folder: String) -> Date? {
        let parts = folder.components(separatedBy: separator)
        guard parts.count > stampComponentCount + 1 else { return nil }
        let stampParts = parts.dropLast(1).suffix(stampComponentCount)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.date(from: stampParts.joined(separator: separator))
    }

    /// An automatic name for a project, because no screen asks for one.
    ///
    /// ⚠️ A decision the design handoff does not make: it says a project is "my living room" but
    /// no screen collects that. Rather than add a naming step between the shutter and the
    /// redesign — the one moment the user most wants to get on with it — projects are named
    /// automatically and renamed from the Library or the Mac sidebar whenever the user cares.
    public static func automaticDisplayName(mode: SpaceMode,
                                            createdAt: Date,
                                            locale: Locale = .current,
                                            calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        let noun = mode == .interior ? "Interior" : "Exterior"
        return "\(noun) — \(formatter.string(from: createdAt))"
    }
}

/// The names of everything inside a project folder.
public enum ProjectFile {
    public static let sidecar = "project.json"
    public static let source = "source.heic"
    /// Single-channel 32-bit float disparity. PNG cannot hold float, and quantising to 8 bits here
    /// would throw away the precision a future larger-shape model could use.
    public static let depth = "depth.tiff"
    public static let thumbnail = "thumb.jpg"
    public static let variationsFolder = "variations"

    public static func variationImage(index: Int, seed: UInt32) -> String {
        String(format: "%02d-%@.png", index, ProjectFolderName.tag(seed))
    }

    public static func variationSidecar(index: Int, seed: UInt32) -> String {
        String(format: "%02d-%@.json", index, ProjectFolderName.tag(seed))
    }

    /// Parse `01-3f9c1a.png` back to its index.
    public static func variationIndex(fromFilename filename: String) -> Int? {
        let stem = (filename as NSString).deletingPathExtension
        guard let first = stem.components(separatedBy: "-").first else { return nil }
        return Int(first)
    }
}
