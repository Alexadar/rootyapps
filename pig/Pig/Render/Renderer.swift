import Foundation
import ImageIO
import UniformTypeIdentifiers
import Metal
import MetalKit
import simd

/// The Metal renderer: a **read-only viewer** over engine state.
///
/// It runs no physics, owns no rules, and holds no game state beyond what it needs to draw a frame.
/// Everything it knows arrives as a `Snapshot`. Delete this whole directory and the engine still
/// runs and still tests — which is the property that keeps the two from tangling.
///
/// It also authors **no geometry**. The pig's dimensions come from `PigShape` as uniforms and its
/// surface is evaluated in `Shaders.metal`; what this file builds is a list of *anchors* — "an ear at
/// (u, v) = (0.19, 0.15)" — never a position. The consequence is that the pig can change shape every
/// single frame and nothing here has to know.
///
/// There is no vertex buffer anywhere. The body is an indexed parameter grid and the attachments are
/// an indexed unit sphere; both derive their vertex from `vertex_id`.
final class Renderer: NSObject, MTKViewDelegate {

    // MARK: - GPU-facing types
    //
    // Layout is mirrored field for field in `Shaders.metal`. `SIMD3<Float>` and Metal's `float3` are
    // both 16-byte aligned with a stride of 16; `packed_float3` is 12 and would shift every field
    // after it into garbage.

    struct Uniforms {
        var viewProjection: float4x4
        var cameraPosition: SIMD3<Float>
        var time: Float
        var lightDirection: SIMD3<Float>
        var ambient: Float
        var fogColor: SIMD3<Float>
        var fogDensity: Float
        var groundColor: SIMD3<Float>
        var paddockRadius: Float
        var shadowCenter: SIMD3<Float>
        var shadowRadius: Float
    }

    struct Body {
        var model: float4x4
        var rA: SIMD4<Float>       // snout, head, chest, belly
        var rB: SIMD4<Float>       // rump, tailBase, length, stand
        var shape: SIMD4<Float>    // sag, squash, superE, jowl
        var anim: SIMD4<Float>     // gait, wobbleAmplitude, lie, breath
        var extra: SIMD4<Float>    // headLift, chew, fat, unused
        var color: SIMD4<Float>
    }

    struct Blob {
        var anchor: SIMD4<Float>   // (x,y,z,0) world · (u,v,_,1) surface · (u,_,_,2) spine
        var offset: SIMD4<Float>
        var scale: SIMD4<Float>    // radii, taper
        var rot: SIMD4<Float>      // euler, or (lift,_,_,1) in leg mode
        var color: SIMD4<Float>    // rgb, gloss
    }

    /// Where the camera is. **Not simulation state** — it is never in `World`, the engine never sees
    /// it, and two players looking in different directions are playing the identical game.
    struct Camera {
        var yaw: Float = 0
        var pitch: Float = 0.36
        var distance: Float = 3.6
    }

    // MARK: - Mesh resolution

    /// The body's parameter grid. 72 rings is enough that the silhouette of a fully round pig has no
    /// visible facets at arm's length on a phone; the cost is 17k indices and no vertex data at all.
    fileprivate static let bodyRings = 132
    fileprivate static let bodySegments = 72
    fileprivate static let sphereRings = 14
    fileprivate static let sphereSegments = 20
    private static let maxBlobs = 256
    private static let framesInFlight = 3

    // MARK: - Metal objects

    fileprivate let device: MTLDevice
    fileprivate let queue: MTLCommandQueue
    private var skyPipeline: MTLRenderPipelineState!
    private var groundPipeline: MTLRenderPipelineState!
    fileprivate var bodyPipeline: MTLRenderPipelineState!
    fileprivate var blobPipeline: MTLRenderPipelineState!
    fileprivate var depthState: MTLDepthStencilState!
    private var skyDepthState: MTLDepthStencilState!

    fileprivate var bodyIndices: MTLBuffer!
    fileprivate var bodyIndexCount = 0
    fileprivate var sphereIndices: MTLBuffer!
    fileprivate var sphereIndexCount = 0
    private var blobBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let inFlight = DispatchSemaphore(value: framesInFlight)

    // MARK: - Scene state

    fileprivate let config: WorldConfig
    /// Set every frame by the host view. The renderer never mutates it.
    var snapshot = Snapshot()
    var camera = Camera()
    fileprivate var aspect: Float = 16.0 / 9.0
    fileprivate var blobs: [Blob] = []

    /// The live renderer, attached to a view.
    convenience init?(view: MTKView, config: WorldConfig) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else { return nil }

        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        // 4× MSAA. A game whose entire silhouette is one smooth curved animal shows stair-stepping
        // more than a box city does, and at this triangle count it is free.
        view.sampleCount = 4
        view.clearColor = MTLClearColor(red: Double(Palette.skyBottom.x),
                                        green: Double(Palette.skyBottom.y),
                                        blue: Double(Palette.skyBottom.z), alpha: 1)
        view.preferredFramesPerSecond = 120

        self.init(device: device, colorPixelFormat: view.colorPixelFormat,
                  depthPixelFormat: view.depthStencilPixelFormat, sampleCount: view.sampleCount,
                  config: config)
    }

    /// The renderer proper, with no view.
    ///
    /// Split out so the **icon is rendered by the game's own shader** rather than drawn by hand: the
    /// icon pass is this same class, at `sampleCount = 1` into an offscreen texture. An illustrated
    /// icon would start out slightly wrong and drift further with every tuning pass on `PigShape`.
    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat, depthPixelFormat: MTLPixelFormat,
          sampleCount: Int, config: WorldConfig) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.config = config
        super.init()

        guard let library = device.makeDefaultLibrary() else { return nil }

        func pipeline(_ vertexName: String, _ fragmentName: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertexName)
            d.fragmentFunction = library.makeFunction(name: fragmentName)
            d.colorAttachments[0].pixelFormat = colorPixelFormat
            d.depthAttachmentPixelFormat = depthPixelFormat
            d.rasterSampleCount = sampleCount
            return try? device.makeRenderPipelineState(descriptor: d)
        }

        guard let sky = pipeline("sky_vertex", "sky_fragment"),
              let ground = pipeline("ground_vertex", "ground_fragment"),
              let body = pipeline("body_vertex", "body_fragment"),
              let blob = pipeline("blob_vertex", "blob_fragment") else { return nil }
        skyPipeline = sky; groundPipeline = ground; bodyPipeline = body; blobPipeline = blob

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)

        let skyDepth = MTLDepthStencilDescriptor()
        skyDepth.depthCompareFunction = .always
        skyDepth.isDepthWriteEnabled = false
        skyDepthState = device.makeDepthStencilState(descriptor: skyDepth)

        let bodyIdx = Renderer.gridIndices(rings: Renderer.bodyRings, segments: Renderer.bodySegments)
        bodyIndexCount = bodyIdx.count
        bodyIndices = device.makeBuffer(bytes: bodyIdx,
                                        length: MemoryLayout<UInt16>.stride * bodyIdx.count,
                                        options: .storageModeShared)

        let sphereIdx = Renderer.gridIndices(rings: Renderer.sphereRings,
                                             segments: Renderer.sphereSegments)
        sphereIndexCount = sphereIdx.count
        sphereIndices = device.makeBuffer(bytes: sphereIdx,
                                          length: MemoryLayout<UInt16>.stride * sphereIdx.count,
                                          options: .storageModeShared)

        for _ in 0..<Renderer.framesInFlight {
            guard let b = device.makeBuffer(length: MemoryLayout<Blob>.stride * Renderer.maxBlobs,
                                            options: .storageModeShared) else { return nil }
            blobBuffers.append(b)
        }
    }

    /// Triangle indices over a `(rings+1) × (segments+1)` parameter grid.
    ///
    /// Wound counter-clockwise seen from outside, and listed as two explicit triangles rather than a
    /// strip — a strip over a grid needs degenerate joins at every row end, and the classic failure
    /// (a surface of translucent wedges, which `citypigeon` shipped once) comes from listing a quad's
    /// corners in loop order instead of strip order. Two triangles cannot make that mistake.
    private static func gridIndices(rings: Int, segments: Int) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(rings * segments * 6)
        let stride = segments + 1
        for r in 0..<rings {
            for s in 0..<segments {
                let a = UInt16(r * stride + s)
                let b = UInt16(r * stride + s + 1)
                let c = UInt16((r + 1) * stride + s)
                let d = UInt16((r + 1) * stride + s + 1)
                out.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return out
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspect = size.height > 0 ? Float(size.width / size.height) : 1
    }

    // MARK: - Frame

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer() else { return }

        inFlight.wait()
        frameIndex = (frameIndex + 1) % Renderer.framesInFlight
        buffer.addCompletedHandler { [inFlight] _ in inFlight.signal() }

        let s = snapshot
        var body = makeBody(s)
        var uniforms = makeUniforms(s, body: body)
        buildBlobs(s)

        let blobBuffer = blobBuffers[frameIndex]
        blobBuffer.contents().copyMemory(from: blobs,
                                         byteCount: MemoryLayout<Blob>.stride * blobs.count)

        var bodyGrid = SIMD2<UInt32>(UInt32(Renderer.bodyRings), UInt32(Renderer.bodySegments))
        var sphereGrid = SIMD2<UInt32>(UInt32(Renderer.sphereRings), UInt32(Renderer.sphereSegments))
        var skyColors = [SIMD4<Float>(Palette.skyTop, 1), SIMD4<Float>(Palette.skyBottom, 1)]

        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal(); return
        }

        enc.setDepthStencilState(skyDepthState)
        enc.setRenderPipelineState(skyPipeline)
        enc.setFragmentBytes(&skyColors, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.setDepthStencilState(depthState)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        enc.setRenderPipelineState(groundPipeline)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // The body and every attachment read the same `Body` uniform, which is what welds them
        // together: one buffer, one shape, no chance of a stale copy.
        enc.setVertexBytes(&body, length: MemoryLayout<Body>.stride, index: 2)
        enc.setFragmentBytes(&body, length: MemoryLayout<Body>.stride, index: 2)

        enc.setRenderPipelineState(bodyPipeline)
        enc.setVertexBytes(&bodyGrid, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 3)
        enc.setCullMode(.none)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: bodyIndexCount,
                                  indexType: .uint16, indexBuffer: bodyIndices,
                                  indexBufferOffset: 0)

        if !blobs.isEmpty {
            enc.setRenderPipelineState(blobPipeline)
            enc.setVertexBuffer(blobBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&sphereGrid, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: sphereIndexCount,
                                      indexType: .uint16, indexBuffer: sphereIndices,
                                      indexBufferOffset: 0, instanceCount: blobs.count)
        }

        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    // MARK: - Uniforms

    fileprivate func makeBody(_ s: Snapshot) -> Body {
        let shape = s.shape
        let model = float4x4(translation: SIMD3<Float>(s.x, 0, s.z)) * float4x4(rotationY: s.heading)

        // Chewing: a small fast bob, on only while the pig is actually taking a bite.
        let chew: Float = s.eating ? abs(sin(s.time * 14)) : 0

        return Body(
            model: model,
            rA: SIMD4(Float(shape.snout), Float(shape.head), Float(shape.chest), Float(shape.belly)),
            rB: SIMD4(Float(shape.rump), Float(shape.tailBase), Float(shape.length), Float(shape.stand)),
            shape: SIMD4(Float(shape.sag), Float(shape.squash), Float(shape.superE), Float(shape.jowl)),
            anim: SIMD4(s.gait, s.wob * Float(shape.wobbleGain), 0, s.breath),
            extra: SIMD4(Float(shape.headLift), chew, s.fat, Float(shape.underside)),
            color: SIMD4(Palette.pig, 1))
    }

    private func makeUniforms(_ s: Snapshot, body: Body) -> Uniforms {
        let girth = Float(PigShape.girth(s.shape))
        // The camera backs off as the pig grows, so it always fills roughly the same part of the
        // frame. A fixed distance makes a fully fat pig fill the screen and a lean one vanish.
        let distance = camera.distance + Float(s.shape.belly) * 3.2
        let height = Float(s.shape.stand) + 0.9 + s.fat * 0.5

        let focus = SIMD3<Float>(s.x, Float(s.shape.stand) * 0.85, s.z)
        let eye = CameraFrame.eye(focus: focus, yaw: camera.yaw, pitch: camera.pitch,
                                  distance: distance, lift: height * 0.25)

        let view = float4x4(lookAt: eye, target: focus, up: SIMD3<Float>(0, 1, 0))
        let proj = float4x4(perspectiveFOV: 58 * .pi / 180, aspect: aspect, near: 0.05, far: 220)

        return Uniforms(
            viewProjection: proj * view,
            cameraPosition: eye,
            time: s.time,
            lightDirection: normalize(Palette.light),
            ambient: Palette.ambient,
            fogColor: Palette.fog,
            fogDensity: Palette.fogDensity,
            groundColor: Palette.ground,
            paddockRadius: Float(config.paddockRadius),
            shadowCenter: SIMD3<Float>(s.x, 0, s.z),
            shadowRadius: girth * 1.9 + 0.25)
    }

    // MARK: - Attachments
    //
    // Every one of these is an ANCHOR, not a position. Nothing below computes where anything is; the
    // shader does that by evaluating the same surface the skin is drawn from.

    fileprivate func buildBlobs(_ s: Snapshot) {
        blobs.removeAll(keepingCapacity: true)
        let shape = s.shape

        // ── Legs ────────────────────────────────────────────────────────────────────────────
        //
        // **A lateral-sequence walk with a planted stance**, which is the gait a pig actually uses
        // and is worth spelling out because the first version got all three parts wrong.
        //
        //  * **The foot is planted, not swept.** For `dutyFactor` of the cycle the foot is on the
        //    ground, and its position in the pig's own frame slides backward at exactly the rate the
        //    pig moves forward — so it stays put on the field. That is only possible because the
        //    stride is the same number the engine advances the phase with: `stride × duty` of travel
        //    against a `2 × amplitude` excursion. Get those two out of step and every foot skates,
        //    which is what a 1.37 m stride and a 0.22 m swing were doing.
        //  * **Lateral sequence**, not a diagonal trot: rear-left, front-left, rear-right, front-right
        //    at quarter-cycle offsets. A trot is a running gait, and it read as a bouncing toy.
        //  * **Duty above a half**, so two or three feet are always down. That is what makes a fat pig
        //    look heavy rather than springy.
        // The cycle itself is `Engine/WalkCycle.swift` — the renderer places what it is told and
        // proves nothing. `WalkCycleTests` is where "a planted foot does not move" is asserted, and
        // it can only be asserted there because the arithmetic is not in here.
        let cycle = WalkCycle(fat: Double(s.fat), in: config)

        // Folded away below a walking pace so a pig easing to a stop settles onto its feet instead of
        // marching on the spot.
        let speedFactor = min(1, s.speed / Float(config.maxSpeed(atFat: Double(s.fat))) * 3)

        // Hips, paired with the phase offset each foot leaves the ground at. The order IS the gait:
        // rear-left, front-left, rear-right, front-right — a lateral sequence, not a diagonal trot.
        let hips: [(u: Float, v: Float)] = [
            (0.795, 0.615),             // rear left
            (0.345, 0.615),             // front left
            (0.795, 0.885),             // rear right
            (0.345, 0.885),             // front right
        ]
        for (leg, offset) in zip(hips, WalkCycle.phaseOffsets) {
            let step = cycle.foot(at: Double(s.gait) / (2 * .pi) + offset)
            let reach = Float(step.reach) * speedFactor
            let lift = Float(step.lift) * speedFactor

            blobs.append(Blob(
                anchor: SIMD4(leg.u, leg.v, 0, 1),
                offset: SIMD4(0, 0, 0, 0),
                // Tapered toward the hoof: thicker at the hip is what reads as a haunch.
                scale: SIMD4(Float(shape.legRadius), 0, Float(shape.legRadius), 1.35),
                rot: SIMD4(lift, 0, reach, 1),
                color: SIMD4(Palette.pig * 0.97, 0.05)))
            // The hoof: a dark cap at the foot, wherever the walk cycle put it. A non-zero `scale.y`
            // is what tells the shader this is a foot rather than the leg itself.
            let hoof = Float(shape.legRadius) * 0.9
            blobs.append(Blob(
                anchor: SIMD4(leg.u, leg.v, 0, 1),
                offset: SIMD4(0, 0, 0, 0),
                scale: SIMD4(Float(shape.legRadius) * 1.16, hoof, Float(shape.legRadius) * 1.16, 1.0),
                rot: SIMD4(lift, 0, reach, 1),
                color: SIMD4(Palette.hoof, 0.15)))
        }

        // ── Ears ────────────────────────────────────────────────────────────────────────────
        //
        // Flopped back, and they flick with the walk. Anchored on the head's surface, so a head that
        // has just widened carries them outward with it.
        let ear = Float(shape.earScale)
        let flick = sin(s.gait * 2) * 0.12 * speedFactor
        for side in [(v: Float(0.155), sign: Float(1)), (v: Float(0.345), sign: Float(-1))] {
            blobs.append(Blob(
                anchor: SIMD4(0.185, side.v, 0, 1),
                offset: SIMD4(0, ear * 0.55, 0, 0),
                scale: SIMD4(ear * 0.60, ear * 0.85, ear * 0.30, 1.9),
                rot: SIMD4(-0.55 + flick * side.sign, 0, side.sign * 0.35, 0),
                color: SIMD4(Palette.ear, 0.05)))
        }

        // ── Eyes ────────────────────────────────────────────────────────────────────────────
        //
        // They go wide when the dog is close. The only piece of state the face has, and it is read
        // from the engine's distance rather than from a flag the renderer keeps.
        let alarm = s.dogActive ? max(0, min(1, (7 - s.dogDistance) / 5)) : 0
        let eyeR = Float(0.021 + 0.005 * s.fat) * (1 + 0.45 * alarm)
        for v in [Float(0.128), Float(0.372)] {
            blobs.append(Blob(
                anchor: SIMD4(0.118, v, 0, 1),
                offset: SIMD4(0, eyeR * 0.35, 0, 0),
                scale: SIMD4(eyeR, eyeR, eyeR, 1.0),
                rot: SIMD4(0, 0, 0, 0),
                color: SIMD4(Palette.eye, 0.9)))
        }

        // ── Snout ───────────────────────────────────────────────────────────────────────────
        //
        // Anchored on the CENTRE LINE at u = 0, which is exactly the tip of the nose because the cap
        // closes the tube there — so the disc needs no knowledge of the current snout radius.
        let sn = Float(shape.snout)
        let chewBob = s.eating ? abs(sin(s.time * 14)) * 0.012 : 0
        blobs.append(Blob(
            anchor: SIMD4(0, 0, 0, 2),
            offset: SIMD4(0, -sn * 0.06 - chewBob, sn * 0.42, 0),
            scale: SIMD4(sn * 1.45, sn * 1.15, sn * 0.52, 1.0),
            rot: SIMD4(0, 0, 0, 0),
            color: SIMD4(Palette.snout, 0.25)))
        for side in [Float(-1), Float(1)] {
            blobs.append(Blob(
                anchor: SIMD4(0, 0, 0, 2),
                offset: SIMD4(side * sn * 0.50, -sn * 0.06 - chewBob, sn * 0.82, 0),
                scale: SIMD4(sn * 0.22, sn * 0.28, sn * 0.18, 1.0),
                rot: SIMD4(0, 0, 0, 0),
                color: SIMD4(Palette.nostril, 0.1)))
        }

        // ── Tail ────────────────────────────────────────────────────────────────────────────
        //
        // A corkscrew: beads along an axis pointing up and back from the rump tip, each offset around
        // it. Spaced closer than their own radius so the beads read as one curl rather than as six
        // spheres — the first attempt spaced them by eye and produced a dotted line floating behind
        // the pig.
        let wag = sin(s.time * (3 + 5 * s.fat)) * (0.3 + 0.5 * s.fat)
        let axis = SIMD3<Float>(0, 0.58, -0.81)
        let perpA = SIMD3<Float>(1, 0, 0)
        let perpB = SIMD3<Float>(0, 0.81, 0.58)
        let root = SIMD3<Float>(0, Float(shape.tailBase) * 0.55, -0.015)
        for i in 0..<6 {
            let f = Float(i)
            let a = f * 1.25 + wag
            let p = root + axis * (f * 0.030)
                + perpA * (cos(a) * 0.042) + perpB * (sin(a) * 0.042)
            blobs.append(Blob(
                anchor: SIMD4(1, 0, 0, 2),
                offset: SIMD4(p.x, p.y, p.z, 0),
                scale: SIMD4(0.026 - f * 0.0015, 0.026 - f * 0.0015, 0.026 - f * 0.0015, 1.0),
                rot: SIMD4(0, 0, 0, 0),
                color: SIMD4(Palette.pig * 0.95, 0.05)))
        }

        buildDrops(s)
        buildDog(s)

        if blobs.count > Renderer.maxBlobs { blobs.removeLast(blobs.count - Renderer.maxBlobs) }
    }

    /// What the pig left behind, at whatever stage of becoming lunch it has reached.
    ///
    /// One slot draws one of two things depending on `ripeness`, which is the engine's number and not
    /// a threshold invented here — so nothing can look edible a second before it is.
    private func buildDrops(_ s: Snapshot) {
        for i in 0..<s.dropAlive.count where s.dropAlive[i] > 0.5 {
            let x = Float(s.dropX[i]), z = Float(s.dropZ[i])
            let ripe = Float(s.dropRipeness[i])
            let look = Float(s.dropLook[i])
            let r = Float(s.dropRadius[i])

            if ripe < 1 {
                // A dropping, with a shoot coming out of it. The shoot IS the timer: by the time it
                // is a hand tall the carrot is ready, so the player never has to watch a clock.
                let squat = 1 - 0.35 * ripe                     // it sinks as the shoot takes over
                blobs.append(Blob(
                    anchor: SIMD4(x, 0, z, 0),
                    offset: SIMD4(0, r * 0.30 * squat, 0, 0),
                    scale: SIMD4(r * 0.95, r * 0.62 * squat, r * 0.95, 1.0),
                    rot: SIMD4(0, look * 3, 0, 0),
                    color: SIMD4(Palette.dung, 0.08)))
                blobs.append(Blob(
                    anchor: SIMD4(x, 0, z, 0),
                    offset: SIMD4(cos(look * 6) * r * 0.42, r * 0.22 * squat, sin(look * 6) * r * 0.42, 0),
                    scale: SIMD4(r * 0.55, r * 0.42 * squat, r * 0.55, 1.0),
                    rot: SIMD4(0, 0, 0, 0),
                    color: SIMD4(Palette.dung * 0.88, 0.08)))
                if ripe > 0.25 {
                    let shoot = (ripe - 0.25) / 0.75
                    for leaf in 0..<3 {
                        let a = Float(leaf) * 2.09 + look * 6
                        blobs.append(Blob(
                            anchor: SIMD4(x, 0, z, 0),
                            offset: SIMD4(cos(a) * 0.03 * shoot,
                                          r * 0.35 + 0.13 * shoot,
                                          sin(a) * 0.03 * shoot, 0),
                            scale: SIMD4(0.022, 0.10 * shoot, 0.022, 0.25),
                            rot: SIMD4(cos(a) * 0.35, 0, sin(a) * 0.35, 0),
                            color: SIMD4(Palette.leaf, 0.10)))
                    }
                }
            } else {
                // A carrot: a cone standing point-down in the soil, with a tuft on top. It shortens
                // as it is eaten, so a half-finished patch reads at a glance.
                let full = max(0.15, Float(s.dropFullness[i]))
                let height = 0.30 * full
                blobs.append(Blob(
                    anchor: SIMD4(x, 0, z, 0),
                    offset: SIMD4(0, height * 0.45, 0, 0),
                    scale: SIMD4(r * 0.75, height * 0.62, r * 0.75, 0.18),
                    rot: SIMD4(0, look * 3, 0, 0),
                    color: SIMD4(Palette.carrot, 0.25)))
                for leaf in 0..<4 {
                    let a = Float(leaf) * 1.57 + look * 6
                    blobs.append(Blob(
                        anchor: SIMD4(x, 0, z, 0),
                        offset: SIMD4(cos(a) * 0.045, height * 1.05, sin(a) * 0.045, 0),
                        scale: SIMD4(0.022, 0.085, 0.022, 0.3),
                        rot: SIMD4(cos(a) * 0.55, 0, sin(a) * 0.55, 0),
                        color: SIMD4(Palette.leaf, 0.10)))
                }
            }
        }
    }

    /// The dog, as world-anchored blobs.
    ///
    /// It is NOT welded to a surface the way the pig's parts are, so every offset here is rotated by
    /// its heading on the way in. That is the price of not giving it its own `pigPoint`; it is a prop
    /// with one pose, and the pig is the thing this engine is about.
    private func buildDog(_ s: Snapshot) {
        guard s.dogActive else { return }
        let yaw = s.dogHeading
        let cy = cos(yaw), sy = sin(yaw)

        func place(_ local: SIMD3<Float>, _ scale: SIMD3<Float>, taper: Float = 1,
                   pitch: Float = 0, color: SIMD3<Float>, gloss: Float = 0.08) {
            // Local +z is the dog's nose. Rotating here rather than in the shader keeps the free-blob
            // path free of a frame it would need for this one prop.
            let world = SIMD3<Float>(local.x * cy + local.z * sy,
                                     local.y,
                                     -local.x * sy + local.z * cy)
            blobs.append(Blob(
                anchor: SIMD4(s.dogX, 0, s.dogZ, 0),
                offset: SIMD4(world.x, world.y, world.z, 0),
                scale: SIMD4(scale.x, scale.y, scale.z, taper),
                rot: SIMD4(pitch, yaw, 0, 0),
                color: SIMD4(color, gloss)))
        }

        let bound = sin(s.dogGait) * 0.05          // a gallop, not a walk
        place(SIMD3(0, 0.40 + bound, 0), SIMD3(0.15, 0.15, 0.27), color: Palette.dog)
        place(SIMD3(0, 0.46 + bound, 0.30), SIMD3(0.12, 0.11, 0.13), color: Palette.dog)
        place(SIMD3(0, 0.43 + bound, 0.42), SIMD3(0.06, 0.055, 0.08), color: Palette.dogSnout)
        for side in [Float(-1), Float(1)] {
            place(SIMD3(side * 0.075, 0.56 + bound, 0.27), SIMD3(0.035, 0.07, 0.02),
                  taper: 1.6, pitch: -0.3, color: Palette.dog)
            place(SIMD3(side * 0.045, 0.47 + bound, 0.39), SIMD3(0.016, 0.016, 0.016),
                  color: Palette.eye, gloss: 0.9)
        }
        // Four legs on a bounding gait: fronts together, backs together, half a cycle apart.
        for leg in [(x: Float(-0.09), z: Float(0.16), phase: Float(0)),
                    (x: Float(0.09), z: Float(0.16), phase: Float(0)),
                    (x: Float(-0.09), z: Float(-0.17), phase: Float.pi),
                    (x: Float(0.09), z: Float(-0.17), phase: Float.pi)] {
            let p = s.dogGait + leg.phase
            place(SIMD3(leg.x, 0.19 + bound + max(0, sin(p)) * 0.06, leg.z + cos(p) * 0.05),
                  SIMD3(0.035, 0.17, 0.035), taper: 0.7, color: Palette.dog)
        }
        place(SIMD3(0, 0.50 + bound, -0.30), SIMD3(0.03, 0.03, 0.14), taper: 0.6,
              pitch: 0.5, color: Palette.dog)
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * max(0, min(1, t))
    }
}

// MARK: - Matrices
//
// Right-handed, looking down −z, with a reversed-depth-free [0,1] clip range — the Metal convention.

extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self.init(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(t.x, t.y, t.z, 1))
    }

    init(rotationY a: Float) {
        let c = cos(a), s = sin(a)
        self.init(SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1))
    }

    init(rotationZ a: Float) {
        let c = cos(a), s = sin(a)
        self.init(SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
    }

    init(perspectiveFOV fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        self.init(SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0))
    }

    init(lookAt eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let f = normalize(target - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        self.init(SIMD4(s.x, u.x, -f.x, 0),
                  SIMD4(s.y, u.y, -f.y, 0),
                  SIMD4(s.z, u.z, -f.z, 0),
                  SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1))
    }
}

// MARK: - The icon
//
// The app icon is a frame of the game, rendered by the game's shader, from the same `PigShape` the
// player fattens. Drawing it by hand would start out slightly wrong and drift further with every
// tuning pass on the body; this cannot.

extension Renderer {

    /// Render one pig into a square PNG with a transparent background.
    ///
    /// The ground pass is skipped, which also removes the shadow — it is a term in the ground shader
    /// rather than a drawn quad, so there is nothing to switch off separately.
    @discardableResult
    func writeIcon(size: Int, snapshot s: Snapshot, to url: URL) -> Bool {
        // 3× supersampled and downsampled by Core Graphics. Cheaper to reason about than an MSAA
        // resolve target, and at 3072² it is visibly cleaner on the curved silhouette.
        let big = size * 3

        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: big, height: big, mipmapped: false)
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .shared
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: big, height: big, mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private

        guard let color = device.makeTexture(descriptor: colorDesc),
              let depth = device.makeTexture(descriptor: depthDesc),
              let buffer = queue.makeCommandBuffer() else { return false }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1

        snapshot = s
        aspect = 1
        var body = makeBody(s)
        var uniforms = makeIconUniforms(s)
        buildBlobs(s)

        guard let blobBuffer = device.makeBuffer(length: max(1, MemoryLayout<Blob>.stride * blobs.count),
                                                 options: .storageModeShared),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        blobBuffer.contents().copyMemory(from: blobs,
                                         byteCount: MemoryLayout<Blob>.stride * blobs.count)

        var bodyGrid = SIMD2<UInt32>(UInt32(Renderer.bodyRings), UInt32(Renderer.bodySegments))
        var sphereGrid = SIMD2<UInt32>(UInt32(Renderer.sphereRings), UInt32(Renderer.sphereSegments))

        enc.setDepthStencilState(depthState)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setVertexBytes(&body, length: MemoryLayout<Body>.stride, index: 2)
        enc.setFragmentBytes(&body, length: MemoryLayout<Body>.stride, index: 2)

        enc.setRenderPipelineState(bodyPipeline)
        enc.setVertexBytes(&bodyGrid, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 3)
        enc.setCullMode(.none)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: bodyIndexCount, indexType: .uint16,
                                  indexBuffer: bodyIndices, indexBufferOffset: 0)

        if !blobs.isEmpty {
            enc.setRenderPipelineState(blobPipeline)
            enc.setVertexBuffer(blobBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&sphereGrid, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: sphereIndexCount,
                                      indexType: .uint16, indexBuffer: sphereIndices,
                                      indexBufferOffset: 0, instanceCount: blobs.count)
        }
        enc.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        return Renderer.writePNG(texture: color, downTo: size, at: url)
    }

    /// Icon framing: a three-quarter view from the front, so the snout and both ears read at 64 pt.
    private func makeIconUniforms(_ s: Snapshot) -> Uniforms {
        let yaw: Float = 2.46          // camera in front and to one side
        let pitch: Float = 0.30
        let distance = 1.48 + Float(s.shape.length) * 0.34

        let focus = SIMD3<Float>(s.x, Float(s.shape.stand) * 0.88, s.z)
        let eye = CameraFrame.eye(focus: focus, yaw: yaw, pitch: pitch, distance: distance)

        let view = float4x4(lookAt: eye, target: focus, up: SIMD3<Float>(0, 1, 0))
        let proj = float4x4(perspectiveFOV: 46 * .pi / 180, aspect: 1, near: 0.05, far: 40)

        return Uniforms(
            viewProjection: proj * view,
            cameraPosition: eye,
            time: s.time,
            lightDirection: normalize(SIMD3<Float>(0.42, 0.72, 0.72)),
            ambient: 0.60,
            fogColor: Palette.fog,
            fogDensity: 0,                       // no aerial perspective on a cut-out
            groundColor: Palette.ground,
            paddockRadius: Float(config.paddockRadius),
            shadowCenter: .zero,
            shadowRadius: 0)
    }

    private static func writePNG(texture: MTLTexture, downTo size: Int, at url: URL) -> Bool {
        let big = texture.width
        let rowBytes = big * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * big)
        pixels.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: rowBytes,
                             from: MTLRegionMake2D(0, 0, big, big), mipmapLevel: 0)
        }

        let space = CGColorSpaceCreateDeviceRGB()
        // The shader writes alpha 1 wherever it draws and the clear is transparent black, so the
        // buffer is already premultiplied — nothing to undo.
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let src = CGContext(data: &pixels, width: big, height: big, bitsPerComponent: 8,
                                  bytesPerRow: rowBytes, space: space, bitmapInfo: info.rawValue)?
            .makeImage() else { return false }

        guard let dst = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: info.rawValue)
        else { return false }
        dst.interpolationQuality = .high
        dst.draw(src, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let out = dst.makeImage(),
              let sink = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(sink, out, nil)
        return CGImageDestinationFinalize(sink)
    }
}
