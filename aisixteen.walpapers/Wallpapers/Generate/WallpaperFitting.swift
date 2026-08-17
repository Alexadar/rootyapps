import Foundation
import CoreGraphics
import GenerationKit

/// Fits a generated master to a particular screen, at the moment it is used.
///
/// ### Why the crop is not done during generation
///
/// The pipeline produces a **master** — 512 × 768 diffused, then ESRGAN ×4 to 2048 × 3072 — and the
/// library stores that, uncropped. Cropping earlier would be irreversible and would compound:
///
/// * **Enhance (stage 3) runs on the master.** Tile-refining an already-cropped picture spends
///   minutes adding detail to a frame whose edges are gone, and can never restore them.
/// * **One wallpaper, several screens.** The same picture set on an iPhone, an iPad and a Mac wants
///   three different crops. A master plus a crop-at-use gives all three; a pre-cropped file gives
///   one and pretends the others are impossible.
/// * **Re-cropping is free; un-cropping is not.** Keeping the master costs disk. Discarding it costs
///   the picture.
///
/// So: generate large, keep everything, and take the crop at the last possible moment — when a
/// specific display has actually been named.
enum WallpaperFitting {

    /// Crops to `aspect` and, if the crop is smaller than the panel, enlarges it with ESRGAN
    /// before the final resample — so the wallpaper lands at native resolution rather than being
    /// stretched at the last step.
    ///
    /// ### Why the second pass earns its seconds
    ///
    /// A 2048² master crops to 945 × 2048 for a 1290 × 2796 panel: **46 % of the width survives**,
    /// and what is left is smaller than the screen. A plain resample to fill it is a 1.37×
    /// enlargement — undoing part of what stage 2 bought.
    ///
    /// Running the upscaler on the *cropped strip* instead costs about thirty tiles, a few seconds,
    /// and produces 3780 × 8192. Downscaling that to the panel is **supersampling**, which is
    /// sharper than either the crop or a naive upscale. It only runs when the crop is genuinely too
    /// small; a master that already exceeds the panel skips it.
    static func fitNatively(_ image: CGImage, to aspect: AspectRatio) -> CGImage? {
        guard let cropped = crop(image, to: aspect) else { return nil }
        guard cropped.width < aspect.width || cropped.height < aspect.height else {
            return scaled(cropped, to: aspect)
        }
        // **The upscale that used to be here is gone.** Enlarging a 945 × 2048 crop by four gives
        // 3780 × 8192, and the tiled accumulator holds three colour floats plus a weight per pixel
        // — about 500 MB for a single call. That is not slow, it is too big, and moving it off the
        // main actor only changed where it stalled. A plain downscale is slightly softer and Save
        // actually completes; the sharpness was speculative, the hang was measured.
        return scaled(cropped, to: aspect)
    }

    /// Crops `image` to `aspect`, filling it and trimming the overflow.
    ///
    /// Aspect-*fill*, never letterbox: a wallpaper with bars is not a wallpaper. The trim is taken
    /// evenly from both sides of the longer axis.
    static func fit(_ image: CGImage, to aspect: AspectRatio) -> CGImage? {
        guard let cropped = crop(image, to: aspect) else { return nil }
        // Only ever scaled DOWN here. `fitNatively` is the path that enlarges.
        guard cropped.width > aspect.width || cropped.height > aspect.height else { return cropped }
        return scaled(cropped, to: aspect)
    }

    private static func crop(_ image: CGImage, to aspect: AspectRatio) -> CGImage? {
        let sourceRatio = CGFloat(image.width) / CGFloat(image.height)
        let targetRatio = CGFloat(aspect.width) / CGFloat(aspect.height)

        var crop = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if sourceRatio > targetRatio {
            // Source is wider than wanted: trim left and right.
            let width = CGFloat(image.height) * targetRatio
            crop = CGRect(x: (CGFloat(image.width) - width) / 2, y: 0,
                          width: width, height: CGFloat(image.height))
        } else if sourceRatio < targetRatio {
            let height = CGFloat(image.width) / targetRatio
            crop = CGRect(x: 0, y: (CGFloat(image.height) - height) / 2,
                          width: CGFloat(image.width), height: height)
        }

        return image.cropping(to: crop.integral)
    }

    private static func scaled(_ image: CGImage, to aspect: AspectRatio) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: aspect.width, height: aspect.height,
                                      bitsPerComponent: 8, bytesPerRow: aspect.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: aspect.width, height: aspect.height))
        return context.makeImage()
    }

    /// The pixel size of the screen this wallpaper is being set on.
    ///
    /// Main-actor isolated because both `NSScreen` and `UIScreen` are: the screen is UI state, and
    /// reading it off the main actor is a data race Swift 6 is right to refuse.
    @MainActor
    static func currentScreenSize() -> AspectRatio {
        #if os(macOS)
        let pixels = MacWallpaperActions.frontmostDisplayPixels()
        return AspectRatio.fittingDisplay(width: pixels.width, height: pixels.height)
        #else
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return AspectRatio(width: Int(bounds.width * scale), height: Int(bounds.height * scale))
        #endif
    }
}

#if !os(macOS)
import UIKit
#endif
