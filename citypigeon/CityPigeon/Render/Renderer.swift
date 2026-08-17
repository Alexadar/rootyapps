import Foundation
import Metal
import MetalKit
import simd

/// The Metal renderer: a **read-only viewer** over engine state.
///
/// It runs no physics, owns no rules, and holds no game state beyond what it needs to draw a frame.
/// Everything it knows arrives as a `Snapshot`. Delete this whole directory and the engine still
/// runs, still tests, and still sweeps — which is the property that keeps the two from tangling.
///
/// The scene is one instanced unit cube, drawn once. Buildings, street, kerbs, vehicles, pedestrians,
/// the pigeon, payloads, the predicted arc and the landing ring are all boxes; the only texture is
/// froggo 1's `scraper.png` on building facades. A low-poly city needs no asset pipeline, which is
/// exactly why PROMPT §4 asks for one.
final class Renderer: NSObject, MTKViewDelegate {

    struct Instance {
        var center: SIMD3<Float>
        var halfExtent: SIMD3<Float>
        var color: SIMD4<Float>
        var flags: SIMD4<Float>          // textured, tiling, emissive, unused
    }

    struct Uniforms {
        var viewProjection: float4x4
        var lightDirection: SIMD3<Float>
        var ambient: Float
        var fogColor: SIMD3<Float>
        var fogDensity: Float
    }

    // MARK: - Metal objects

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var cubePipeline: MTLRenderPipelineState!
    private var skyPipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var facadeTexture: MTLTexture?
    private var sampler: MTLSamplerState!

    /// Triple buffering, so the CPU can build frame N+1 while the GPU draws frame N without either
    /// waiting on the other or writing into a buffer that is still being read.
    private static let framesInFlight = 3
    private var instanceBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let inFlight = DispatchSemaphore(value: framesInFlight)
    private static let maxInstances = 4096

    // MARK: - Scene state

    private let config: WorldConfig
    /// Set every frame by the host view. The renderer never mutates it.
    var snapshot = Snapshot()
    var aspect: Float = 16.0 / 9.0
    private var instances: [Instance] = []
    /// Splats persist across frames; they are decoration, not state the engine cares about.
    private var splats: [(x: Float, size: Float, born: Float)] = []
    private var seenPayloads = 0

    init?(view: MTKView, config: WorldConfig) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.config = config
        super.init()

        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: Double(Palette.skyTop.x), green: Double(Palette.skyTop.y),
                                        blue: Double(Palette.skyTop.z), alpha: 1)
        view.preferredFramesPerSecond = 60

        guard let library = device.makeDefaultLibrary() else { return nil }

        let cubeDesc = MTLRenderPipelineDescriptor()
        cubeDesc.vertexFunction = library.makeFunction(name: "cube_vertex")
        cubeDesc.fragmentFunction = library.makeFunction(name: "cube_fragment")
        cubeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        cubeDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        // Premultiplied alpha, for the arc ribbon and the landing ring.
        let a = cubeDesc.colorAttachments[0]!
        a.isBlendingEnabled = true
        a.sourceRGBBlendFactor = .sourceAlpha
        a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let skyDesc = MTLRenderPipelineDescriptor()
        skyDesc.vertexFunction = library.makeFunction(name: "sky_vertex")
        skyDesc.fragmentFunction = library.makeFunction(name: "sky_fragment")
        skyDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        skyDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        do {
            cubePipeline = try device.makeRenderPipelineState(descriptor: cubeDesc)
            skyPipeline = try device.makeRenderPipelineState(descriptor: skyDesc)
        } catch { return nil }

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)

        let samp = MTLSamplerDescriptor()
        samp.sAddressMode = .repeat
        samp.tAddressMode = .repeat
        samp.minFilter = .linear
        samp.magFilter = .linear
        samp.mipFilter = .linear
        sampler = device.makeSamplerState(descriptor: samp)

        facadeTexture = Renderer.loadFacade(device: device)

        for _ in 0..<Renderer.framesInFlight {
            instanceBuffers.append(device.makeBuffer(
                length: MemoryLayout<Instance>.stride * Renderer.maxInstances,
                options: .storageModeShared)!)
        }
    }

    /// froggo 1's `scraper.png`, unchanged and already tileable — the far plane of the same city.
    private static func loadFacade(device: MTLDevice) -> MTLTexture? {
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(name: "scraper", scaleFactor: 1, bundle: .main,
                                      options: [.SRGB: false,
                                                .generateMipmaps: true,
                                                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)])
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspect = size.height > 0 ? Float(size.width / size.height) : 16.0 / 9.0
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer() else { return }

        inFlight.wait()
        cmd.addCompletedHandler { [inFlight] _ in inFlight.signal() }

        buildScene()

        let buffer = instanceBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % Renderer.framesInFlight
        let count = min(instances.count, Renderer.maxInstances)
        instances.withUnsafeBytes { src in
            buffer.contents().copyMemory(from: src.baseAddress!,
                                         byteCount: count * MemoryLayout<Instance>.stride)
        }

        var uniforms = makeUniforms()
        var skyColors = [SIMD4<Float>(Palette.skyTop, 1), SIMD4<Float>(Palette.skyHorizon, 1)]

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal(); return
        }

        // Sky first, depth off, so everything else draws over it.
        enc.setRenderPipelineState(skyPipeline)
        enc.setFragmentBytes(&skyColors, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.setRenderPipelineState(cubePipeline)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.back)
        // Metal's default front face is CLOCKWISE. The cube above is wound counter-clockwise, so
        // without this every box renders inside-out: the near faces are culled and you see the
        // inside of the far ones. It looks like a lighting bug and is not one.
        enc.setFrontFacing(.counterClockwise)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        if let facadeTexture { enc.setFragmentTexture(facadeTexture, index: 0) }
        enc.setFragmentSamplerState(sampler, index: 0)
        if count > 0 {
            // 24 vertices as six quads, one draw per face. Six draws rather than one indexed draw
            // keeps the shader's `vid / 4` face maths trivial, and at six calls a frame the
            // difference is not measurable.
            for face in 0..<6 {
                enc.drawPrimitives(type: .triangleStrip, vertexStart: face * 4, vertexCount: 4,
                                   instanceCount: count)
            }
        }
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Camera

    /// A locked side view. The camera never rotates and the player never controls it — depth is for
    /// parallax and readability, not for aiming, exactly as PROMPT §2 requires.
    private func makeUniforms() -> Uniforms {
        let c = config

        // Frame from BOTH constraints, not one.
        //
        // Deriving the vertical extent from `width / aspect` alone means a near-square window shows
        // 85 m of sky and puts the street off the bottom edge — which is exactly what the first run
        // did. Take whichever of "show the whole playable width" and "show the whole altitude band"
        // binds harder, so the game is framed correctly at any window shape.
        let needWidth = Float(c.visibleAheadOfPigeon - c.cullBehindPigeon)
        let needHeight = Float(c.altitudeRange.upperBound) + 14      // headroom above the ceiling
        let height = max(needHeight, needWidth / max(aspect, 0.1))

        let centreX = snapshot.pigeonX + Float(c.visibleAheadOfPigeon + c.cullBehindPigeon) / 2
        // Bias the frame down so the street sits comfortably inside it rather than on the edge —
        // the street is where the targets are, and it is the half of the screen that matters.
        let centreY = height / 2 - Float(groundBias)

        // Narrow field of view from far back: enough perspective for the two building rows to part
        // with parallax, little enough that the play plane still reads as a plane.
        let fov: Float = 26 * .pi / 180
        let distance = (height / 2) / tan(fov / 2)

        let eye = SIMD3<Float>(centreX, centreY, distance)
        let look = SIMD3<Float>(centreX, centreY, 0)
        let view = float4x4.lookAt(eye: eye, target: look, up: SIMD3(0, 1, 0))
        let proj = float4x4.perspective(fovY: fov, aspect: aspect, near: 1, far: distance + 500)

        return Uniforms(viewProjection: proj * view,
                        // Sun from ahead-left and above, so the pigeon's near side is lit and the
                        // buildings behind fall away into shade.
                        lightDirection: normalize(SIMD3(-0.35, 0.82, 0.45)),
                        ambient: 0.62,
                        fogColor: Palette.skyHorizon,
                        // Fog measured from the PLAY PLANE, not from the camera. Keyed to the camera
                        // it fogs the whole scene uniformly — the first run washed the entire city
                        // toward white because the camera sits 150 m back from everything.
                        fogDensity: distance)
    }

    /// How far below the frame's centre the street sits.
    private let groundBias: Float = 3

    // MARK: - Scene assembly

    private func box(_ centre: SIMD3<Float>, _ half: SIMD3<Float>, _ colour: SIMD3<Float>,
                     alpha: Float = 1, textured: Bool = false, tiling: Float = 0,
                     emissive: Float = 0) {
        instances.append(Instance(center: centre, halfExtent: half,
                                  color: SIMD4(colour, alpha),
                                  flags: SIMD4(textured ? 1 : 0, tiling, emissive, 0)))
    }

    private func buildScene() {
        instances.removeAll(keepingCapacity: true)
        let c = config
        let s = snapshot

        buildCity(around: s.pigeonX)
        buildStreet(around: s.pigeonX)
        buildSplats(now: s.time)

        // Iterating the entity blocks is the renderer's job, not the engine's: building an instance
        // buffer is inherently a loop, and this side of the boundary is decor.
        for i in 0..<s.targets.slots where s.targets.alive[i] {
            let x = s.targets.x[i], hit = s.targets.hit[i], v = s.targets.v[i]
            if s.targets.kind[i] > 0.5 {
                buildPedestrian(x: x, hit: hit)
            } else {
                buildCar(x: x, speed: v, hit: hit, slot: i)
            }
        }

        buildArcAndRing()

        for i in 0..<s.payloads.slots where s.payloads.alive[i] {
            let r = 0.28 + 0.22 * s.payloads.kind[i]
            box(SIMD3(s.payloads.x[i], s.payloads.y[i], Renderer.zPlay),
                SIMD3(r, r, r), Palette.payload, emissive: 0.15)
        }

        // Other pigeons, drawn with the same rig as the player so a hazard reads as the same kind of
        // thing the player is — tinted darker and set slightly back in z so it never reads as "you".
        for i in 0..<s.flock.slots where s.flock.alive[i] {
            buildPigeon(x: s.flock.x[i], y: s.flock.y[i], z: Renderer.zPlay - 1.4,
                        facingLeft: s.flock.v[i] < 0, tint: Palette.flockTint)
        }

        buildPigeon(x: s.pigeonX, y: s.pigeonY, z: Renderer.zPlay,
                    facingLeft: false, tint: 1.0)
        _ = c
    }

    // Depth lanes. The physics is one-dimensional in x; these only separate things visually, which
    // is what "3-D, but it plays in a plane" means in practice.
    private static let zRoad: Float = 0
    private static let zPlay: Float = 1.6          // pigeon and payloads
    private static let zPavement: Float = 4.4      // pedestrians
    // Well behind the action. The first pass put the near row at z = −14 with a half-depth of 11,
    // so it spanned −25…−3 and effectively stood *in* the play plane: the city towered over the
    // street, leaned hard with perspective, and hid the traffic that is the entire game.
    private static let zBuildingNear: Float = -32
    private static let zBuildingFar: Float = -68

    /// Skyscrapers, generated deterministically from their slot index so the city is stable as the
    /// camera moves and identical on every run of a seed.
    private func buildCity(around x: Float) {
        // Two rows with different jobs. The near row is the street's own low blocks, kept **below
        // the flight band** so the pigeon silhouettes against sky rather than against masonry — a
        // bird over a city flies above the rooftops, and it is also the only way the playfield
        // reads. The far row is the skyline PROMPT §2 asks for: tall, distant, and hazed back.
        for (z, spacing, scale, low, high) in
            [(Renderer.zBuildingNear, Float(21), Float(1.0), Float(4), Float(10)),
             (Renderer.zBuildingFar, Float(34), Float(1.0), Float(19), Float(21))] {
            let first = Int(floor((x - 140) / spacing))
            let last = Int(ceil((x + 220) / spacing))
            for i in first...last {
                let h = Renderer.hash(i, z == Renderer.zBuildingFar ? 17 : 3)
                // Shorter than the first pass, and deliberately: the frame is ~46 m tall and the
                // pigeon flies at 12–24 m, so a skyline that routinely exceeds the frame buries the
                // playfield. These top out just above the flight ceiling, which reads as a city
                // without competing with it.
                let height = (low + h * high) * scale
                let width = (5 + Renderer.hash(i, 91) * 4) * scale
                let depth = 5 + Renderer.hash(i, 57) * 3
                let cx = Float(i) * spacing + Renderer.hash(i, 33) * 4
                box(SIMD3(cx, height / 2, z), SIMD3(width, height / 2, depth),
                    Palette.facade, textured: true, tiling: 0.34,
                    // A few windows are lit even by day — the reflection reading, and it keeps
                    // froggo's systemOrange present in a daylight scene.
                    emissive: Renderer.hash(i, 71) > 0.72 ? 0.1 : 0)
                // Roof cap, in flat facade blue darkened — reads as a top surface and stops the
                // tiled texture running off the top edge.
                box(SIMD3(cx, height + 0.4, z), SIMD3(width * 1.04, 0.4, depth * 1.04),
                    Palette.facade * 0.55)
            }
        }
    }

    private func buildStreet(around x: Float) {
        let halfSpan: Float = 260
        // Fill everything below the street, back past the far building row. Without it the camera
        // sees past the road slab into the sky gradient — the bottom of the frame goes white and
        // the distant buildings appear to float.
        //
        // Its top sits at y = −0.05, deliberately BELOW the road's y = 0. Coplanar faces z-fight,
        // and z-fighting on a surface the camera slides along every frame reads as the whole road
        // flickering. Every horizontal surface here is given its own distinct height for that
        // reason, not for any physical one.
        box(SIMD3(x, -20.05, -34), SIMD3(halfSpan, 20, 72), Palette.asphalt * 0.85)
        box(SIMD3(x, -0.5, Renderer.zRoad), SIMD3(halfSpan, 0.5, 7.5), Palette.asphalt)
        box(SIMD3(x, -0.35, Renderer.zPavement + 1.1), SIMD3(halfSpan, 0.45, 2.6), Palette.pavement)
        box(SIMD3(x, -0.3, -8.4), SIMD3(halfSpan, 0.5, 2.2), Palette.pavement)
        box(SIMD3(x, 0.12, 6.9), SIMD3(halfSpan, 0.11, 0.35), Palette.kerb)
        box(SIMD3(x, 0.12, -6.9), SIMD3(halfSpan, 0.11, 0.35), Palette.kerb)

        // Dashes, snapped to a world grid so they slide past rather than crawling with the camera.
        let spacing: Float = 8
        let first = Int(floor((x - halfSpan) / spacing)), last = Int(ceil((x + halfSpan) / spacing))
        for i in first...last {
            box(SIMD3(Float(i) * spacing, 0.07, Renderer.zRoad), SIMD3(1.8, 0.05, 0.22),
                Palette.laneMark)
        }
    }

    private func buildCar(x: Float, speed: Float, hit: Bool, slot: Int) {
        // Keyed to the target's SLOT, not its position. Hashing `x` re-rolls the colour every
        // frame the car moves, which reads as flickering rather than as traffic.
        let paint = Palette.vehiclePaint[Int(Renderer.hash(slot, 13) * 6) % 6]
        let body = hit ? paint * 0.75 : paint
        let t = (x: x, speed: speed, hit: hit)
        box(SIMD3(t.x, 0.62, Renderer.zRoad), SIMD3(2.2, 0.55, 1.7), body)
        box(SIMD3(t.x - (t.speed < 0 ? -0.25 : 0.25), 1.42, Renderer.zRoad),
            SIMD3(1.25, 0.42, 1.5), Palette.vehicleGlass)
        // Wheels, as two dark slabs — enough to read as a vehicle at this distance.
        box(SIMD3(t.x - 1.35, 0.28, Renderer.zRoad), SIMD3(0.42, 0.28, 1.78), Palette.outline)
        box(SIMD3(t.x + 1.35, 0.28, Renderer.zRoad), SIMD3(0.42, 0.28, 1.78), Palette.outline)
        if t.hit { box(SIMD3(t.x, 1.9, Renderer.zRoad), SIMD3(1.5, 0.12, 1.3), Palette.payload) }
    }

    private func buildPedestrian(x: Float, hit: Bool) {
        let z = Renderer.zPavement
        let t = (x: x, hit: hit)
        let body = hit ? Palette.pedestrianBody * 0.7 : Palette.pedestrianBody
        box(SIMD3(t.x, 0.72, z), SIMD3(0.3, 0.55, 0.28), body)
        box(SIMD3(t.x, 1.48, z), SIMD3(0.24, 0.24, 0.24), Palette.pedestrianHead)
        if t.hit { box(SIMD3(t.x, 1.82, z), SIMD3(0.34, 0.1, 0.32), Palette.payload) }
    }

    /// The pigeon, from nine primitives and animated by transform alone.
    ///
    /// Same construction as froggo2's frog rig, and for the same reason its doc comment gives: an
    /// authored model can replace this later without touching a line of the animation, because the
    /// animation only ever moves boxes about.
    private func buildPigeon(x: Float, y: Float, z: Float, facingLeft: Bool, tint: Float) {
        let s = snapshot
        let k = Renderer.pigeonScale * (tint < 1 ? 0.85 : 1)
        // Oncoming birds face the other way. One sign flip on every x offset, rather than a second
        // rig — the body is symmetric, only the head, beak and tail are not.
        let f: Float = facingLeft ? -1 : 1
        // Wingbeat from a clock, slowed while diving so the bird reads as gliding down.
        let beat = sin(s.time * 11) * (0.55 - 0.3 * min(1, abs(s.pigeonVY) / 4))
        // Pitch with vertical speed: nose down when diving. Cheap, and it is most of the life.
        let pitch = max(-0.4, min(0.4, -s.pigeonVY * 0.06)) * k

        box(SIMD3(x, y, z), SIMD3(0.62, 0.4, 0.41) * k, Palette.pigeonBody * tint)
        box(SIMD3(x + f * 0.53 * k, y + 0.23 * k + pitch, z), SIMD3(0.26, 0.26, 0.26) * k,
            Palette.pigeonNeck * tint)
        box(SIMD3(x + f * 0.82 * k, y + 0.20 * k + pitch, z), SIMD3(0.16, 0.07, 0.07) * k,
            Palette.pigeonBeak * tint)
        box(SIMD3(x + f * 0.58 * k, y + 0.25 * k + pitch, z + 0.16 * k),
            SIMD3(0.055, 0.055, 0.055) * k, Palette.pigeonEye)
        box(SIMD3(x + f * 0.58 * k, y + 0.25 * k + pitch, z - 0.16 * k),
            SIMD3(0.055, 0.055, 0.055) * k, Palette.pigeonEye)
        // The beak stays at full brightness on a darkened bird: one bright mark is what keeps a
        // silhouette reading as a bird facing a direction rather than as a smudge.
        if tint < 1 {
            box(SIMD3(x + f * 0.82 * k, y + 0.20 * k + pitch, z),
                SIMD3(0.16, 0.07, 0.07) * k, Palette.pigeonBeak)
        }
        box(SIMD3(x - f * 0.68 * k, y + 0.06 * k, z), SIMD3(0.3, 0.16, 0.3) * k, Palette.pigeonWing * tint)
        box(SIMD3(x - f * 0.04 * k, y + (0.24 + beat * 0.27) * k, z + (0.5 + beat * 0.08) * k),
            SIMD3(0.45, 0.085, 0.45) * k, Palette.pigeonWing * tint)
        box(SIMD3(x - f * 0.04 * k, y + (0.24 + beat * 0.27) * k, z - (0.5 + beat * 0.08) * k),
            SIMD3(0.45, 0.085, 0.45) * k, Palette.pigeonWing * tint)
        box(SIMD3(x + f * 0.08 * k, y - 0.30 * k, z), SIMD3(0.08, 0.1, 0.19) * k, Palette.pigeonBeak * tint)
    }

    /// The pigeon's size in metres of half-body-length.
    ///
    /// Deliberately far larger than a real pigeon. The camera has to show 80 m of street so the
    /// predicted impact point stays on screen, and at that scale an accurate 30 cm bird is four
    /// pixels — the player cannot read its pitch, its wingbeat or even reliably where it is. Every
    /// side-scroller makes this trade; this one just writes it down.
    private static let pigeonScale: Float = 3.7

    /// Predicted arc plus landing ring — the owner's choice, and the thing that makes the charge
    /// legible at all given the payload always lands directly beneath the bird.
    private func buildArcAndRing() {
        let s = snapshot
        guard s.arc.count > 1 else { return }
        for i in 1..<s.arc.count {
            let a = s.arc[i - 1], b = s.arc[i]
            let mid = (a + b) / 2
            let d = b - a
            let len = max(0.001, simd_length(d))
            // Beads rather than a swept ribbon: at this camera distance the difference is invisible
            // and a bead needs no per-segment rotation.
            let fade = Float(i) / Float(s.arc.count)
            box(SIMD3(mid.x, mid.y, Renderer.zPlay), SIMD3(len * 0.45, 0.22, 0.22),
                Palette.arc, alpha: Palette.arcAlpha * (0.35 + 0.65 * fade), emissive: 0.25)
        }

        // The landing marker is a **vertical blade**, not a ring on the ground.
        //
        // A flat disc lying on the street is the obvious thing to draw and it is invisible here: the
        // camera is a locked side view, so a horizontal plate is seen edge-on and all that reaches
        // the screen is its own thickness. The first recording had a working aim assist that could
        // not be seen in a single frame of twenty seconds. Standing it upright costs nothing and is
        // legible from exactly the one angle this game is ever viewed from.
        if let land = s.landingX {
            let colour = s.landingOnTarget ? Palette.ringReachable : Palette.ringUnreachable
            box(SIMD3(land, 3.4, Renderer.zPlay), SIMD3(0.2, 3.4, 0.2), colour,
                alpha: 0.85, emissive: 0.4)
            // A short cross-bar at street level, given real height so it too reads side-on.
            box(SIMD3(land, 0.35, Renderer.zPlay), SIMD3(1.8, 0.35, 0.2), colour,
                alpha: 0.7, emissive: 0.3)
        }
    }

    private func buildSplats(now: Float) {
        // Newly arrived payloads leave a mark. The engine does not track these — they are decoration
        // and the renderer is welcome to forget them.
        splats.removeAll { now - $0.born > 6 }
        for sp in splats {
            let age = (now - sp.born) / 6
            // Given height for the same reason the landing marker is upright: flat on the road, a
            // splat is edge-on to a side-view camera and effectively invisible.
            box(SIMD3(sp.x, 0.12, Renderer.zRoad), SIMD3(sp.size, 0.12, sp.size * 0.8),
                Palette.payload, alpha: 0.9 * (1 - age))
        }
    }

    func noteImpact(x: Float, mass: Float, at time: Float) {
        splats.append((x: x, size: 0.7 + mass * 0.8, born: time))
        if splats.count > 48 { splats.removeFirst(splats.count - 48) }
    }

    /// Deterministic value hash for city generation. Same city every run, and no state to carry.
    private static func hash(_ i: Int, _ salt: Int) -> Float {
        var h = UInt64(bitPattern: Int64(i &* 0x9E37_79B1 &+ salt &* 0x85EB_CA77))
        h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33; h = h &* 0xC4CE_B9FE_1A85_EC53
        h ^= h >> 33
        return Float(h % 100_000) / 100_000
    }
}

// MARK: - Matrices
//
// Written out rather than pulled from a library: four small functions, and the alternative is a
// dependency for four small functions.

extension float4x4 {

    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return float4x4(columns: (SIMD4(x, 0, 0, 0),
                                  SIMD4(0, y, 0, 0),
                                  SIMD4(0, 0, z, -1),
                                  SIMD4(0, 0, z * near, 0)))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = normalize(target - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        return float4x4(columns: (SIMD4(s.x, u.x, -f.x, 0),
                                  SIMD4(s.y, u.y, -f.y, 0),
                                  SIMD4(s.z, u.z, -f.z, 0),
                                  SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)))
    }
}
