import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO

// Real-sprite Metal renderer: loads the actual game art (monster Walk animation frames, player,
// bullet PNGs from Assets.xcassets) into a 2D texture array and draws textured instanced quads —
// the real sprite game on Metal, not debug circles. One slice per frame; per-instance picks the slice.

struct SpriteInstance {
    var pos = SIMD2<Float>(0, 0)
    var rot: Float = 0
    var size: Float = 0          // half-extent in world units (<=0 -> culled)
    var slice: UInt32 = 0
    var pad: UInt32 = 0
}

private let spriteShaders = """
#include <metal_stdlib>
using namespace metal;
struct Inst { float2 pos; float rot; float size; uint slice; uint pad; };
struct VOut { float4 position [[position]]; float2 uv; uint slice; };
vertex VOut spr_v(uint vid [[vertex_id]], uint iid [[instance_id]], const device Inst* inst [[buffer(0)]],
                  constant float2& camCenter [[buffer(1)]], constant float2& camHalf [[buffer(2)]]) {
    float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 uvs[4] = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };   // v-flip: image upright
    Inst e = inst[iid]; VOut o; o.slice = e.slice;
    if (e.size <= 0.0) { o.position = float4(2,2,2,1); o.uv = float2(0); return o; }
    float c = cos(e.rot), s = sin(e.rot);
    float2 cor = corners[vid] * e.size;
    float2 r = float2(cor.x * c - cor.y * s, cor.x * s + cor.y * c);
    float2 world = e.pos + r;
    o.position = float4((world - camCenter) / camHalf, 0, 1); o.uv = uvs[vid];
    return o;
}
fragment float4 spr_f(VOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float4 col = tex.sample(smp, in.uv, in.slice);
    if (col.a < 0.02) discard_fragment();
    return col;   // premultiplied
}
struct BgOut { float4 position [[position]]; float2 uv; };
vertex BgOut bg_v(uint vid [[vertex_id]], constant float2& camCenter [[buffer(0)]],
                  constant float2& camHalf [[buffer(1)]], constant float& tileWorld [[buffer(2)]]) {
    float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 c = corners[vid]; BgOut o;
    o.position = float4(c, 0, 1);
    o.uv = (camCenter + c * camHalf) / tileWorld;     // world->tile UV (scrolls + repeats)
    return o;
}
fragment float4 bg_f(BgOut in [[stage_in]], texture2d<float> bg [[texture(0)]]) {
    constexpr sampler smp(filter::linear, address::repeat);
    return bg.sample(smp, in.uv);
}
"""

private let SLICE = 96                            // common slice resolution

final class SpriteRenderer {
    let pso: MTLRenderPipelineState
    let tex: MTLTexture
    let instBuf: MTLBuffer
    let bgTex: MTLTexture
    let bgPSO: MTLRenderPipelineState
    var playerSlice: UInt32 = 0
    var bulletSlice: UInt32 = 0
    var typeBase: [Int: UInt32] = [:]
    var typeCount: [Int: Int] = [:]

    init(device: MTLDevice, assetsRoot: String, resourcesRoot: String, typeFolders: [Int: String],
         playerImage: String, playerCrop: [Int], typesInUse: [Int], maxInstances: Int) throws {
        let root = assetsRoot, res = resourcesRoot

        // slice 0 = player (exoskeleton atlas crop), slice 1 = bullet (yellow quad), then walk frames
        var slices: [[UInt8]] = []
        slices.append(SpriteRenderer.loadCrop("\(res)/\(playerImage)", playerCrop, SLICE)
                      ?? SpriteRenderer.solid(SLICE, 0.3, 0.9, 0.4))   // green-box fallback (matches game)
        slices.append(SpriteRenderer.loadResized("\(res)/weapons.png", SLICE)   // real bullet = weapons.png art
                      ?? SpriteRenderer.solid(SLICE, 1.0, 0.6, 0.2))
        playerSlice = 0; bulletSlice = 1
        var next: UInt32 = 2
        for tid in typesInUse {
            guard let folder = typeFolders[tid] else { continue }
            let frames = SpriteRenderer.walkFrames("\(root)/Monsters/\(folder)/Walk.spriteatlas")
            if frames.isEmpty { continue }
            typeBase[tid] = next; typeCount[tid] = frames.count
            for f in frames { slices.append(SpriteRenderer.loadResized(f, SLICE) ?? SpriteRenderer.solid(SLICE, 0.9, 0.3, 0.3)) }
            next += UInt32(frames.count)
        }

        let td = MTLTextureDescriptor()
        td.textureType = .type2DArray; td.pixelFormat = .rgba8Unorm
        td.width = SLICE; td.height = SLICE; td.arrayLength = max(slices.count, 1); td.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: td) else {
            throw NSError(domain: "sprite", code: 1, userInfo: [NSLocalizedDescriptionKey: "no texture"])
        }
        let region = MTLRegionMake2D(0, 0, SLICE, SLICE)
        for (i, px) in slices.enumerated() {
            px.withUnsafeBytes { texture.replace(region: region, mipmapLevel: 0, slice: i,
                                                 withBytes: $0.baseAddress!, bytesPerRow: SLICE * 4, bytesPerImage: SLICE * SLICE * 4) }
        }
        tex = texture

        let lib = try device.makeLibrary(source: spriteShaders, options: nil)
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = lib.makeFunction(name: "spr_v"); rpd.fragmentFunction = lib.makeFunction(name: "spr_f")
        let a = rpd.colorAttachments[0]!
        a.pixelFormat = .bgra8Unorm; a.isBlendingEnabled = true
        a.sourceRGBBlendFactor = .one; a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pso = try device.makeRenderPipelineState(descriptor: rpd)
        instBuf = device.makeBuffer(length: MemoryLayout<SpriteInstance>.stride * maxInstances, options: .storageModeShared)!

        // background floor (tiled map_background.png)
        bgTex = SpriteRenderer.loadTexture(device, "\(res)/map_background.png")
            ?? SpriteRenderer.solidTexture(device, 0.10, 0.11, 0.14)
        let bgrpd = MTLRenderPipelineDescriptor()
        bgrpd.vertexFunction = lib.makeFunction(name: "bg_v"); bgrpd.fragmentFunction = lib.makeFunction(name: "bg_f")
        bgrpd.colorAttachments[0]!.pixelFormat = .bgra8Unorm
        bgPSO = try device.makeRenderPipelineState(descriptor: bgrpd)
    }

    /// monster type -> slice for the current animation frame
    func monsterSlice(_ tid: Int, _ frame: Int) -> UInt32 {
        guard let base = typeBase[tid], let cnt = typeCount[tid], cnt > 0 else { return bulletSlice }
        return base + UInt32(frame % cnt)
    }

    /// one cell of a batched grid: a viewport rectangle + its own camera + its slice of the instance buffer
    struct GridCell {
        var x, y, w, h: Double
        var camCenter: SIMD2<Float>, camHalf: SIMD2<Float>
        var start: Int, count: Int
    }

    /// Abstract batched render layer: draw N games, each into its own viewport with its own camera, from
    /// ONE concatenated instance buffer. The live game is just this with a single full-screen cell (N=1).
    func encodeGrid(into cmd: MTLCommandBuffer, rp: MTLRenderPassDescriptor, instances: [SpriteInstance], cells: [GridCell]) {
        if !instances.isEmpty {
            let ptr = instBuf.contents().bindMemory(to: SpriteInstance.self, capacity: instances.count)
            for (i, e) in instances.enumerated() { ptr[i] = e }
        }
        var tw: Float = 512
        let e = cmd.makeRenderCommandEncoder(descriptor: rp)!
        for c in cells {
            e.setViewport(MTLViewport(originX: c.x, originY: c.y, width: c.w, height: c.h, znear: 0, zfar: 1))
            var cc = c.camCenter, ch = c.camHalf
            e.setRenderPipelineState(bgPSO)
            e.setVertexBytes(&cc, length: 8, index: 0); e.setVertexBytes(&ch, length: 8, index: 1)
            e.setVertexBytes(&tw, length: 4, index: 2); e.setFragmentTexture(bgTex, index: 0)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            if c.count > 0 {
                e.setRenderPipelineState(pso)
                e.setVertexBuffer(instBuf, offset: c.start * MemoryLayout<SpriteInstance>.stride, index: 0)
                e.setVertexBytes(&cc, length: 8, index: 1); e.setVertexBytes(&ch, length: 8, index: 2)
                e.setFragmentTexture(tex, index: 0)
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: c.count)
            }
        }
        e.endEncoding()
    }

    func encode(into cmd: MTLCommandBuffer, rp: MTLRenderPassDescriptor, instances: [SpriteInstance],
                camCenter: SIMD2<Float>, camHalf: SIMD2<Float>) {
        let ptr = instBuf.contents().bindMemory(to: SpriteInstance.self, capacity: instances.count)
        for (i, e) in instances.enumerated() { ptr[i] = e }
        var cc = camCenter, ch = camHalf, tw: Float = 512
        let e = cmd.makeRenderCommandEncoder(descriptor: rp)!
        // 1) tiled floor
        e.setRenderPipelineState(bgPSO)
        e.setVertexBytes(&cc, length: 8, index: 0); e.setVertexBytes(&ch, length: 8, index: 1)
        e.setVertexBytes(&tw, length: 4, index: 2); e.setFragmentTexture(bgTex, index: 0)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        // 2) sprites on top
        e.setRenderPipelineState(pso)
        e.setVertexBuffer(instBuf, offset: 0, index: 0)
        e.setVertexBytes(&cc, length: 8, index: 1); e.setVertexBytes(&ch, length: 8, index: 2)
        e.setFragmentTexture(tex, index: 0)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
        e.endEncoding()
    }

    // ---- asset loading ----
    static func walkFrames(_ dir: String) -> [String] {
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [String] = []
        for s in subs.sorted() where s.hasSuffix(".imageset") {
            let base = String(s.dropLast(".imageset".count))
            let p = "\(dir)/\(s)/\(base).png"
            if fm.fileExists(atPath: p) { out.append(p) }
        }
        return out
    }

    /// crop a sub-rect (x,y,w,h from top-left, atlas coords) out of an image, fit into SxS
    static func loadCrop(_ path: String, _ crop: [Int], _ S: Int) -> [UInt8]? {
        guard crop.count == 4,
              let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let sub = img.cropping(to: CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3])) ?? img
        var data = [UInt8](repeating: 0, count: S * S * 4)
        guard let ctx = CGContext(data: &data, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(sub, in: CGRect(x: 0, y: 0, width: S, height: S))
        return data
    }

    /// load a full-resolution PNG into a 2D texture (for the tiled floor)
    static func loadTexture(_ device: MTLDevice, _ path: String) -> MTLTexture? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        td.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: td) else { return nil }
        data.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w * 4) }
        return t
    }

    static func solidTexture(_ device: MTLDevice, _ r: Float, _ g: Float, _ b: Float) -> MTLTexture {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        td.usage = .shaderRead
        let t = device.makeTexture(descriptor: td)!
        var px = SpriteRenderer.solid(4, r, g, b)
        px.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 16) }
        return t
    }

    /// a solid premultiplied-RGBA slice (for the bullet quad / fallbacks)
    static func solid(_ S: Int, _ r: Float, _ g: Float, _ b: Float) -> [UInt8] {
        var d = [UInt8](repeating: 0, count: S * S * 4)
        let R = UInt8(r * 255), G = UInt8(g * 255), B = UInt8(b * 255)
        for i in 0..<(S * S) { d[i * 4] = R; d[i * 4 + 1] = G; d[i * 4 + 2] = B; d[i * 4 + 3] = 255 }
        return d
    }

    static func loadResized(_ path: String, _ S: Int) -> [UInt8]? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        var data = [UInt8](repeating: 0, count: S * S * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &data, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: S, height: S))
        return data
    }
}
