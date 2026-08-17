import Foundation
import simd

/// Everything the renderer is allowed to know, and the only thing that crosses the boundary.
///
/// One way: the simulation produces a Snapshot, the renderer consumes it. Nothing here ever flows
/// back. That is what makes it safe for the renderer to add jitter, shimmer and chaos — none of it
/// can reach state, so none of it can break determinism.
///
/// Values are in geometrized units (G = c = M = 1), matching RelativityKit exactly.
struct Snapshot {
    var camera = Camera()
    var relativity = Renderer.RelativityUniforms()
    var bodies: [Body] = []
    /// True when this scene must integrate geodesics per pixel rather than offset a lookup.
    /// Set from `Demo.isWorldSpace`, so the label in the readout and the pipeline in use cannot
    /// disagree.
    var usesGeodesicPass = false
    /// Coordinate time, for display only. The simulation itself advances on an integer `Tick`.
    var coordinateTime: Double = 0
    /// Per-body proper time, which is the mechanic: two workers at different depths genuinely
    /// diverge in age, and this is where that becomes visible.
    var properTimes: [Double] = []
    /// Where the virtual camera sits for the through-portal pass. Computed on the CPU from the
    /// PortalKit transform, so the renderer never derives geometry — it only looks from where it
    /// is told to look.
    var portalVirtualCamera: Camera?
    var hasPortals: Bool { bodies.contains { $0.kind == .portal } }

    struct Camera {
        var eye = SIMD3<Float>(0, 2.5, 14)
        var target = SIMD3<Float>(0, 0, 0)
        var fovRadians: Float = 1.05
    }

    struct Body {
        enum Kind { case cosmonaut, cat, marker, portal }
        var kind: Kind
        var position: SIMD3<Float>
        var scale: Float = 1
        var yaw: Float = 0
        var color: SIMD3<Float> = Palette.amber
        var emissive: Float = 0
    }
}
