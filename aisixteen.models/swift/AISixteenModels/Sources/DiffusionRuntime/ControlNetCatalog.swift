import Foundation
import ModelKit

/// Which ControlNets a pack actually carries.
///
/// The `sd15cn` pack is one set of weights shared by every app here; what differs is which
/// ControlNets ship beside it. Wallpapers and Studio need Tile. Architecture needs MLSD and Depth
/// and specifically **does not** want Tile, which would hold a redesign to the room it is meant to
/// change.
///
/// Discovered from the directory rather than hard-coded, because the pack is built by a script in
/// another repository and an app cannot know what a future one contains. A name that is not there is
/// a feature that must not be offered — an app that shows a button it cannot honour is worse than
/// one that shows nothing.
public enum ControlNetCatalog {

    /// The nets this project knows how to drive, and what each one is conditioned on.
    public enum Kind: String, CaseIterable, Sendable {
        /// Conditions on the tile itself: keep this square as it is, only sharper. Adding invented
        /// detail at full resolution.
        case tile
        /// Conditions on straight line segments. Holds architectural geometry — walls, windows,
        /// ceilings — while everything else changes.
        case mlsd
        /// Conditions on a depth map. Holds the *shape* of a space while its surfaces change.
        case depth

        /// The substring that identifies it in a compiled model's filename. Apple's converter
        /// camel-cases the HuggingFace repo id, so `control_v11p_sd15_mlsd` becomes
        /// `LllyasvielControlV11PSd15Mlsd`.
        var marker: String {
            switch self {
            case .tile: return "tile"
            case .mlsd: return "mlsd"
            case .depth: return "depth"
            }
        }

        /// What a person is told this does.
        public var displayName: String {
            switch self {
            case .tile: return "Detail"
            case .mlsd: return "Lines"
            case .depth: return "Depth"
            }
        }

        /// Whether it needs a conditioning image computed from the source, rather than the source.
        ///
        /// Tile does not — the tile conditions on itself. MLSD and Depth do, and where that image
        /// comes from is the app's problem: a LiDAR capture, a converted estimator, an edge
        /// detector. The pass will not invent it.
        public var needsConditioningImage: Bool { self != .tile }
    }

    /// Every ControlNet in the pack, as `(kind, name)`. The name is the compiled model's filename
    /// without its extension, which is exactly what `StableDiffusionPipeline(controlNet:)` expects.
    public static func installed(at resourcesURL: URL) -> [(kind: Kind, name: String)] {
        let directory = resourcesURL.appendingPathComponent("controlnet")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".mlmodelc") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
        return names.compactMap { name in
            let lowered = name.lowercased()
            guard let kind = Kind.allCases.first(where: { lowered.contains($0.marker) }) else {
                return nil
            }
            return (kind, name)
        }
    }

    /// The compiled name for one kind, or `nil` when this pack does not carry it.
    public static func name(of kind: Kind, at resourcesURL: URL) -> String? {
        installed(at: resourcesURL).first { $0.kind == kind }?.name
    }

    public static func has(_ kind: Kind, at resourcesURL: URL) -> Bool {
        name(of: kind, at: resourcesURL) != nil
    }
}
