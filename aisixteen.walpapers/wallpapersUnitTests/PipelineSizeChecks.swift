import XCTest
import GenerationKit
@testable import Wallpapers

/// Every size the picture takes, from noise to the lock screen.
///
/// Written down as assertions because the pipeline has three resamples in it and the question "what
/// resolution is the wallpaper actually" has a different answer at each one. Getting it wrong is not
/// visible in code review — it is visible as a soft wallpaper months later.
///
///     stage 1   512 × 512      diffusion, the only size the converted graphs accept
///     stage 2   2048 × 2048    ESRGAN ×4 — this is the master, saved as-is
///     ─ enhance is a separate action on an existing master ─
///     stage 3   1024 × 1024    plain downscale in, nine ControlNet tiles, plain upscale out
///
/// **ESRGAN runs exactly once**, on the way up from 512. Enhance's round trip is ÷2 then ×2 with
/// ordinary resampling; a second ESRGAN pass there was tried and removed — 1024 → 4096 costs a
/// ~200 MB accumulator for detail the immediate downscale to 2048 throws away.
final class PipelineSizeChecks: XCTestCase {

    func testTheMasterIsFourTimesTheDiffusionSize() {
        XCTAssertEqual(Upscaler.scale, 4)
        XCTAssertEqual(ModelIdentity.sd15cn.nativeSide, 512)
        XCTAssertEqual(ModelIdentity.sd15cn.nativeSide * Upscaler.scale, 2048,
                       "the master is 2048² — one ESRGAN pass, no downscale after it")
    }

    func testEnhanceWorksAtHalfTheMasterAndPutsItBack() {
        // Nine tiles at 1024 rather than twenty-five at 2048: ninety seconds against four minutes,
        // and the downscale on the way in is supersampling, so the refiner sees a cleaner picture
        // than the master it came from.
        XCTAssertEqual(TileRefiner.workingSide, 1024)
        XCTAssertEqual(TileRefiner.workingSide * 2, ModelIdentity.sd15cn.nativeSide * Upscaler.scale)
        XCTAssertEqual(TileRefiner.grid(width: TileRefiner.workingSide,
                                        height: TileRefiner.workingSide).count, 9)
    }

    func testASquareMasterDoesNotFullyCoverAProPhonePanel() {
        // The honest cost of generating square. `AspectRatio.phone` is 1208 × 2624 — the 1206 × 2622
        // panel snapped up to the latent grid's multiple of 8 — and a 2048² master cropped to that
        // shape is 943 px wide, so setting it enlarges by ~1.28×.
        //
        // Recorded rather than hidden: it is the reason the master is 2048 and not 1024. At 1024 the
        // crop would be 471 px against a 1206 px panel, a 2.6× enlargement, which is not a wallpaper.
        let panel = AspectRatio.phone
        let master = ModelIdentity.sd15cn.nativeSide * Upscaler.scale
        let croppedWidth = Int((Double(master) * panel.ratio).rounded())

        XCTAssertEqual(croppedWidth, 943)
        XCTAssertLessThan(croppedWidth, panel.width, "a square master cannot fill a tall panel")
        XCTAssertEqual(Double(panel.width) / Double(croppedWidth), 1.28, accuracy: 0.01)

        // What the rejected smaller master would have cost, so the choice stays justified.
        let atHalf = Int((512.0 * 2 * panel.ratio).rounded())
        XCTAssertEqual(Double(panel.width) / Double(atHalf), 2.56, accuracy: 0.02)
    }

    func testTheUpscalerTilesTheMasterRatherThanRunningItWhole() {
        // An RRDBNet evaluated over a full wallpaper at 4× internally does not fit on a phone
        // alongside the diffusion models; the converted graph takes one fixed 256 px tile.
        XCTAssertEqual(Upscaler.tile, 256)
        XCTAssertEqual(Upscaler.grid(width: 512, height: 512).count, 9)
    }
}
