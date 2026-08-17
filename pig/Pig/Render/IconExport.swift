import Foundation
import Metal

/// `PIG_ICON=<path> open -n -g Pig.app` renders the app icon and quits.
///
/// The icon is **a frame of this game**, produced by the same shader from the same `PigShape`, so it
/// cannot disagree with the animal the player fattens. It is deliberately not an illustration: every
/// tuning pass on the body would leave a hand-drawn icon a little more wrong, and nobody would notice
/// until the store listing sat beside a screenshot.
enum IconExport {

    /// Returns true if an icon was requested, in which case the app should exit rather than open a
    /// window.
    static func runIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PIG_ICON"] else { return false }
        let fat = env["PIG_ICON_FAT"].flatMap(Double.init) ?? 0.72
        let size = env["PIG_ICON_SIZE"].flatMap(Int.init) ?? 1024

        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = Renderer(device: device, colorPixelFormat: .rgba8Unorm,
                                      depthPixelFormat: .depth32Float, sampleCount: 1,
                                      config: .shipping) else {
            FileHandle.standardError.write(Data("pig: no Metal device for the icon pass\n".utf8))
            return true
        }

        var world = World(batch: 1, config: .shipping)
        world.fat = Tensor(shape: [1], data: [min(max(fat, 0), 1)])
        // One step so the derived state the renderer reads is the state a running game would hand it,
        // rather than the zeroes an uninitialised world starts with.
        Step.advance(&world, intent: .idle(batch: 1))

        var shot = world.snapshot()
        // No props in the icon: the drops and the dog are world-anchored, and the icon is the animal.
        shot.dropAlive = shot.dropAlive.map { _ in 0 }
        shot.dogActive = false

        // The app is sandboxed, so a path outside its container is simply not writable — the first
        // attempt at this wrote nothing and reported nothing, because `CGImageDestination` fails
        // silently on a denied URL. Fall back to the container's own tmp and print where it landed.
        var url = URL(fileURLWithPath: path)
        var ok = renderer.writeIcon(size: size, snapshot: shot, to: url)
        if !ok {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            ok = renderer.writeIcon(size: size, snapshot: shot, to: url)
        }
        FileHandle.standardError.write(
            Data("pig: icon \(ok ? "written" : "FAILED") → \(url.path)\n".utf8))
        return true
    }
}
