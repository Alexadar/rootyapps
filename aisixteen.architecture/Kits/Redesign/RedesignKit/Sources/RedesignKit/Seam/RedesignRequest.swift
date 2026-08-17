import Foundation

/// Whether the user photographed the inside or the outside. Chosen at capture, because it changes
/// both the coach copy and the preset set — it is not a filter applied afterwards.
public enum SpaceMode: String, Sendable, Codable, CaseIterable, Hashable {
    case interior
    case exterior
}

/// A pointer to an image on disk, inside the project's folder.
///
/// The design handoff's `RedesignRequest` carried `sourcePhoto: CGImage`. A handle instead, for
/// two reasons that both matter: the request becomes `Codable`, so a queued job survives the app
/// being killed and can be rehydrated at launch; and a 12 MP photo is not copied into memory once
/// per queued variation.
public struct ImageHandle: Hashable, Sendable, Codable {
    public let url: URL
    public let size: PixelSize

    public init(url: URL, size: PixelSize) {
        self.url = url
        self.size = size
    }
}

/// One conditioning input for a ControlNet.
///
/// Depth is the only kind this build produces, but it is deliberately not modelled as "the depth
/// map". `../aisixteen.models/scripts/convert_sd15_coreml.py` already converts the unet with
/// `--unet-support-controlnet` and converts the VAE *encoder* alongside it, precisely so that
/// flows conditioned on a user-supplied picture work. Architecture is the domain where the other
/// control maps matter most — straight lines and surface normals are what keep a building looking
/// like a building — so the general shape is modelled now and one case is shipped.
public struct ControlSignal: Sendable, Equatable, Codable, Hashable {
    public let kind: ControlKind
    public let image: ImageHandle
    public let provenance: DepthProvenance
    /// ControlNet conditioning scale. 1.0 means "follow the control map"; lower lets the model
    /// drift from the geometry, which is exactly what this app promises not to do.
    public let weight: Double

    public init(kind: ControlKind,
                image: ImageHandle,
                provenance: DepthProvenance,
                weight: Double = 1.0) {
        self.kind = kind
        self.image = image
        self.provenance = provenance
        self.weight = weight
    }
}

/// Everything the generator needs, and nothing it does not.
///
/// Notably absent: variation *count*. Variations are a caller-side loop — the queue enqueues N
/// requests that differ only by `variationIndex` and `seed`. A generator that knew about siblings
/// would have to know about cancellation scope too, and that is the queue's job.
public struct RedesignRequest: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let projectID: String
    /// 1-based. Renders as "Variation 2" in the queue strip and the Live Activity.
    public let variationIndex: Int
    public let variationCount: Int
    public let source: ImageHandle
    public let controls: [ControlSignal]
    public let mode: SpaceMode
    public let prompt: String
    public let presetID: String?
    /// NOT optional, and rolled at enqueue rather than inside the generator.
    ///
    /// A generator that picks its own seed lazily cannot be resumed from a checkpoint and cannot
    /// be restarted deterministically when a checkpoint is rejected — both of which this app
    /// does. The seed is also part of what the library stores, so the user can regenerate.
    public let seed: UInt32
    public let plan: RedesignPlan
    /// Display-only, for the Live Activity and the completion notification.
    public let spaceName: String
    public let styleName: String

    public init(id: String,
                projectID: String,
                variationIndex: Int,
                variationCount: Int,
                source: ImageHandle,
                controls: [ControlSignal],
                mode: SpaceMode,
                prompt: String,
                presetID: String?,
                seed: UInt32,
                plan: RedesignPlan = .standard,
                spaceName: String,
                styleName: String) {
        self.id = id
        self.projectID = projectID
        self.variationIndex = variationIndex
        self.variationCount = variationCount
        self.source = source
        self.controls = controls
        self.mode = mode
        self.prompt = prompt
        self.presetID = presetID
        self.seed = seed
        self.plan = plan
        self.spaceName = spaceName
        self.styleName = styleName
    }

    public var variationLabel: String { "Variation \(variationIndex)" }

    /// The depth control, if there is one. Convenience for the badge and for the app's checks —
    /// `controls` is the truth.
    public var depth: ControlSignal? { controls.first { $0.kind == .depth } }

    /// A stable digest of everything that determines the output.
    ///
    /// Used for exactly one decision: a checkpoint whose digest differs is a checkpoint for a
    /// different render and must be discarded rather than resumed. Display names are excluded —
    /// renaming a space must not throw away a render that is twenty steps in.
    public var digest: String {
        var parts: [String] = [
            projectID,
            String(variationIndex),
            source.url.lastPathComponent,
            "\(source.size.width)x\(source.size.height)",
            mode.rawValue,
            prompt,
            presetID ?? "-",
            String(seed),
            String(plan.totalSteps),
        ]
        for control in controls.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            parts.append("\(control.kind.rawValue):\(control.image.url.lastPathComponent):\(control.weight)")
        }
        return Self.digest(of: parts.joined(separator: "|"))
    }

    /// FNV-1a, 64-bit, rendered as hex.
    ///
    /// Not CryptoKit: this package is Foundation-only on purpose, and the digest is a
    /// same-render-or-not check against a local file the app itself wrote thirty seconds ago —
    /// not a security boundary. Collision here would resume a checkpoint from a different render,
    /// which the step/kind checks would then also have to pass; 64 bits is far more than enough.
    static func digest(of string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(string.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
