import Foundation
import CoreML
import CoreGraphics
@preconcurrency import DiffusionKit
import GenerationKit
import TaskKit

/// Stage 3 — ControlNet Tile refinement, run tile by tile over an already-upscaled wallpaper.
///
/// Stage 2 enlarges honestly but cannot *invent*: ESRGAN sharpens what the diffusion model put
/// there. This pass goes back over the enlarged picture at its own resolution and adds detail that
/// was never in the 512 original — bark, grain, the texture of rock — by running a short
/// image-to-image diffusion on each tile, with a Tile ControlNet holding each tile faithful to what
/// was already there.
///
/// ### Why tiles, and why 512
///
/// The converted models are fixed-shape at 512 × 512. Tiling is not a workaround for that — it is
/// what "tile" in ControlNet Tile means. A 2048 × 2048 master is sixteen 512 tiles, and memory
/// stays at one tile's cost no matter how large the wallpaper gets.
///
/// ### The cost, measured
///
/// ~15 s per tile warm on a Mac, so roughly four minutes for a 2048² master, and every step runs a
/// second network alongside the unet. That is why this is a deliberate *Enhance* action on a
/// picture the user already likes, not part of every generation.
struct TileRefiner {

    /// The shape both converted models were built for.
    static let tile = 512
    /// Overlap in pixels. Same reasoning as the upscaler: a tile cannot see past its own edge, so
    /// butted tiles seam visibly. Larger than ESRGAN's 16 because diffusion invents content, and
    /// invented content disagrees across a boundary far more than sharpening does.
    static let overlap = 64
    /// How much of each tile is re-diffused. 0.35 keeps the composition and adds texture; higher
    /// starts inventing objects that were not there and breaks tile-to-tile agreement.
    static let strength: Float = 0.35
    /// Nominal steps. At strength 0.35 only ~35 % actually run — img2img skips the early, noisiest
    /// part of the schedule.
    static let steps = 12

    /// The side length the refinement actually runs at.
    ///
    /// A 2048² master is twenty-five tiles and roughly four minutes; halving it to 1024 is **nine**
    /// and about ninety seconds — and four minutes of foreground-only work is a different product
    /// from one. Downscaling an ESRGAN upscale is also supersampling, so the input to the refiner is
    /// cleaner than the 2048 it came from.
    ///
    /// (Nine, not four: the stride is `tile - overlap` = 448, so a 1024 axis takes origins 0, 448
    /// and 512 — the last pulled back to keep the final tile full. See `TileGridChecks`.)
    ///
    /// The cost is honest: detail invented at 1024 is enlarged afterwards, so it is a touch softer
    /// than refining at full size. At wallpaper viewing distance that trade looks right, but it is
    /// a trade.
    static let workingSide = 1024

    private let resourcesURL: URL
    private let stepCount: Int
    private let refineStrength: Float
    private let negativePrompt: String
    private let reduceMemory: Bool

    init(resourcesURL: URL,
         steps: Int = TileRefiner.steps,
         strength: Float = TileRefiner.strength,
         negativePrompt: String = "",
         reduceMemory: Bool = TileRefiner.reduceMemoryByDefault) {
        self.resourcesURL = resourcesURL
        self.stepCount = steps
        self.refineStrength = strength
        self.negativePrompt = negativePrompt
        self.reduceMemory = reduceMemory
    }

    /// See the note on the refine loop. Measured, not assumed.
    static let reduceMemoryByDefault = true

    static func isAvailable(at resourcesURL: URL) -> Bool {
        let controlNet = resourcesURL.appending(path: "controlnet")
        let encoder = resourcesURL.appending(path: "VAEEncoder.mlmodelc")
        return FileManager.default.fileExists(atPath: encoder.path)
            && ((try? FileManager.default.contentsOfDirectory(atPath: controlNet.path))?.isEmpty == false)
    }

    /// The ControlNet's name as the pipeline expects it: the compiled model's filename, no extension.
    private func controlNetName() throws -> String {
        let directory = resourcesURL.appending(path: "controlnet")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".mlmodelc") }
            .map { ($0 as NSString).deletingPathExtension }
        guard let first = names.first else { throw GenerationError.failed(reason: "No tile model is installed.") }
        return first
    }

    /// Refines `image` in place, tile by tile.
    ///
    /// - Parameter progress: `(completedTiles, totalTiles)` so the UI can keep counting rather than
    ///   freezing for four minutes.
    /// - Parameter isCancelled: checked between tiles. A four-minute job that cannot be stopped is
    ///   not a feature, and cancelling mid-tile would leave a half-refined picture.
    /// - Parameter tiles: where finished tiles are kept, so an interrupted refinement resumes rather
    ///   than starting over. Optional only because the refiner is also used in tests and previews;
    ///   in the app it is always present.
    func refine(_ image: CGImage,
                prompt: String,
                seed: UInt32,
                tiles: JobStore.TileSet? = nil,
                preview: @escaping @Sendable (CGImage?) -> Void = { _ in },
                progress: @escaping @Sendable (Int, Int) -> Void,
                isCancelled: @escaping @Sendable () -> Bool) throws -> CGImage {

        let width = image.width, height = image.height
        let grid = Self.grid(width: width, height: height)
        let total = grid.count

        try tiles?.prepare()
        let alreadyDone = tiles?.completed() ?? []
        let outstanding = TileLedger.remaining(total: total, completed: alreadyDone)

        // Loaded on first use, not up front. A refinement resumed with one tile left must not pay
        // 776 MB and several seconds to load a pipeline it will use once — and one resumed with
        // *no* tiles left must not load it at all.
        var pipeline: StableDiffusionPipeline?
        defer { pipeline?.unloadResources() }
        func loadedPipeline() throws -> StableDiffusionPipeline {
            if let pipeline { return pipeline }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            var loaded = try StableDiffusionPipeline(resourcesAt: resourcesURL,
                                                     controlNet: [try controlNetName()],
                                                     configuration: configuration,
                                                     disableSafety: true,
                                                     reduceMemory: reduceMemory)
            // The whole point of holding one pipeline across the tile loop. Without this the unet
            // and the ControlNet are torn down and re-read from disk after every single tile —
            // measured at 372 s against 47 s for the same nine tiles, at essentially the same peak.
            // That churn is what put sustained memory pressure on the phone.
            loaded.retainsDenoisingModels = true
            try loaded.loadResources()
            pipeline = loaded
            return loaded
        }

        var canvas = [Float](repeating: 0, count: width * height * 3)
        var weights = [Float](repeating: 0, count: width * height)
        let ramp = Self.feather(size: Self.tile, overlap: Self.overlap)
        // Read once. Every partial composite falls back to these pixels wherever no tile has landed.
        let base = Self.rgba(of: image, width: width, height: height)

        var done = 0
        progress(TileLedger.progress(total: total, completed: alreadyDone).done, total)

        for (index, origin) in grid.enumerated() {
          // A tile produces a CGImage, a PNG, a pixel buffer and everything Core ML autoreleases
          // along the way. Without a pool per tile they all live until this function returns, which
          // for nine tiles is minutes of accumulation on a device that reboots when the system runs
          // short of memory.
          try autoreleasepool {
            if isCancelled() { throw GenerationError.cancelled }

            // Accumulation is a weighted sum, so replaying stored tiles in grid order reconstructs
            // exactly the canvas the interrupted run had. Order does not matter; presence does.
            if outstanding.contains(index) == false, let restored = tiles?.load(index) {
                Self.accumulate(restored, into: &canvas, weights: &weights,
                                at: origin, canvas: (width, height), ramp: ramp)
                done += 1
                return
            }

            guard let patch = image.cropping(to: CGRect(x: origin.x, y: origin.y,
                                                        width: Self.tile, height: Self.tile))
            else { return }

            var configuration = StableDiffusionPipeline.Configuration(prompt: prompt)
            configuration.startingImage = patch
            configuration.strength = refineStrength
            configuration.stepCount = stepCount
            // The same seed for every tile. Different seeds per tile make neighbouring tiles
            // invent incompatible detail, and the overlap cannot blend away a disagreement
            // about what the picture contains.
            configuration.seed = seed
            configuration.guidanceScale = 5.0
            configuration.negativePrompt = negativePrompt
            configuration.disableSafety = true
            configuration.schedulerType = .dpmSolverMultistepScheduler
            // The tile conditions on itself: that is the whole idea of Tile ControlNet — keep
            // this square looking like what it already is, only sharper.
            configuration.controlNetInputs = [patch]

            let produced = try loadedPipeline().generateImages(configuration: configuration) { _ in
                !isCancelled()
            }
            guard let refined = produced.compactMap({ $0 }).first else {
                throw GenerationError.cancelled
            }

            // Written before it is accumulated: a crash between the two costs a re-render, whereas
            // accumulating first and crashing before the write loses the tile silently.
            try tiles?.store(refined, at: index)

            Self.accumulate(refined, into: &canvas, weights: &weights,
                            at: origin, canvas: (width, height), ramp: ramp)
            done += 1
            // Composed and handed over now, not at the end. This is what makes the minute legible:
            // detail arrives where it lands, tile by tile, instead of the picture changing once.
            preview(try? Self.compose(canvas: canvas, weights: weights, base: base,
                                      width: width, height: height))
            progress(done, total)
          }
        }

        // Let go of ~870 MB **before** composing. `resolve` allocates the full-size output twice
        // over, and paying that on top of a resident unet is the difference between finishing and
        // being killed. The `defer` above would only run after the composition.
        pipeline?.unloadResources()
        pipeline = nil

        return try Self.compose(canvas: canvas, weights: weights, base: base,
                                width: width, height: height)
    }

    /// The image's pixels, RGBA, row-major.
    private static func rgba(of image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return pixels }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// Square resample. Used both to bring a master down to the working size and to put the
    /// refined result back.
    static func resized(_ image: CGImage, to side: Int) -> CGImage? {
        guard side > 0, image.width != side || image.height != side else { return image }
        let height = Int((Double(side) / Double(image.width) * Double(image.height)).rounded())
        guard let context = CGContext(data: nil, width: side, height: max(height, 1),
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: max(height, 1)))
        return context.makeImage()
    }

    // MARK: -

    /// Every tile origin, in working order — left to right, top to bottom.
    ///
    /// Flat rather than two nested loops because the index into this list *is* the tile's identity
    /// on disk. It is also what goes into the job manifest, so a later change to the tiling maths
    /// cannot silently reinterpret a half-finished job against a different grid.
    static func grid(width: Int, height: Int) -> [(x: Int, y: Int)] {
        let step = tile - overlap
        let xs = origins(span: width, tile: tile, step: step)
        let ys = origins(span: height, tile: tile, step: step)
        return ys.flatMap { y in xs.map { (x: $0, y: y) } }
    }

    /// Tile origins that always yield a full tile — the last one is pulled back to the edge rather
    /// than running off it, because the models accept exactly one input size.
    static func origins(span: Int, tile: Int, step: Int) -> [Int] {
        guard span > tile else { return [0] }
        var result: [Int] = []
        var position = 0
        while position + tile < span {
            result.append(position)
            position += step
        }
        result.append(span - tile)
        return result
    }

    private static func feather(size: Int, overlap: Int) -> [Float] {
        var line = [Float](repeating: 1, count: size)
        for i in 0..<min(overlap, size / 2) {
            let v = Float(i) / Float(max(overlap - 1, 1))
            line[i] = v
            line[size - 1 - i] = v
        }
        var plane = [Float](repeating: 0, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                plane[row * size + column] = line[row] * line[column]
            }
        }
        return plane
    }

    private static func accumulate(_ tile: CGImage,
                                   into canvas: inout [Float],
                                   weights: inout [Float],
                                   at origin: (x: Int, y: Int),
                                   canvas size: (width: Int, height: Int),
                                   ramp: [Float]) {
        let w = tile.width, h = tile.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.draw(tile, in: CGRect(x: 0, y: 0, width: w, height: h))

        for row in 0..<h {
            let canvasRow = origin.y + row
            guard canvasRow < size.height else { break }
            for column in 0..<w {
                let canvasColumn = origin.x + column
                guard canvasColumn < size.width else { break }
                let weight = ramp[row * w + column]
                guard weight > 0 else { continue }
                let source = (row * w + column) * 4
                let target = (canvasRow * size.width + canvasColumn) * 3
                canvas[target]     += Float(pixels[source]) * weight
                canvas[target + 1] += Float(pixels[source + 1]) * weight
                canvas[target + 2] += Float(pixels[source + 2]) * weight
                weights[canvasRow * size.width + canvasColumn] += weight
            }
        }
    }

    /// Composes what has been refined so far **over the picture that was already there**.
    ///
    /// The refinement used to compose exactly once, after the last tile, so for the whole minute the
    /// user watched an unchanged picture with a veil clearing over it — the veil revealed the *old*
    /// pixels, which reads as nothing happening at all. Every tile is already VAE-decoded by the
    /// time it lands here, so publishing after each one costs a composite and nothing else.
    ///
    /// Pixels no tile has touched yet fall back to `base`. Without that they would divide by a
    /// near-zero weight and come out black, so an early preview would be one bright square on a
    /// dark field rather than a picture gaining detail.
    private static func compose(canvas: [Float], weights: [Float], base: [UInt8],
                                width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let weight = weights[index]
            guard weight > 1e-6 else {
                // Untouched: keep what the picture already showed.
                pixels[index * 4]     = base[index * 4]
                pixels[index * 4 + 1] = base[index * 4 + 1]
                pixels[index * 4 + 2] = base[index * 4 + 2]
                continue
            }
            pixels[index * 4]     = UInt8(min(max(canvas[index * 3] / weight, 0), 255))
            pixels[index * 4 + 1] = UInt8(min(max(canvas[index * 3 + 1] / weight, 0), 255))
            pixels[index * 4 + 2] = UInt8(min(max(canvas[index * 3 + 2] / weight, 0), 255))
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { throw GenerationError.failed(reason: "The refined picture couldn't be assembled.") }
        return image
    }
}
