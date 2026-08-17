import Foundation
import CoreGraphics
import GenerationKit

/// Makes the mock's pictures.
///
/// **Why procedural rather than bundled photographs.** Three reasons that all matter to judging the
/// design now. The picture must *change with the prompt* — a fixed sample image makes the whole
/// Create flow read as a placeholder no matter how good the animation is, and the point of this run
/// is to judge that flow. It must be **deterministic**, so the same prompt and seed give the same
/// wallpaper on every launch and "regenerate from this prompt" means something. And it must render
/// at **any size**, because aspect ratio is a real input and a bundled 9:19.5 photograph cropped to
/// 16:9 would hide exactly the thing the Mac needs to show.
///
/// It also keeps the repository free of megabytes of licence-encumbered binaries.
///
/// This is not pretending to be diffusion. It is a seeded colour field: a base wash, a handful of
/// radial blooms whose positions and colours come from the prompt, and a noise layer that thins as
/// the run proceeds — which is what an emerging latent actually looks like from a distance.
enum ProceduralRenderer {

    /// Renders a frame of a generation.
    ///
    /// - Parameter progress: 0 at the first decoded latent, 1 at the last. Controls how much of the
    ///   composition has resolved and how much noise is left over it.
    /// - Returns: 8-bit RGBA, premultiplied, `width * height * 4` bytes.
    static func render(prompt: String, seed: UInt32, size: AspectRatio, progress: Double) -> Data? {
        let width = size.width, height = size.height
        let bytesPerRow = width * Bitmap.bytesPerPixel

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Prompt and seed together, so two wallpapers from the same words but different seeds are
        // genuinely different pictures — which is what the regenerate button promises.
        var rng = SeededRandomNumberGenerator(seed: stableHash(prompt) ^ UInt64(seed))
        let palette = Palette(rng: &rng)
        let clamped = min(max(progress, 0), 1)

        drawWash(in: context, size: CGSize(width: width, height: height), palette: palette)
        drawBlooms(in: context,
                   size: CGSize(width: width, height: height),
                   palette: palette,
                   progress: clamped,
                   rng: &rng)
        drawGrain(in: context,
                  width: width,
                  height: height,
                  amount: grainAmount(for: clamped),
                  rng: &rng)

        guard let data = context.data else { return nil }
        return Data(bytes: data, count: bytesPerRow * height)
    }

    /// Noise falls away as the picture resolves, but never quite to zero — a finished render with
    /// mathematically flat gradients looks synthetic in a way no generated image does.
    private static func grainAmount(for progress: Double) -> Double {
        0.03 + 0.30 * pow(1 - progress, 1.6)
    }

    // MARK: Palette

    /// Five related colours from one seeded hue.
    ///
    /// Picked as an analogous set with one complementary accent, rather than five independent random
    /// colours: random RGB triples reliably produce mud, and a wallpaper generator whose output is
    /// mud is not a useful thing to judge a design against.
    private struct Palette {
        let base: CGColor
        let blooms: [CGColor]

        init(rng: inout SeededRandomNumberGenerator) {
            let hue = Double.random(in: 0..<1, using: &rng)
            let saturation = Double.random(in: 0.35...0.75, using: &rng)
            let dark = Bool.random(using: &rng)
            let baseBrightness = dark ? Double.random(in: 0.08...0.22, using: &rng)
                                      : Double.random(in: 0.78...0.94, using: &rng)
            base = Self.color(h: hue, s: saturation * 0.5, b: baseBrightness)

            var colours: [CGColor] = []
            for index in 0..<5 {
                // Analogous drift, plus one deliberate jump to the opposite side of the wheel so
                // there is somewhere for the eye to go.
                let drift = index == 3 ? 0.5 : Double.random(in: -0.09...0.09, using: &rng)
                let h = (hue + drift).truncatingRemainder(dividingBy: 1)
                let b = dark ? Double.random(in: 0.35...0.85, using: &rng)
                             : Double.random(in: 0.30...0.75, using: &rng)
                colours.append(Self.color(h: h < 0 ? h + 1 : h,
                                          s: Double.random(in: 0.4...0.95, using: &rng) * saturation + 0.15,
                                          b: b))
            }
            blooms = colours
        }

        /// HSB → RGB. Written out rather than pulled from UIKit so this file stays platform-neutral.
        static func color(h: Double, s: Double, b: Double) -> CGColor {
            let saturation = min(max(s, 0), 1), brightness = min(max(b, 0), 1)
            let sector = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
            let index = Int(sector)
            let f = sector - Double(index)
            let p = brightness * (1 - saturation)
            let q = brightness * (1 - saturation * f)
            let t = brightness * (1 - saturation * (1 - f))
            let (r, g, bl): (Double, Double, Double)
            switch index % 6 {
            case 0: (r, g, bl) = (brightness, t, p)
            case 1: (r, g, bl) = (q, brightness, p)
            case 2: (r, g, bl) = (p, brightness, t)
            case 3: (r, g, bl) = (p, q, brightness)
            case 4: (r, g, bl) = (t, p, brightness)
            default: (r, g, bl) = (brightness, p, q)
            }
            return CGColor(srgbRed: r, green: g, blue: bl, alpha: 1)
        }
    }

    // MARK: Layers

    private static func drawWash(in context: CGContext, size: CGSize, palette: Palette) {
        context.setFillColor(palette.base)
        context.fill(CGRect(origin: .zero, size: size))
    }

    /// Soft radial blooms. Early in the run only the first one or two have arrived, so the picture
    /// genuinely resolves rather than fading in fully formed.
    private static func drawBlooms(in context: CGContext,
                                   size: CGSize,
                                   palette: Palette,
                                   progress: Double,
                                   rng: inout SeededRandomNumberGenerator) {
        let space = CGColorSpaceCreateDeviceRGB()
        let longest = max(size.width, size.height)
        // One bloom at the first preview, all five by the end.
        let resolved = max(1, Int((Double(palette.blooms.count) * (0.25 + 0.75 * progress)).rounded()))

        for (index, colour) in palette.blooms.enumerated() {
            let centre = CGPoint(x: Double.random(in: 0...size.width, using: &rng),
                                 y: Double.random(in: 0...size.height, using: &rng))
            let radius = longest * Double.random(in: 0.25...0.75, using: &rng)
            guard index < resolved else { continue }

            // The most recently arrived bloom is still faint — it is the one currently forming.
            let freshness = index == resolved - 1 ? 0.45 + 0.55 * progress : 1
            let peak = 0.85 * freshness

            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: [colour.copy(alpha: peak) ?? colour,
                                                     colour.copy(alpha: 0) ?? colour] as CFArray,
                                            locations: [0, 1])
            else { continue }

            context.saveGState()
            context.drawRadialGradient(gradient,
                                       startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius,
                                       options: [])
            context.restoreGState()
        }
    }

    /// A cloud of noise, generated small and scaled up with interpolation.
    ///
    /// Per-pixel noise at full resolution would be twelve million random draws per preview — slow,
    /// and visually wrong: it reads as sensor grain rather than as an unresolved image. Generating
    /// at an eighth scale and letting Core Graphics smooth it produces the soft, blotchy field that
    /// a partly-denoised latent actually looks like, and costs a sixty-fourth as much.
    private static func drawGrain(in context: CGContext,
                                  width: Int,
                                  height: Int,
                                  amount: Double,
                                  rng: inout SeededRandomNumberGenerator) {
        guard amount > 0.001 else { return }
        let smallWidth = max(2, width / 8)
        let smallHeight = max(2, height / 8)
        var pixels = [UInt8](repeating: 0, count: smallWidth * smallHeight * 4)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8(Double.random(in: 0...255, using: &rng))
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }

        let bytesPerRow = smallWidth * 4
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let noise = CGImage(width: smallWidth,
                                  height: smallHeight,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { return }

        context.saveGState()
        context.setAlpha(min(max(amount, 0), 1))
        context.setBlendMode(.overlay)
        context.interpolationQuality = .high
        context.draw(noise, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }
}
