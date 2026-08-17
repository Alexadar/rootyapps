import Foundation
import CoreML
import CoreGraphics
import Accelerate
import GenerationKit
import TaskKit

/// Stage 2 — ESRGAN super-resolution, applied tile by tile.
///
/// The diffusion model produces 512 × 896. A wallpaper needs several times that, and asking the
/// diffusion model for it directly is not an option: Core ML graphs are fixed-shape, and SD 1.5
/// duplicates horizons and repeats detail well before it reaches wallpaper resolution. So the
/// picture is composed at the size the model is good at and enlarged by a network built for exactly
/// that job — 34 MB and one convolutional pass, against ~650 MB and twenty diffusion steps for the
/// alternative.
///
/// ### Why tiling, and why it is not optional
///
/// The converted model takes one fixed 256 px tile. That is deliberate: an RRDBNet evaluated over a
/// full wallpaper at 4× internally would not fit in a phone's memory alongside the diffusion models.
/// Tiling keeps peak memory at one tile regardless of output size.
///
/// Two details separate this from looking obviously tiled, and both were established by the Python
/// reference (`aisixteen.models/scripts/test_upscaler.py`):
///
/// * **Overlap.** ESRGAN's receptive field spans tens of pixels, so a tile cannot see past its own
///   edge. Butted edge to edge, the seams read as a grid.
/// * **Feathered blending.** Even overlapped, adjacent tiles disagree slightly in the shared region.
///   A linear cross-fade hides it; a hard cut is *more* visible than the seam it replaced.
final class Upscaler {

    /// Input tile size the model was converted for. Changing it requires reconverting.
    static let tile = 256
    /// Output is 4× the input.
    static let scale = 4
    /// Input pixels of overlap between neighbouring tiles. Carried in the model's metadata as
    /// `recommended_overlap`, because seam artefacts are a property of the network's receptive
    /// field rather than of this app.
    static let overlap = 16

    private let model: MLModel

    init(modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    static func bundledModelURL() -> URL? {
        Bundle.main.url(forResource: "RealESRGAN4x", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "UltraSharp4x", withExtension: "mlmodelc")
    }

    /// Which enlarger is installed, as a job records it.
    ///
    /// Taken from the compiled model's own filename rather than from a constant, because the two are
    /// interchangeable at build time — `bundledModelURL()` falls through from one to the other — and
    /// a hard-coded id would go on saying `realesrgan4x` after a swap. A job resumed against a
    /// different enlarger would blend two networks' tiles across the overlap and look like a seam
    /// artefact rather than a bug.
    static var installedID: String? {
        bundledModelURL()?.deletingPathExtension().lastPathComponent.lowercased()
    }

    /// Enlarges `image` by 4×.
    ///
    /// - Parameter progress: called with completed-tile counts so the UI can keep counting through
    ///   stage 2 rather than freezing on the last diffusion step.
    /// - Parameter tiles: where finished tiles are kept, so an interrupted enlargement resumes.
    ///   Optional, and the caller should weigh it: a tile is ~0.2 s of inference against ~1.5 MB
    ///   written, so this is worth much less here than in stage 3. It exists so that a *job*
    ///   interrupted anywhere resumes as one thing rather than partly.
    func upscale(_ image: CGImage,
                 tiles: JobStore.TileSet? = nil,
                 progress: (_ done: Int, _ total: Int) -> Void = { _, _ in }) throws -> CGImage {
        let inWidth = image.width, inHeight = image.height
        let outWidth = inWidth * Self.scale, outHeight = inHeight * Self.scale
        let grid = Self.grid(width: inWidth, height: inHeight)
        let total = grid.count

        try tiles?.prepare()
        let alreadyDone = tiles?.completed() ?? []
        let outstanding = TileLedger.remaining(total: total, completed: alreadyDone)

        // Colour and weight accumulate separately, then divide. That is what makes overlapping
        // tiles a cross-fade rather than last-one-wins.
        var colour = [Float](repeating: 0, count: outWidth * outHeight * 3)
        var weight = [Float](repeating: 0, count: outWidth * outHeight)
        let ramp = Self.feather(size: Self.tile * Self.scale, overlap: Self.overlap * Self.scale)

        var completed = 0
        progress(TileLedger.progress(total: total, completed: alreadyDone).done, total)

        for (index, origin) in grid.enumerated() {
          // Each tile makes a CVPixelBuffer, a CGImage and — when the job is stored — a PNG, all
          // autoreleased by frameworks. Sixteen tiles of a 2048² enlargement without a pool is tens
          // of megabytes held for no reason.
          try autoreleasepool {
            let target = (origin.x * Self.scale, origin.y * Self.scale)

            // A weighted sum, so replaying stored tiles rebuilds exactly the canvas the interrupted
            // run had.
            if outstanding.contains(index) == false, let restored = tiles?.load(index) {
                Self.accumulate(restored, into: &colour, weight: &weight,
                                at: target, canvas: (outWidth, outHeight), ramp: ramp)
                completed += 1
                return
            }

            guard let patch = image.cropping(to: CGRect(x: origin.x, y: origin.y,
                                                        width: min(Self.tile, inWidth - origin.x),
                                                        height: min(Self.tile, inHeight - origin.y))),
                  let squared = Self.padded(patch, to: Self.tile),
                  let buffer = Self.pixelBuffer(from: squared, side: Self.tile)
            else { return }

            let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
            let output = try model.prediction(from: input)
            guard let produced = output.featureValue(for: "upscaled")?.imageBufferValue,
                  let enlarged = Self.image(from: produced) else { return }

            try tiles?.store(enlarged, at: index)

            Self.accumulate(enlarged, into: &colour, weight: &weight,
                            at: target, canvas: (outWidth, outHeight), ramp: ramp)

            completed += 1
            progress(completed, total)
          }
        }

        return try Self.resolve(colour: colour, weight: weight, width: outWidth, height: outHeight)
    }

    /// Every tile origin, in working order. The index into this list is the tile's identity on disk,
    /// so it is built once and never recomputed differently between a run and its resumption.
    ///
    /// Origins are clamped so the last row and column are still full tiles: the model has exactly
    /// one input shape and cannot be handed a partial one.
    static func grid(width: Int, height: Int) -> [(x: Int, y: Int)] {
        let step = tile - overlap
        func origins(span: Int) -> [Int] {
            let starts = stride(from: 0, to: max(span - overlap, 1), by: step).map { $0 }
            // Distinct, because clamping can map the last two starts onto the same origin — which
            // would otherwise mean two tile indices for one square, and a resumed run silently
            // short of a tile.
            var seen = Set<Int>()
            return starts.map { min($0, max(span - tile, 0)) }.filter { seen.insert($0).inserted }
        }
        let xs = origins(span: width), ys = origins(span: height)
        return ys.flatMap { y in xs.map { (x: $0, y: y) } }
    }

    // MARK: -

    /// 1 through the middle, ramping to 0 across the overlap at each edge.
    private static func feather(size: Int, overlap: Int) -> [Float] {
        var line = [Float](repeating: 1, count: size)
        if overlap > 0 {
            for i in 0..<overlap {
                let v = Float(i) / Float(max(overlap - 1, 1))
                line[i] = v
                line[size - 1 - i] = v
            }
        }
        var plane = [Float](repeating: 0, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                plane[row * size + column] = line[row] * line[column]
            }
        }
        return plane
    }

    private static func padded(_ image: CGImage, to side: Int) -> CGImage? {
        guard image.width != side || image.height != side else { return image }
        guard let context = CGContext(data: nil, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func pixelBuffer(from image: CGImage, side: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true,
                                           kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, side, side,
                                  kCVPixelFormatType_32BGRA, attributes as CFDictionary,
                                  &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: side, height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    /// Core ML hands back a BGRA pixel buffer whose memory is only valid while locked. Turning it
    /// into a `CGImage` here means one representation for both paths — the tile that was just
    /// produced and the tile read back from disk accumulate through identical code, so a resumed
    /// picture cannot differ from an uninterrupted one by a channel swap.
    private static func image(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let context = CGContext(data: base,
                                width: CVPixelBufferGetWidth(buffer),
                                height: CVPixelBufferGetHeight(buffer),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
        return context?.makeImage()
    }

    private static func accumulate(_ produced: CGImage,
                                   into colour: inout [Float],
                                   weight: inout [Float],
                                   at origin: (x: Int, y: Int),
                                   canvas: (width: Int, height: Int),
                                   ramp: [Float]) {
        let width = produced.width, height = produced.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.draw(produced, in: CGRect(x: 0, y: 0, width: width, height: height))

        for row in 0..<height {
            let canvasRow = origin.y + row
            guard canvasRow < canvas.height else { break }
            for column in 0..<width {
                let canvasColumn = origin.x + column
                guard canvasColumn < canvas.width else { break }
                let w = ramp[row * width + column]
                guard w > 0 else { continue }

                let source = (row * width + column) * 4
                let target = (canvasRow * canvas.width + canvasColumn) * 3
                colour[target]     += Float(pixels[source]) * w
                colour[target + 1] += Float(pixels[source + 1]) * w
                colour[target + 2] += Float(pixels[source + 2]) * w
                weight[canvasRow * canvas.width + canvasColumn] += w
            }
        }
    }

    private static func resolve(colour: [Float], weight: [Float],
                                width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let w = max(weight[index], 1e-6)
            pixels[index * 4]     = UInt8(min(max(colour[index * 3] / w, 0), 255))
            pixels[index * 4 + 1] = UInt8(min(max(colour[index * 3 + 1] / w, 0), 255))
            pixels[index * 4 + 2] = UInt8(min(max(colour[index * 3 + 2] / w, 0), 255))
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { throw GenerationError.failed(reason: "The enlarged picture couldn't be assembled.") }
        return image
    }
}
