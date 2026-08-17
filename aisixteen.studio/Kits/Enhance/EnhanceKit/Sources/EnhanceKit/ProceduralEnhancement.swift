import Foundation
import CoreGraphics

/// What the mock does to a photo instead of running a model.
///
/// ⚠️ **This is not model output and must never be presented as it.** It is an unsharp mask, a
/// saturation lift and a gentle S-curve — a plausible *look* of "enhanced", so the comparison split,
/// the strength dial and the resolving veil can all be judged before any weights exist. Screenshots
/// or preview video taken against it would be a lie about what the app does; that is what the
/// `Mock` build configuration is fenced off for.
///
/// ### Why it honours `strength` when the brief says the mock may ignore it
///
/// The build prompt permits a mock that ignores strength. Ignoring it would make Whisper 15 and
/// Strong 80 produce byte-identical passes, and the four detents — the primary control in the whole
/// app — would be unjudgeable until the model landed. So the effect scales with strength. It is the
/// one place the mock does more than it was asked to, and it costs nothing.
///
/// ### Why it ignores `mask`
///
/// Because the *composite* localises the pass — `original + (mask × strength × pass)` is applied by
/// the renderer, from the recipe. A mock that also masked would apply the mask twice and the
/// subject edge would darken at every re-render.
enum ProceduralEnhancement {

    /// - Parameters:
    ///   - strength: 0–100, straight from the dial.
    ///   - progress: 0–1 through the schedule. Intermediates are rendered at a fraction of the
    ///     final effect, so the picture visibly resolves rather than popping.
    static func render(_ source: PixelImage, strength: Double, progress: Double) -> PixelImage {
        let amount = effectAmount(strength: strength) * min(max(progress, 0), 1)
        guard amount > 0 else { return source }

        var output = source
        let width = source.width
        let height = source.height

        source.pixels.withUnsafeBufferPointer { input in
            output.pixels.withUnsafeMutableBufferPointer { result in
                for y in 0..<height {
                    for x in 0..<width {
                        let here = (y * width + x) * PixelImage.bytesPerPixel

                        // 3×3 box blur, for the unsharp mask's low-frequency half. Edges clamp
                        // rather than wrap: a wrapped edge puts the opposite side of the photo into
                        // the halo, which is visible as a bright rim on a dark border.
                        var blur = (r: 0, g: 0, b: 0)
                        for dy in -1...1 {
                            let sy = min(max(y + dy, 0), height - 1)
                            for dx in -1...1 {
                                let sx = min(max(x + dx, 0), width - 1)
                                let index = (sy * width + sx) * PixelImage.bytesPerPixel
                                blur.r += Int(input[index])
                                blur.g += Int(input[index + 1])
                                blur.b += Int(input[index + 2])
                            }
                        }

                        let original = (r: Double(input[here]),
                                        g: Double(input[here + 1]),
                                        b: Double(input[here + 2]))
                        let blurred = (r: Double(blur.r) / 9,
                                       g: Double(blur.g) / 9,
                                       b: Double(blur.b) / 9)

                        // 1. Unsharp: push the detail that the blur removed back in, amplified.
                        var r = original.r + (original.r - blurred.r) * amount * 1.4
                        var g = original.g + (original.g - blurred.g) * amount * 1.4
                        var b = original.b + (original.b - blurred.b) * amount * 1.4

                        // 2. Saturation, around Rec. 709 luma so skin does not go orange first.
                        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                        let saturation = 1 + 0.28 * amount
                        r = luma + (r - luma) * saturation
                        g = luma + (g - luma) * saturation
                        b = luma + (b - luma) * saturation

                        // 3. A gentle S-curve for contrast, blended in by `amount` so the shape of
                        //    the curve does not change as it strengthens — only how far it is
                        //    applied. Changing both at once makes the intermediate frames look like
                        //    a different photo rather than the same one resolving.
                        r = mix(r, contrastCurve(r), amount)
                        g = mix(g, contrastCurve(g), amount)
                        b = mix(b, contrastCurve(b), amount)

                        result[here] = clamp8(r)
                        result[here + 1] = clamp8(g)
                        result[here + 2] = clamp8(b)
                        result[here + 3] = input[here + 3]
                    }
                }
            }
        }

        return output
    }

    /// Maps the 0–100 dial onto how hard the look is applied.
    ///
    /// Deliberately not linear. Whisper has to stay believable as "pixel-faithful" and Strong has to
    /// read as a re-render, so the low end is compressed and the top end is not.
    static func effectAmount(strength: Double) -> Double {
        let normalised = min(max(strength, 0), 100) / 100
        return normalised * normalised * 0.9 + normalised * 0.1
    }

    @inline(__always)
    private static func contrastCurve(_ value: Double) -> Double {
        let n = value / 255
        return (n * n * (3 - 2 * n)) * 255      // smoothstep
    }

    @inline(__always)
    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    @inline(__always)
    private static func clamp8(_ value: Double) -> UInt8 {
        UInt8(min(max(value.rounded(), 0), 255))
    }
}
