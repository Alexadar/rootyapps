import Foundation

/// **Which model** — as opposed to which *build* of it.
///
/// Today the app ships one converted pipeline and could get away with assuming it. It will not stay
/// that way: the model arrives as a downloadable asset pack, an SDXL conversion is a plausible
/// second pack, and the moment there are two, every piece of stored work has to say which one made
/// it. A half-finished job resumed against a different model does not fail — it splices two
/// different pictures together and looks like the model being unreliable.
///
/// So identity is recorded, not inferred at use time, and it is a *value* rather than a `Bool` for
/// "is this the ControlNet one". The three things callers actually branch on — the native side,
/// whether there is a ControlNet, and whether the device can hold it — are properties of the model,
/// and scattering them as constants is how they drift apart from the files on disk.
///
/// ### One entry, deliberately
///
/// `known` lists exactly the models that have been converted and measured. An entry for a model that
/// does not exist yet would be guesses about its memory and its native size, written down in the one
/// place the app trusts — and the first real conversion would contradict them.
public struct ModelIdentity: Codable, Hashable, Sendable, Identifiable {

    /// The architecture. What actually differs between families is the latent size, the text
    /// encoders and the memory, so nothing here is cosmetic.
    public enum Family: String, Codable, Hashable, Sendable {
        case stableDiffusion15 = "sd15"
        case stableDiffusionXL = "sdxl"
    }

    /// Stable across conversions of the same model — `"sd15cn"`. This is what a job manifest stores
    /// and what a resume compares, so it must never be regenerated or prettified.
    public let id: String
    public let family: Family
    /// Shown to a person choosing a model. Not used for any comparison.
    public let displayName: String
    /// The side, in pixels, the converted graphs were built for. Core ML graphs are fixed-shape, so
    /// this is a hard property of the files and not a preference.
    public let nativeSide: Int
    /// Whether a Tile ControlNet ships alongside, which is what makes Enhance possible at all.
    public let hasControlNet: Bool
    /// Peak resident bytes for one loaded pipeline, **measured**, not estimated. 1.11 GB for
    /// `sd15cn` generating on the Neural Engine at 6-bit.
    public let approximateResidentBytes: Int
    /// Below this much physical memory the model is not offered. A device that cannot hold it does
    /// not fail politely — it reboots, which this project has done.
    public let minimumDeviceMemoryBytes: Int

    public init(id: String,
                family: Family,
                displayName: String,
                nativeSide: Int,
                hasControlNet: Bool,
                approximateResidentBytes: Int,
                minimumDeviceMemoryBytes: Int) {
        self.id = id
        self.family = family
        self.displayName = displayName
        self.nativeSide = nativeSide
        self.hasControlNet = hasControlNet
        self.approximateResidentBytes = approximateResidentBytes
        self.minimumDeviceMemoryBytes = minimumDeviceMemoryBytes
    }

    /// The house diffusion pack: an SD 1.5 checkpoint, 6-bit palettised, converted with
    /// `--unet-support-controlnet`, epi_noiseoffset fused at 0.7, shipping a Tile ControlNet.
    ///
    /// ### The id outlives the weights, on purpose
    ///
    /// `sd15cn` names the *pack and its role*, not one particular checkpoint. The base
    /// `stable-diffusion-v1-5` weights were replaced by an SD 1.5 fine-tune with the same
    /// architecture, and the id stayed — because renaming it would strand every paused job on every
    /// installed device, and nothing about how the app drives the pack changed.
    ///
    /// What stops a job made by the old weights resuming into the new ones is the **fingerprint**,
    /// not the id. That is exactly why a job records both: the id says *what role these weights
    /// play*, the fingerprint says *which build of them*, and reusing one while the other changes is
    /// the case the pair was designed for.
    ///
    /// The single unet serves both text-to-image and tile refine: ControlNet residuals are *added*
    /// to the skip connections, so feeding zeros reduces the controlled unet to a plain one, proven
    /// bit-identical. That is why `hasControlNet` does not imply a second unet.
    public static let sd15cn = ModelIdentity(
        id: "sd15cn",
        family: .stableDiffusion15,
        displayName: "Stable Diffusion 1.5 · Tile",
        nativeSide: 512,
        hasControlNet: true,
        // Measured on an iPhone 14 Pro Max: 1.11 GB generating, 776 MB refining with the ControlNet.
        // The larger of the two, because it is the one that has to fit.
        approximateResidentBytes: 1_192_000_000,
        // 6 GB. The 4 GB devices reboot under this load — measured, not assumed.
        minimumDeviceMemoryBytes: 6 * 1_024 * 1_024 * 1_024)

    /// Every model this build knows how to run. Grows when a conversion exists and has been
    /// measured, never in anticipation of one.
    public static let known: [ModelIdentity] = [.sd15cn]

    public static func known(id: String) -> ModelIdentity? {
        known.first { $0.id == id }
    }

    /// Whether this device has the memory to run it.
    ///
    /// The reason a model can be *identified* separately from being installed: when there is more
    /// than one pack to choose from, the choice has to be filtered by what the hardware can hold,
    /// and the honest place to decide that is against a measured number rather than a device-name
    /// allow-list that goes stale every September.
    public var fitsThisDevice: Bool {
        ProcessInfo.processInfo.physicalMemory >= UInt64(minimumDeviceMemoryBytes)
    }
}
