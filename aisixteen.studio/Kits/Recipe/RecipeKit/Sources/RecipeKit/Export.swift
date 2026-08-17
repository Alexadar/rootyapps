import Foundation

/// The export sheet's rows (`1e`), and the exact sentence each one owes the user.
///
/// The copy lives in a Foundation value so it can be asserted. That is not pedantry: the whole
/// position of this app is that it never touches the original, and the only place the user is told
/// what happens to their file is here. A row whose wording drifts into something ambiguous is a
/// product failure, so the tests check that every row names the fate of the original out loud.
public enum ExportOption: String, CaseIterable, Sendable, Codable, Hashable {

    /// The default, and the one that keeps both files.
    case saveAsNew
    case share

    public static let `default` = ExportOption.saveAsNew

    public var title: String {
        switch self {
        case .saveAsNew: return "Save as new photo"
        case .share:     return "Share…"
        }
    }

    /// ⚠️ Literal, never ambiguous. The handoff's wording, unchanged.
    public var fateOfTheOriginal: String {
        switch self {
        case .saveAsNew:
            return "The enhanced copy lands next to your original in Photos. Nothing is overwritten."
        case .share:
            return "Sends the enhanced copy. Your original stays where it is."
        }
    }

    /// True for every case, and a test asserts it: a row that does not say what happens to the
    /// original has no business in this sheet.
    public var namesTheOriginal: Bool {
        fateOfTheOriginal.lowercased().contains("original")
    }

    /// Whether the row needs permission to add to the photo library. `share` hands the file to the
    /// share sheet and asks for nothing.
    public var needsPhotoLibraryAddAccess: Bool { self == .saveAsNew }

    public var primaryButtonTitle: String {
        switch self {
        case .saveAsNew: return "Save as New Photo"
        case .share:     return "Share"
        }
    }
}

/// The sheet's footer, and the two other places the privacy promise is allowed to appear.
///
/// Board `1j`: the promise is made in **exactly three places, once each** — the import footer, the
/// export rows, and the export footer. Repeating it anywhere else reads as marketing, which is the
/// opposite of the effect wanted. They are collected here so that rule is checkable.
public enum PrivacyCopy {
    /// Import screen (`1a`).
    public static let importFooter = "No account · No network · Your photo never leaves this device"
    /// Export sheet footer (`1e`). The device name is substituted by the caller.
    public static func exportFooter(deviceName: String) -> String {
        "Enhanced on this \(deviceName). Never uploaded."
    }

    /// The three sanctioned places, for the test that counts them.
    public static let sanctionedPlaces = 3
}
