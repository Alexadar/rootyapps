import Foundation
import ProjectKit

/// Where the library lives, and the two different truths that follow from it.
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
}

enum ProjectLocator {

    static let containerIdentifier = "iCloud.oleksandr.aisixteen.architecture"
    /// Only `Documents` is exposed by `NSUbiquitousContainerIsDocumentScopePublic`, so everything
    /// the user is promised they can see has to live inside it.
    private static let documentsFolder = "Documents"

    /// **Blocking.** Deliberately not main-actor-isolated.
    ///
    /// `url(forUbiquityContainerIdentifier:)` talks to the sync daemon and can take hundreds of
    /// milliseconds on a cold launch. Calling it on the main actor is a visible hitch on the one
    /// screen the user is staring at while they wait for the app to open.
    nonisolated static func resolve() -> StorageLocation {
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            return .iCloud(container.appendingPathComponent(documentsFolder, isDirectory: true))
        }
        return .local(localFallbackRoot())
    }

    /// Application Support, and specifically NOT the two obvious alternatives:
    ///   • `Caches` is purgeable — the system can and does delete it under pressure, and the user's
    ///     redesigns are not a cache.
    ///   • `Documents` on iOS is exposed separately through `UIFileSharingEnabled`, which would
    ///     make the folder visible through a second, different mechanism with different rules.
    nonisolated static func localFallbackRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Architecture", isDirectory: true)
            .appendingPathComponent(documentsFolder, isDirectory: true)
    }

    /// Coordination only where another device might genuinely be writing.
    static func store(for location: StorageLocation, appVersion: String) -> ProjectStore {
        ProjectStore(root: location.root,
                     access: location.isCloud ? CoordinatedFileAccess() : DirectFileAccess(),
                     appVersion: appVersion)
    }

    /// Honours the DEBUG-only storage override, so a UI test can exercise the local-fallback copy
    /// without switching iCloud off on the machine.
    nonisolated static func resolveWithOverrides() -> StorageLocation {
        if LaunchOverride.value(LaunchOverride.storage) == "off" {
            return .local(localFallbackRoot())
        }
        return resolve()
    }
}
