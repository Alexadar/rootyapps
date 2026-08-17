import Foundation

public enum SpaceMode: String, Sendable, Codable, CaseIterable, Hashable {
    case interior
    case exterior
}

public enum DepthProvenance: String, Sendable, Codable, CaseIterable, Hashable {
    case lidar, dualCamera, embedded, estimated, synthetic, none
}

/// What the user asked for. Enough to regenerate the whole project from scratch.
public struct ProjectRecipe: Sendable, Codable, Equatable, Hashable {
    public var presetID: String?
    public var prompt: String
    public var isEdited: Bool
    /// Variation N uses `baseSeed &+ UInt32(N - 1)`, so a project's variations are reproducible
    /// from one number and the user can be told which seed made which picture.
    public var baseSeed: UInt32
    public var requestedVariations: Int

    public init(presetID: String?,
                prompt: String,
                isEdited: Bool,
                baseSeed: UInt32,
                requestedVariations: Int) {
        self.presetID = presetID
        self.prompt = prompt
        self.isEdited = isEdited
        self.baseSeed = baseSeed
        self.requestedVariations = requestedVariations
    }

    public func seed(forVariation index: Int) -> UInt32 {
        baseSeed &+ UInt32(max(index, 1) - 1)
    }
}

/// `project.json` — one per project folder.
///
/// ⚠️ It deliberately does NOT list the variations. Two devices generating into the same project
/// would each rewrite this file and produce an iCloud conflict over the *whole project* rather
/// than over one picture. Variations are discovered by listing `variations/` and reading each
/// per-variation sidecar, so two devices adding different variations never collide at all.
public struct ProjectSidecar: Sendable, Codable, Equatable {
    /// Bumped when the shape changes. An older app reading a newer file must be able to tell.
    public var version: Int
    public var id: String
    public var displayName: String
    public var mode: SpaceMode
    public var createdAt: Date
    public var appVersion: String
    public var recipe: ProjectRecipe
    public var depthProvenance: DepthProvenance
    public var sourcePixelWidth: Int
    public var sourcePixelHeight: Int

    public static let currentVersion = 1

    public init(version: Int = ProjectSidecar.currentVersion,
                id: String,
                displayName: String,
                mode: SpaceMode,
                createdAt: Date,
                appVersion: String,
                recipe: ProjectRecipe,
                depthProvenance: DepthProvenance,
                sourcePixelWidth: Int,
                sourcePixelHeight: Int) {
        self.version = version
        self.id = id
        self.displayName = displayName
        self.mode = mode
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.recipe = recipe
        self.depthProvenance = depthProvenance
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
    }
}

/// One finished variation's sidecar, beside its picture.
public struct VariationSidecar: Sendable, Codable, Equatable {
    public var version: Int
    public var index: Int
    public var seed: UInt32
    public var createdAt: Date
    public var elapsedSeconds: TimeInterval
    public var stepsRun: Int
    /// Non-nil when the render was interrupted and picked up again. Provenance, not an error.
    public var resumedFromStep: Int?
    public var prompt: String
    public var presetID: String?

    public static let currentVersion = 1

    public init(version: Int = VariationSidecar.currentVersion,
                index: Int,
                seed: UInt32,
                createdAt: Date,
                elapsedSeconds: TimeInterval,
                stepsRun: Int,
                resumedFromStep: Int?,
                prompt: String,
                presetID: String?) {
        self.version = version
        self.index = index
        self.seed = seed
        self.createdAt = createdAt
        self.elapsedSeconds = elapsedSeconds
        self.stepsRun = stepsRun
        self.resumedFromStep = resumedFromStep
        self.prompt = prompt
        self.presetID = presetID
    }
}

/// A variation as the library sees it: the record, and whether its picture has actually arrived.
public struct VariationRecord: Sendable, Equatable, Identifiable {
    public let index: Int
    public let sidecar: VariationSidecar
    public let imageURL: URL
    /// False when the sidecar synced from another device but the PNG has not landed yet.
    public let imageIsPresent: Bool

    public var id: Int { index }

    public init(index: Int, sidecar: VariationSidecar, imageURL: URL, imageIsPresent: Bool) {
        self.index = index
        self.sidecar = sidecar
        self.imageURL = imageURL
        self.imageIsPresent = imageIsPresent
    }
}

/// A project, assembled from a folder.
public struct SpaceProject: Sendable, Equatable, Identifiable {
    public let folder: URL
    /// Nil for a "ghost space": the folder synced but `project.json` has not arrived yet.
    public let sidecar: ProjectSidecar?
    public let variations: [VariationRecord]
    public let sourceURL: URL
    public let depthURL: URL
    public let thumbnailURL: URL

    public var id: String { sidecar?.id ?? folder.lastPathComponent }

    public init(folder: URL,
                sidecar: ProjectSidecar?,
                variations: [VariationRecord],
                sourceURL: URL,
                depthURL: URL,
                thumbnailURL: URL) {
        self.folder = folder
        self.sidecar = sidecar
        self.variations = variations
        self.sourceURL = sourceURL
        self.depthURL = depthURL
        self.thumbnailURL = thumbnailURL
    }

    /// True while the sidecar has not arrived. The tile shows the folder's own name and offers to
    /// fetch, rather than pretending to be a finished project or showing a broken row.
    public var isGhost: Bool { sidecar == nil }

    /// What the library prints. A ghost falls back to the human part of the folder name, which is
    /// why the folder name carries the display name at all.
    public var displayName: String {
        sidecar?.displayName ?? ProjectFolderName.displayName(fromFolder: folder.lastPathComponent)
    }

    public var createdAt: Date {
        sidecar?.createdAt ?? ProjectFolderName.date(fromFolder: folder.lastPathComponent) ?? .distantPast
    }

    public var finishedCount: Int { variations.filter(\.imageIsPresent).count }
}
