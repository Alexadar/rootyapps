import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

/// The Metal renderer: a **read-only viewer** over engine state.
///
/// It runs no physics, owns no rules, and holds no game state beyond what it needs to draw a frame.
/// Everything it knows arrives as a `Snapshot`. Delete this whole directory and the Kits still run,
/// still test and still sweep — the property that keeps simulation and presentation from tangling,
/// and the reason chaos and jitter can live here safely without ever feeding back.
///
/// Structure is inherited from `citypigeon/CityPigeon/Render/Renderer.swift`: one instanced unit
/// primitive, triple buffering, flat shading. What is new is the full-screen relativistic pass that
/// draws the spacetime behind it.
final class Renderer: NSObject, MTKViewDelegate {

    /// Must match `struct Instance` in Shaders.metal exactly.
    /// `SIMD3<Float>` is 16-byte aligned with stride 16, which is why the Metal side uses `float3`
    /// and never `packed_float3` — a mismatch there shifts every colour and flag by four bytes.
    struct Instance {
        var center: SIMD3<Float>
        var halfExtent: SIMD3<Float>
        var color: SIMD4<Float>
        var flags: SIMD4<Float>
    }

    struct Uniforms {
        var viewProjection: float4x4
        var lightDirection: SIMD3<Float>
        var ambient: Float
        var fogColor: SIMD3<Float>
        var fogDensity: Float
    }

    /// Must match `struct Relativity` in Shaders.metal. Geometrized units throughout (G = c = M = 1),
    /// the same units RelativityKit works in, so nothing can be lost in a conversion between them.
    struct RelativityUniforms {
        var holeCenterNDC: SIMD2<Float> = .zero
        var spin: Float = 0.8
        var mass: Float = 1
        var outerHorizon: Float = 1.6
        var ergosphereEq: Float = 2
        var photonSphere: Float = 3
        var photonPrograde: Float = 3
        var photonRetro: Float = 3
        var lensStrength: Float = 0.045
        var bubbleRadiusNDC: Float = 0
        var observerRedshift: Float = 1
        var aspect: Float = 16.0 / 9.0
        var time: Float = 0
        // Shared camera. SIMD3<Float> has stride 16 and Metal's float3 matches; do not pack.
        var camEye = SIMD3<Float>(0, 2.5, 14)
        var camRight = SIMD3<Float>(1, 0, 0)
        var camUp = SIMD3<Float>(0, 1, 0)
        var camForward = SIMD3<Float>(0, 0, -1)
        var tanHalfFov: Float = 0.58
        /// RK4 steps per pixel in the geodesic pass. 256 at native resolution is ~5e8 steps/second
        /// on a phone at 60 fps, which thermally throttles an A16 in under a minute. Exposed as a
        /// control rather than a constant because the right value depends on the device.
        var integrationSteps: Float = 96
    }

    // MARK: - Metal objects

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var cubePipeline: MTLRenderPipelineState!
    private var relativisticPipeline: MTLRenderPipelineState!
    private var geodesicPipeline: MTLRenderPipelineState!
    private var portalPipeline: MTLRenderPipelineState!
    /// The through-portal view, rendered from the virtual camera before the main pass.
    private var portalTarget: MTLTexture?
    private var portalDepth: MTLTexture?
    private var portalSampler: MTLSamplerState!
    /// The geodesic pass renders HERE, at a fraction of native resolution, then blits up.
    ///
    /// It is a smooth background — no text, no thin geometry, nothing that needs a hard pixel edge —
    /// so rendering it at half resolution costs almost nothing visually and exactly 4x fewer
    /// fragment invocations. On a 2796x1290 panel that is 216M invocations a second down to 54M,
    /// and each invocation is up to 96 RK4 steps of a full inverse-metric evaluation. This is the
    /// single largest lever in the renderer and it is free.
    private var geoTarget: MTLTexture?
    private var blitPipeline: MTLRenderPipelineState!
    private var linearSampler: MTLSamplerState!
    /// 1.0 = native. 0.5 = quarter the fragments.
    var geodesicScale: Float = 0.5
    private var depthState: MTLDepthStencilState!

    /// Triple buffering, so the CPU can build frame N+1 while the GPU draws frame N without either
    /// waiting on the other or writing into a buffer still being read.
    private static let framesInFlight = 3
    private static let maxInstances = 4096
    private var instanceBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let inFlight = DispatchSemaphore(value: framesInFlight)

    // MARK: - Scene state, set from outside every frame; never mutated here

    var snapshot = Snapshot()
    var aspect: Float = 16.0 / 9.0
    private var instances: [Instance] = []
    /// Portal mouths, kept separate: they draw last, with their own pipeline, sampling the
    /// through-view. Mixing them into `instances` would draw them as opaque boxes.
    private var portalInstances: [Instance] = []
    private var paletteBuffer: MTLBuffer!

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        super.init()

        view.device = device
        // `.bgra8Unorm`, NOT `.bgra8Unorm_srgb`. Every colour in `Palette` was sampled straight out
        // of a PNG, so the values are already sRGB-encoded. An _srgb drawable would apply the
        // transfer function a second time: the first build rendered the void at 0.35 grey instead
        // of 0.099, because 0.099^(1/2.2) = 0.35, and a black hole scene came out lavender.
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        // Pin the layer's colour space to sRGB for the same reason — otherwise a wide-gamut display
        // reinterprets these as Display P3 and everything shifts.
        #if !targetEnvironment(simulator) || true
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.pixelFormat = .bgra8Unorm
        }
        #endif

        guard let library = device.makeDefaultLibrary() else { return nil }

        // Full-screen relativistic pass — Tier 1, screen-space.
        let relDesc = MTLRenderPipelineDescriptor()
        relDesc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        relDesc.fragmentFunction = library.makeFunction(name: "relativistic_fragment")
        relDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        relDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        // The geodesic pass — Tier 2, world-space. Integrates the real orbit equation per pixel.
        let geoDesc = MTLRenderPipelineDescriptor()
        geoDesc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        geoDesc.fragmentFunction = library.makeFunction(name: "geodesic_fragment")
        geoDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        geoDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        // Upscale blit for the reduced-resolution geodesic pass.
        let blitDesc = MTLRenderPipelineDescriptor()
        blitDesc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        blitDesc.fragmentFunction = library.makeFunction(name: "blit_fragment")
        blitDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        blitDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        // Portals — a quad sampling the through-view.
        let portalDesc = MTLRenderPipelineDescriptor()
        portalDesc.vertexFunction = library.makeFunction(name: "portal_vertex")
        portalDesc.fragmentFunction = library.makeFunction(name: "portal_fragment")
        portalDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        portalDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        // Instanced primitives.
        let cubeDesc = MTLRenderPipelineDescriptor()
        cubeDesc.vertexFunction = library.makeFunction(name: "cube_vertex")
        cubeDesc.fragmentFunction = library.makeFunction(name: "cube_fragment")
        cubeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        cubeDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        do {
            relativisticPipeline = try device.makeRenderPipelineState(descriptor: relDesc)
            geodesicPipeline = try device.makeRenderPipelineState(descriptor: geoDesc)
            portalPipeline = try device.makeRenderPipelineState(descriptor: portalDesc)
            blitPipeline = try device.makeRenderPipelineState(descriptor: blitDesc)
            cubePipeline = try device.makeRenderPipelineState(descriptor: cubeDesc)
        } catch {
            assertionFailure("pipeline creation failed: \(error)")
            return nil
        }

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        portalSampler = device.makeSamplerState(descriptor: sd)
        linearSampler = device.makeSamplerState(descriptor: sd)

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)

        // Unified memory on Apple silicon: `.storageModeShared` means the CPU write and the GPU
        // read touch the same pages, with no copy and no blit. That is why a per-frame rebuild of
        // the instance list costs essentially nothing here.
        for _ in 0..<Self.framesInFlight {
            guard let b = device.makeBuffer(length: MemoryLayout<Instance>.stride * Self.maxInstances,
                                            options: .storageModeShared) else { return nil }
            instanceBuffers.append(b)
        }

        // The palette goes to the GPU once. Order must match the indices the shader reads.
        var pal: [SIMD4<Float>] = [
            SIMD4(Palette.skyFar, 1), SIMD4(Palette.skyDeep, 1),
            SIMD4(Palette.horizon, 1), SIMD4(Palette.ergosphere, 1),
            SIMD4(Palette.bubbleWall, 1),
        ]
        pal += Palette.redshiftRamp.map { SIMD4($0, 1) }
        paletteBuffer = device.makeBuffer(bytes: pal,
                                          length: MemoryLayout<SIMD4<Float>>.stride * pal.count,
                                          options: .storageModeShared)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspect = size.height > 0 ? Float(size.width / size.height) : 1
        ensurePortalTargets(width: Int(size.width), height: Int(size.height),
                            format: view.colorPixelFormat)
    }

    /// Allocate the offscreen through-view at drawable resolution. Recreated only when the size
    /// actually changes — a per-frame allocation here would dominate the frame cost.
    private func ensurePortalTargets(width: Int, height: Int, format: MTLPixelFormat) {
        guard width > 0, height > 0 else { return }
        if let t = portalTarget, t.width == width, t.height == height { return }
        let c = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                         height: height, mipmapped: false)
        c.usage = [.renderTarget, .shaderRead]
        c.storageMode = .private
        portalTarget = device.makeTexture(descriptor: c)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width,
                                                         height: height, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        portalDepth = device.makeTexture(descriptor: d)

        let gw = max(Int(Float(width) * geodesicScale), 64)
        let gh = max(Int(Float(height) * geodesicScale), 64)
        let gd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: gw,
                                                          height: gh, mipmapped: false)
        gd.usage = [.renderTarget, .shaderRead]
        gd.storageMode = .private
        geoTarget = device.makeTexture(descriptor: gd)
    }

    /// Encode sky + primitives for one camera. Shared by the through-view and the main pass, so
    /// the two cannot drift apart — the whole point of a portal is that the far side is the same
    /// world seen from elsewhere.
    /// Fill `rel` with the camera basis for whichever camera this pass uses.
    private func relativityUniforms(for camera: Snapshot.Camera) -> RelativityUniforms {
        var rel = snapshot.relativity
        rel.aspect = aspect
        let fwd = simd_normalize(camera.target - camera.eye)
        let right = simd_normalize(simd_cross(fwd, SIMD3<Float>(0, 1, 0)))
        rel.camEye = camera.eye
        rel.camForward = fwd
        rel.camRight = right
        rel.camUp = simd_cross(right, fwd)
        rel.tanHalfFov = tan(camera.fovRadians * 0.5)
        return rel
    }

    /// The spacetime pass, rendered into `geoTarget` at reduced resolution.
    private func encodeSky(_ encoder: MTLRenderCommandEncoder, camera: Snapshot.Camera) {
        var rel = relativityUniforms(for: camera)
        encoder.setRenderPipelineState(snapshot.usesGeodesicPass ? geodesicPipeline
                                                                 : relativisticPipeline)
        encoder.setFragmentBytes(&rel, length: MemoryLayout<RelativityUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private func encodeScene(_ encoder: MTLRenderCommandEncoder, camera: Snapshot.Camera,
                             instanceCount: Int, buffer: MTLBuffer) {
        var rel = relativityUniforms(for: camera)
        if let sky = geoTarget {
            // Upscale the pass rendered at `geodesicScale`. One texture fetch per pixel instead of
            // ~38,000 floating-point operations per pixel, which is the whole saving.
            encoder.setRenderPipelineState(blitPipeline)
            encoder.setFragmentTexture(sky, index: 0)
            encoder.setFragmentSamplerState(linearSampler, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        } else {
            encoder.setRenderPipelineState(snapshot.usesGeodesicPass ? geodesicPipeline
                                                                     : relativisticPipeline)
            encoder.setFragmentBytes(&rel, length: MemoryLayout<RelativityUniforms>.stride, index: 0)
            encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        guard instanceCount > 0 else { return }
        var uniforms = makeUniforms(camera: camera)
        encoder.setRenderPipelineState(cubePipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        for face in 0..<6 {
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: face * 4,
                                   vertexCount: 4, instanceCount: instanceCount)
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        inFlight.wait()
        commandBuffer.addCompletedHandler { [inFlight] _ in inFlight.signal() }
        frameIndex = (frameIndex + 1) % Self.framesInFlight

        // Build the frame's geometry once. Both passes draw the SAME instance buffer — the far
        // side of a portal is this world seen from elsewhere, not a different world, and sharing
        // the buffer is what makes that true by construction rather than by discipline.
        buildInstances()
        let buffer = instanceBuffers[frameIndex]
        let solidCount = min(instances.count, Self.maxInstances)
        if solidCount > 0 {
            buffer.contents().withMemoryRebound(to: Instance.self, capacity: solidCount) { p in
                for i in 0..<solidCount { p[i] = instances[i] }
            }
        }

        // ── Pass 0: spacetime, at reduced resolution ─────────────────────────────────────────
        if let sky = geoTarget {
            let sd = MTLRenderPassDescriptor()
            sd.colorAttachments[0].texture = sky
            sd.colorAttachments[0].loadAction = .dontCare
            sd.colorAttachments[0].storeAction = .store
            if let e = commandBuffer.makeRenderCommandEncoder(descriptor: sd) {
                encodeSky(e, camera: snapshot.camera)
                e.endEncoding()
            }
        }

        // ── Pass A: the through-portal view, from the virtual camera ─────────────────────────
        //
        // Rendered before the main pass and into an offscreen target, so the portal quad can
        // simply sample it at its own screen position. One level of recursion; a second level
        // means ping-ponging two targets, which the allocation above is already shaped for.
        ensurePortalTargets(width: Int(view.drawableSize.width),
                            height: Int(view.drawableSize.height),
                            format: view.colorPixelFormat)
        if snapshot.hasPortals, let target = portalTarget, let pDepth = portalDepth,
           let virtualCamera = snapshot.portalVirtualCamera {
            let pd = MTLRenderPassDescriptor()
            pd.colorAttachments[0].texture = target
            pd.colorAttachments[0].loadAction = .clear
            pd.colorAttachments[0].storeAction = .store
            pd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            pd.depthAttachment.texture = pDepth
            pd.depthAttachment.loadAction = .clear
            pd.depthAttachment.storeAction = .dontCare
            pd.depthAttachment.clearDepth = 1.0
            if let through = commandBuffer.makeRenderCommandEncoder(descriptor: pd) {
                encodeScene(through, camera: virtualCamera,
                            instanceCount: solidCount, buffer: buffer)
                through.endEncoding()
            }
        }

        // ── Pass B: the real view ────────────────────────────────────────────────────────────
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            inFlight.signal()
            return
        }
        encodeScene(encoder, camera: snapshot.camera, instanceCount: solidCount, buffer: buffer)

        // Portal mouths last, sampling the through-view.
        if !portalInstances.isEmpty, let target = portalTarget {
            let pbuf = instanceBuffers[(frameIndex + 1) % Self.framesInFlight]
            let count = min(portalInstances.count, Self.maxInstances)
            pbuf.contents().withMemoryRebound(to: Instance.self, capacity: count) { p in
                for i in 0..<count { p[i] = portalInstances[i] }
            }
            var uniforms = makeUniforms(camera: snapshot.camera)
            encoder.setRenderPipelineState(portalPipeline)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(pbuf, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(target, index: 0)
            encoder.setFragmentSamplerState(portalSampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                   vertexCount: 4, instanceCount: count)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeUniforms(camera: Snapshot.Camera) -> Uniforms {
        let view = float4x4.lookAt(eye: camera.eye, center: camera.target, up: SIMD3(0, 1, 0))
        let proj = float4x4.perspective(fovyRadians: camera.fovRadians, aspect: aspect,
                                        near: 0.05, far: 400)
        return Uniforms(viewProjection: proj * view,
                        lightDirection: normalize(SIMD3(0.4, 0.8, 0.45)),
                        ambient: 0.34,
                        fogColor: Palette.skyDeep,
                        fogDensity: 0)
    }

    private func buildInstances() {
        instances.removeAll(keepingCapacity: true)
        portalInstances.removeAll(keepingCapacity: true)
        for body in snapshot.bodies {
            switch body.kind {
            case .cosmonaut:
                ProceduralCosmonautRig.emit(into: &instances, at: body.position,
                                            scale: body.scale, yaw: body.yaw)
            case .cat:
                ProceduralCatRig.emit(into: &instances, at: body.position,
                                      scale: body.scale, yaw: body.yaw)
            case .marker:
                instances.append(Instance(center: body.position,
                                          halfExtent: SIMD3(repeating: body.scale),
                                          color: SIMD4(body.color, 1),
                                          flags: SIMD4(body.emissive, 0, 0, 0)))
            case .portal:
                portalInstances.append(Instance(center: body.position,
                                                halfExtent: SIMD3(body.scale, body.scale * 1.5, 0),
                                                color: SIMD4(body.color, 1),
                                                flags: SIMD4(body.emissive, 0, 0, 0)))
            }
        }
    }
}

// MARK: - Matrix helpers

extension float4x4 {
    static func perspective(fovyRadians fovy: Float, aspect: Float,
                            near: Float, far: Float) -> float4x4 {
        let y = 1 / tan(fovy * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return float4x4(columns: (SIMD4(x, 0, 0, 0),
                                  SIMD4(0, y, 0, 0),
                                  SIMD4(0, 0, z, -1),
                                  SIMD4(0, 0, z * near, 0)))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        return float4x4(columns: (SIMD4(s.x, u.x, -f.x, 0),
                                  SIMD4(s.y, u.y, -f.y, 0),
                                  SIMD4(s.z, u.z, -f.z, 0),
                                  SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)))
    }
}
