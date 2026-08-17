import Testing
import Foundation
@testable import GenerationKit

/// ORACLES:
///  • INVARIANT — every generated size must be a multiple of 8. Stable-Diffusion-family VAEs
///    downsample by 8; a dimension that is not a multiple of 8 cannot be decoded at all. This is a
///    hard property of the architecture, not a preference.
///  • IDENTITY — the three shipped presets are DEFINED values and must round-trip exactly.
///  • INVARIANT — clamping preserves aspect ratio to within one latent cell.
/// MODEL CAVEAT: the pixel counts are the *requested* output size. A real pipeline may generate at
/// a smaller base resolution and upscale; that is the pipeline's business, not this type's.
@Suite("AspectRatio — latent-grid and clamping invariants")
struct AspectRatioTests {

    @Test("every preset is already on the latent grid")
    func presetsAreOnGrid() {
        for aspect in [AspectRatio.phone, .pad, .wide] {
            #expect(aspect.width % 8 == 0, "\(aspect.displayName) width \(aspect.width)")
            #expect(aspect.height % 8 == 0, "\(aspect.displayName) height \(aspect.height)")
        }
    }

    @Test("the presets are the sizes the design bundle names")
    func presetValues() {
        #expect(AspectRatio.phone == AspectRatio(width: 1206, height: 2622))
        #expect(AspectRatio.pad == AspectRatio(width: 2048, height: 1536))
        #expect(AspectRatio.wide == AspectRatio(width: 3840, height: 2160))
        #expect(AspectRatio.phone.isPortrait)
        #expect(!AspectRatio.pad.isPortrait)
    }

    @Test("an off-grid request is snapped, never rejected")
    func offGridSnaps() {
        let a = AspectRatio(width: 1207, height: 2623)
        #expect(a.width % 8 == 0)
        #expect(a.height % 8 == 0)
        #expect(abs(a.width - 1207) <= 4)
        #expect(abs(a.height - 2623) <= 4)
    }

    @Test("absurd requests clamp instead of trapping")
    func clamping() {
        let huge = AspectRatio(width: 100_000, height: 100_000)
        #expect(huge.width == AspectRatio.maximumEdge)
        #expect(huge.height == AspectRatio.maximumEdge)

        let tiny = AspectRatio(width: 1, height: 1)
        #expect(tiny.width == AspectRatio.minimumEdge)
        #expect(tiny.height == AspectRatio.minimumEdge)

        let negative = AspectRatio(width: -400, height: -400)
        #expect(negative.width == AspectRatio.minimumEdge)
    }

    @Test("a display smaller than the cap is used at its own size")
    func displayUnderCap() {
        let a = AspectRatio.fittingDisplay(width: 3456, height: 2234)
        #expect(a.width == 3456)          // already a multiple of 8
        #expect(a.height == 2232)         // 2234 snaps down to the grid
    }

    @Test("a display over the cap scales down and keeps its shape")
    func displayOverCap() {
        // Pro Display XDR, 6016 × 3384.
        let a = AspectRatio.fittingDisplay(width: 6016, height: 3384)
        #expect(max(a.width, a.height) == AspectRatio.maximumEdge)
        let requested = 6016.0 / 3384.0
        #expect(abs(a.ratio - requested) < 0.01, "got \(a.ratio), wanted \(requested)")
    }

    @Test("a portrait display is not silently turned landscape")
    func portraitDisplay() {
        let a = AspectRatio.fittingDisplay(width: 2160, height: 3840)
        #expect(a.isPortrait)
    }

    @Test("it survives a JSON round trip, which is how it reaches the sidecar")
    func codableRoundTrip() throws {
        for original in AspectRatio.offered {
            let data = try JSONEncoder().encode(original)
            let back = try JSONDecoder().decode(AspectRatio.self, from: data)
            #expect(back == original)
        }
    }

    @Test("display names are the bundle's words, and an odd size names itself")
    func displayNames() {
        #expect(AspectRatio.pad.displayName == "iPad")
        #expect(AspectRatio.phone.displayName == "Phone")
        #expect(AspectRatio.wide.displayName == "Wide")
        #expect(AspectRatio(width: 1024, height: 1024).displayName == "1024 × 1024")
    }
}
