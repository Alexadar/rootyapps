import Foundation
import EditsKit

/// Where the edits actually live.
///
/// iCloud is the user's own storage, not a service — the app has no account, no server and no
/// network at all. When iCloud is switched off or signed out, the app does not degrade: it writes to
/// a local folder and **says so**. The one thing it must never do is imply that an edit is syncing
/// when it is not.
enum StorageLocation: Equatable {
    case iCloud(URL)
    case local(URL)

    var root: URL {
        switch self {
        case .iCloud(let url), .local(let url): return url
        }
    }

    var isCloud: Bool {
        if case .iCloud = self { return true }
        return false
    }

    /// The library caption's tail. Two different sentences because they are two different truths.
    var captionSuffix: String {
        isCloud ? "in your iCloud folder" : "on this device"
    }

    /// ⚠️ User-owned storage language only. "Your folder", never "your account"; "kept", never
    /// "uploaded" or "backed up to".
    var libraryPromise: String {
        isCloud
            ? "Yours, in your iCloud folder — open it anytime in Files."
            : "Yours, on this device — iCloud Drive is off, so nothing syncs."
    }

    var emptyStatePromise: String {
        isCloud
            ? "Photos you enhance will gather here — made on this device, kept in your iCloud folder."
            : "Photos you enhance will gather here — made and kept on this device."
    }
}

/// Resolves the storage root once per launch.
enum LibraryLocator {

    static let containerIdentifier = "iCloud.oleksandr.aisixteen.studio"

    /// The user-visible folder inside the container. `Documents` is not decoration — it is what
    /// `NSUbiquitousContainerIsDocumentScopePublic` exposes in the Files app, and a container
    /// without it holds files the user can never see.
    private static let documentsFolder = "Documents"

    /// **Blocking.** `url(forUbiquityContainerIdentifier:)` talks to the sync daemon and can take
    /// hundreds of milliseconds on first use. Calling it on the main actor is a hitch on launch, so
    /// this is deliberately not main-actor-isolated and every caller awaits it off the main thread.
    static func resolve(fileManager: FileManager = .default) -> StorageLocation {
        if let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) {
            return .iCloud(container.appendingPathComponent(documentsFolder, isDirectory: true))
        }
        return .local(localFallbackRoot(fileManager: fileManager))
    }

    /// Application Support, not Documents and **not Caches**: the system may purge Caches, and
    /// losing an edit the user liked because the disk got tight is not acceptable.
    static func localFallbackRoot(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Edits", isDirectory: true)
    }

    /// The library for a location, with the right file access for it.
    ///
    /// Coordination is only used where it earns its latency: the iCloud container has another
    /// process reading it, the local folder does not.
    static func library(for location: StorageLocation, appVersion: String) -> EditLibrary {
        EditLibrary(root: location.root,
                    access: location.isCloud ? CoordinatedFileAccess() : DirectFileAccess(),
                    appVersion: appVersion)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
