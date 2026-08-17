import Foundation
import LibraryKit

/// Where the wallpapers actually live.
///
/// iCloud is the user's own storage, not a service — the app has no account, no server and no
/// network after the model download. When iCloud is switched off or signed out, the app does not
/// degrade: it writes to a local folder and **says so**. The one thing it must never do is imply
/// that a wallpaper is syncing when it is not.
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

    /// The gallery caption's tail. Two different sentences because they are two different truths.
    var captionSuffix: String {
        isCloud ? "in your iCloud folder" : "on this device"
    }

    /// The empty state's promise, which must match where the files will really go.
    var emptyStatePromise: String {
        isCloud
            ? "Wallpapers you make will gather here — created on this device, kept in your iCloud."
            : "Wallpapers you make will gather here — created and kept on this device."
    }
}

/// Resolves the storage root once per launch.
enum LibraryLocator {

    static let containerIdentifier = "iCloud.oleksandr.aisixteen.wallpapers"

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

    /// Application Support, not Documents: on iOS the app's Documents folder is exposed by
    /// `UIFileSharingEnabled` and backed up, and this is a cache-like store of things the user can
    /// always remake. It is still not `Caches` — the system may purge that, and losing a wallpaper
    /// the user liked because the disk got tight is not acceptable.
    static func localFallbackRoot(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory,
                                         in: .userDomainMask,
                                         appropriateFor: nil,
                                         create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Wallpapers", isDirectory: true)
    }

    /// The library for a location, with the right file access for it.
    ///
    /// Coordination is only used where it earns its latency: the iCloud container has another
    /// process reading it, the local folder does not.
    static func library(for location: StorageLocation, appVersion: String) -> WallpaperLibrary {
        WallpaperLibrary(root: location.root,
                         access: location.isCloud ? CoordinatedFileAccess() : DirectFileAccess(),
                         appVersion: appVersion)
    }
}
