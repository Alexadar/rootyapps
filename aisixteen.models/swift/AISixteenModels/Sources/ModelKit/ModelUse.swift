import Foundation

/// One model a job depended on, and the build of it.
///
/// ### Why a job records more than one
///
/// A wallpaper is made by a *pipeline*, not by a model. Stage 1 is the diffusion pipeline, stage 2
/// is an ESRGAN enlarger, stage 3 is the diffusion pipeline again with a Tile ControlNet. Those are
/// separate files, shipped separately, and they can be updated independently — a new upscaler pack
/// does not touch the diffusion pack.
///
/// The first version of this recorded a single model id and a single fingerprint, both taken from
/// the diffusion resources. That left a real hole: swap the ESRGAN model and every stored stage-2
/// tile becomes stale, while the manifest still says the job is resumable. The resumed enlargement
/// would then be half one network's output and half another's, blended across the overlap, with
/// nothing reporting a problem.
///
/// So a job records **every model it used**, and resuming requires all of them to still be present,
/// unchanged.
public struct ModelUse: Codable, Hashable, Sendable {

    /// **The subtask**, not the file.
    ///
    /// Keyed by stage rather than by "which model" so the three stages can diverge. Today stages 1
    /// and 3 happen to run the same pack, but they are different jobs asking for different things —
    /// composing a picture from noise, and adding texture to one that already exists. A future build
    /// could reasonably compose with SDXL and refine with the SD 1.5 Tile ControlNet, and a manifest
    /// keyed by model rather than by stage could not express that a job had used both.
    ///
    /// It also makes the resumability question exact: a job that was interrupted during stage 3 only
    /// depended on the models the stages it actually ran used.
    public enum Role: String, Codable, Hashable, Sendable, CaseIterable {
        /// Stage 1 — diffusion from noise.
        case generate
        /// Stage 2 — ESRGAN enlargement.
        case upscale
        /// Stage 3 — Tile ControlNet refinement.
        case refine
    }

    public var role: Role
    /// Which model served this stage — `"sd15cn"`, `"realesrgan4x"`. Stable across reconversions of
    /// the same model, because stored work compares it.
    public var id: String
    /// Which build of that model. See `ModelFingerprint`.
    public var fingerprint: String

    public init(role: Role, id: String, fingerprint: String) {
        self.role = role
        self.id = id
        self.fingerprint = fingerprint
    }
}

public extension Array where Element == ModelUse {

    /// Whether everything this job used is still installed, unchanged.
    ///
    /// Asymmetric on purpose: `installed` may contain **more** than the job used. A job that never
    /// upscaled does not become unresumable because an upscaler has since been added — it did not
    /// depend on one. What it may not survive is any model it *did* use being absent or different.
    func areAllStillInstalled(among installed: [ModelUse]) -> Bool {
        allSatisfy { used in installed.contains(used) }
    }

    /// Order-independent comparison, because the caller builds this list by walking directories and
    /// nothing guarantees the order twice running.
    func describesSameModels(as other: [ModelUse]) -> Bool {
        Set(self) == Set(other)
    }
}
