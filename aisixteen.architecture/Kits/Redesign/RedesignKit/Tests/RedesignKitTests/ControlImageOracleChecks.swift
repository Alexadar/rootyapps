import Foundation
import Testing
@testable import RedesignKit

/// The ControlNet conditioning image, checked against hand-computed pixel values.
///
/// This is an oracle suite rather than a smoke test because the failure mode has no symptom you
/// can see. Get the polarity backwards and nothing crashes, the thumbnail looks like a plausible
/// grey gradient, and the model quietly pushes the near wall away and pulls the far one in. The
/// only way to catch it is to assert the actual numbers.
///
/// The contract, fixed by `../aisixteen.models/scripts/convert_sd15_coreml.py`: 512 × 512, three
/// channels, 8-bit, and MiDaS-convention inverse depth — **near is bright**.
@Suite("ControlNet conditioning image")
struct ControlImageOracleChecks {

    /// Read one pixel's red channel (R == G == B by construction).
    private func level(_ image: PreviewImage, x: Int, y: Int) -> UInt8 {
        image.pixels[(y * image.size.width + x) * 4]
    }

    private func alpha(_ image: PreviewImage, x: Int, y: Int) -> UInt8 {
        image.pixels[(y * image.size.width + x) * 4 + 3]
    }

    @Test("The output is exactly 512 × 512 RGBA with three identical channels")
    func shapeIsTheModelContract() {
        // Core ML models are fixed shape. This is not a preference.
        let values: [Float] = [0, 0.25, 0.5, 1]
        let image = try! #require(ControlImageRenderer.render(values: values,
                                                              size: PixelSize(width: 2, height: 2)))
        #expect(image.size == PixelSize(width: 512, height: 512))
        #expect(image.isWellFormed)
        #expect(image.pixels.count == 512 * 512 * 4)

        for (x, y) in [(0, 0), (100, 300), (511, 511)] {
            let offset = (y * 512 + x) * 4
            #expect(image.pixels[offset] == image.pixels[offset + 1])
            #expect(image.pixels[offset + 1] == image.pixels[offset + 2])
            #expect(image.pixels[offset + 3] == 255)
        }
    }

    @Test("Disparity: the largest value is white and the smallest is black")
    func disparityNearIsBright() {
        // A 2 × 1 frame: left = far (0), right = near (1). In disparity, large means near, and
        // the ControlNet wants near bright.
        let image = try! #require(ControlImageRenderer.render(
            values: [0, 1],
            size: PixelSize(width: 2, height: 1),
            polarity: .disparityNearIsLarge,
            fit: .stretch))

        #expect(level(image, x: 10, y: 256) == 0, "far must be black")
        #expect(level(image, x: 500, y: 256) == 255, "near must be white")
    }

    @Test("Metric depth: the polarity is inverted, so the smallest value is white")
    func metricDepthIsInverted() {
        // LiDAR gives metres: small means near. That must come out BRIGHT, which means inverting.
        let image = try! #require(ControlImageRenderer.render(
            values: [0.5, 8.0],
            size: PixelSize(width: 2, height: 1),
            polarity: .depthNearIsSmall,
            fit: .stretch))

        #expect(level(image, x: 10, y: 256) == 255, "0.5 m away is the nearest thing — white")
        #expect(level(image, x: 500, y: 256) == 0, "8 m away is the farthest — black")
    }

    @Test("Normalisation maps the frame's own min and max to 0 and 255")
    func normalisationUsesTheFrameRange() {
        // A room photographed from across it never spans the sensor's full range. Normalising to
        // the frame is what gives the model usable relief instead of a flat mid-grey.
        // Values chosen to be exact in binary floating point, so the oracle is arithmetic rather
        // than an approximation: (0.5 − 0.25) / (0.75 − 0.25) = 0.5 exactly.
        let image = try! #require(ControlImageRenderer.render(
            values: [0.25, 0.5, 0.75],
            size: PixelSize(width: 3, height: 1),
            fit: .stretch))

        #expect(level(image, x: 5, y: 256) == 0)
        #expect(level(image, x: 500, y: 256) == 255)
        // The midpoint of the range lands on the midpoint of the ramp: 0.5 × 255 = 127.5 → 128.
        #expect(level(image, x: 256, y: 256) == 128)
    }

    @Test("A constant-depth frame becomes mid grey and does not divide by zero")
    func flatFrameIsMidGrey() {
        // A wall shot flat on. Dividing by a zero range produces NaN and then a garbage buffer.
        let image = try! #require(ControlImageRenderer.render(
            values: [Float](repeating: 2.5, count: 16),
            size: PixelSize(width: 4, height: 4)))

        #expect(level(image, x: 0, y: 0) == 128)
        #expect(level(image, x: 511, y: 511) == 128)
        #expect(level(image, x: 256, y: 256) == 128)
    }

    @Test("Holes in a LiDAR frame take the far value rather than flattening the map")
    func infiniteHolesAreFar() {
        // LiDAR returns +inf where nothing reflected — a window, a mirror, the sky. Including
        // those in the range would flatten the entire map to one value.
        let image = try! #require(ControlImageRenderer.render(
            values: [0, .infinity, 1, .nan],
            size: PixelSize(width: 4, height: 1),
            fit: .stretch))

        #expect(level(image, x: 20, y: 256) == 0)
        #expect(level(image, x: 150, y: 256) == 0, "a hole reads as far, never as a phantom object in front of the camera")
        #expect(level(image, x: 280, y: 256) == 255, "the finite maximum still reaches white")
        #expect(level(image, x: 480, y: 256) == 0)
    }

    @Test("A frame that is entirely holes produces nothing rather than a black square")
    func allHolesIsNil() {
        #expect(ControlImageRenderer.render(values: [.infinity, .nan],
                                            size: PixelSize(width: 2, height: 1)) == nil)
    }

    @Test("A landscape frame is centre-cropped, not stretched")
    func nonSquareIsCropped() {
        // Stretching tells the model the room is a different shape than it is — which is precisely
        // the geometry claim this app makes and must not break.
        //
        // 8 × 4, values ramping left to right 0…7. A centre crop takes columns 2…5, so the
        // rendered image spans only values 2…5 — and those become the new black and white.
        var values = [Float](repeating: 0, count: 32)
        for y in 0..<4 { for x in 0..<8 { values[y * 8 + x] = Float(x) } }

        let cropped = try! #require(ControlImageRenderer.render(
            values: values, size: PixelSize(width: 8, height: 4), fit: .centerCrop))
        let stretched = try! #require(ControlImageRenderer.render(
            values: values, size: PixelSize(width: 8, height: 4), fit: .stretch))

        // Normalisation still runs over the WHOLE frame, so the cropped window (values 2…5) maps
        // to 2/7…5/7 of the ramp rather than to full black and full white.
        #expect(level(cropped, x: 2, y: 256) == UInt8((2.0 / 7.0 * 255).rounded()))
        #expect(level(cropped, x: 509, y: 256) == UInt8((5.0 / 7.0 * 255).rounded()))
        // The stretched version does reach both ends — which is exactly why it is not the default.
        #expect(level(stretched, x: 2, y: 256) == 0)
        #expect(level(stretched, x: 509, y: 256) == 255)
    }

    @Test("A portrait frame crops the long edge too")
    func portraitCropsVertically() {
        var values = [Float](repeating: 0, count: 32)
        for y in 0..<8 { for x in 0..<4 { values[y * 4 + x] = Float(y) } }

        let image = try! #require(ControlImageRenderer.render(
            values: values, size: PixelSize(width: 4, height: 8), fit: .centerCrop))

        #expect(level(image, x: 256, y: 2) == UInt8((2.0 / 7.0 * 255).rounded()))
        #expect(level(image, x: 256, y: 509) == UInt8((5.0 / 7.0 * 255).rounded()))
    }

    @Test("A mismatched value count is refused rather than read out of bounds")
    func mismatchedInputIsRefused() {
        #expect(ControlImageRenderer.render(values: [0, 1, 2],
                                            size: PixelSize(width: 2, height: 2)) == nil)
        #expect(ControlImageRenderer.render(values: [],
                                            size: PixelSize(width: 0, height: 0)) == nil)
    }

    @Test("Hard edges survive: a depth step is not smeared into a ramp")
    func edgesAreNotBlurred() {
        // The step at an object boundary IS the signal. Bilinear resampling across it invents a
        // ramp where the model should see a wall.
        var values = [Float](repeating: 0, count: 64)
        for y in 0..<8 { for x in 0..<8 { values[y * 8 + x] = x < 4 ? 0 : 1 } }

        let image = try! #require(ControlImageRenderer.render(
            values: values, size: PixelSize(width: 8, height: 8), fit: .stretch))

        // Every pixel is either black or white — nothing in between.
        var seen = Set<UInt8>()
        for x in stride(from: 0, to: 512, by: 7) { seen.insert(level(image, x: x, y: 256)) }
        #expect(seen == [0, 255])
    }

    @Test("Alpha is opaque everywhere")
    func alphaIsOpaque() {
        let image = try! #require(ControlImageRenderer.render(
            values: [0, 1], size: PixelSize(width: 2, height: 1), fit: .stretch))
        for (x, y) in [(0, 0), (255, 255), (511, 511)] {
            #expect(alpha(image, x: x, y: y) == 255)
        }
    }
}

@Suite("Control signals and depth provenance")
struct ControlSignalChecks {

    @Test("Only camera-measured depth claims to have been read")
    func badgeCopyMatchesProvenance() {
        // The design handoff cut measuring entirely. No badge may imply a dimension.
        let forbidden = ["measure", "dimension", "metre", "meter", "feet", "inch", "cm ", "size of",
                         "distance", "area", "square"]
        for provenance in DepthProvenance.allCases {
            let text = provenance.badgeText.lowercased()
            for word in forbidden {
                #expect(!text.contains(word), "\(provenance) badge claims a measurement: \(text)")
            }
        }
        #expect(DepthProvenance.lidar.badgeText == "Depth read — geometry will hold")
        #expect(DepthProvenance.dualCamera.badgeText == "Depth read — geometry will hold")
        #expect(DepthProvenance.embedded.badgeText == "Depth read — geometry will hold")
        #expect(DepthProvenance.estimated.badgeText == "Depth estimated — geometry will hold")
        #expect(DepthProvenance.synthetic.badgeText == "Sample depth — for testing")
    }

    @Test("Measured and estimated are distinguished")
    func measuredIsDistinct() {
        #expect(DepthProvenance.lidar.isMeasured)
        #expect(DepthProvenance.dualCamera.isMeasured)
        #expect(DepthProvenance.embedded.isMeasured)
        #expect(!DepthProvenance.estimated.isMeasured)
        #expect(!DepthProvenance.synthetic.isMeasured)
    }

    @Test("MLSD and lineart are distinct kinds, because they are distinct ControlNets")
    func mlsdIsNotLineart() {
        // `control_v11p_sd15_mlsd` produces straight line SEGMENTS (walls, window frames);
        // `control_v11p_sd15_lineart` produces artistic line DRAWINGS. Collapsing them means the
        // enum asks for the wrong conditioning image and the failure has no symptom but a poor
        // result. This case originally existed only as `.lineart` and drove the MLSD weights.
        #expect(ControlKind.mlsd != ControlKind.lineart)
        #expect(ControlKind.mlsd.rawValue == "mlsd")
        #expect(ControlKind.lineart.rawValue == "lineart")
    }

    @Test("Only depth is producible, and nothing may request a control it cannot draw")
    func onlyDepthIsProducible() {
        #expect(ControlKind.depth.isProducible)
        for kind in ControlKind.allCases where kind != .depth {
            #expect(!kind.isProducible, "\(kind) claims to be producible and is not")
        }
    }

    @Test("Every control kind round-trips through the request, including the unshipped ones")
    func allControlKindsSurviveCoding() throws {
        // The declared-but-unproduced kinds exist so that adding a second ControlNet later
        // is data rather than a signature change. They have to survive encoding today, or that
        // promise is untested.
        let controls = ControlKind.allCases.map {
            ControlSignal(kind: $0,
                          image: Fixture.handle("\($0.rawValue).png", width: 512, height: 512),
                          provenance: .lidar,
                          weight: 0.8)
        }
        let request = Fixture.request(controls: controls)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RedesignRequest.self, from: data)

        #expect(decoded.controls.count == ControlKind.allCases.count)
        #expect(decoded.controls.map(\.kind) == ControlKind.allCases)
        #expect(decoded == request)
        #expect(decoded.digest == request.digest)
    }

    @Test("The depth control is findable among several")
    func depthIsFindable() {
        let request = Fixture.request(controls: [
            Fixture.control(.lineart),
            Fixture.control(.depth, provenance: .dualCamera),
        ])
        #expect(request.depth?.provenance == .dualCamera)
    }

    @Test("A request with no controls has no depth and does not crash")
    func noControlsIsRepresentable() {
        let request = Fixture.request(controls: [])
        #expect(request.depth == nil)
        #expect(!request.digest.isEmpty)
    }

    @Test("Changing a control's weight changes the digest")
    func controlWeightIsPartOfIdentity() {
        let strong = Fixture.request(controls: [
            ControlSignal(kind: .depth, image: Fixture.handle("d.tiff"), provenance: .lidar, weight: 1.0)])
        let weak = Fixture.request(controls: [
            ControlSignal(kind: .depth, image: Fixture.handle("d.tiff"), provenance: .lidar, weight: 0.5)])
        #expect(strong.digest != weak.digest)
    }
}
