import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO

// Track A — GPU-driven sprite rendering (no SpriteKit).
// World state lives in ONE MTLBuffer; a compute kernel ticks it; ONE instanced draw renders every
// entity (vertex shader reads its position straight from the buffer, applies the camera transform —
// the matmul — and the fragment shader paints a sprite). Headless: renders to a texture and writes a
// PNG so the architecture is verifiable without a window. The live MTKView game is the same path
// presenting to screen instead of a texture.

// Entity struct — must match the Metal layout exactly (all 4-byte fields, stride 24).
struct Entity {
    var px: Float, py: Float, vx: Float, vy: Float
    var type: UInt32, alive: UInt32
}

let shaderSrc = """
#include <metal_stdlib>
using namespace metal;
struct Entity { float px; float py; float vx; float vy; uint type; uint alive; };

// THE TICK — runs entirely on the GPU, in place, over the state buffer.
kernel void tick(device Entity* ents [[buffer(0)]],
                 constant float& dt [[buffer(1)]],
                 constant float2& center [[buffer(2)]],
                 constant uint& count [[buffer(3)]],
                 uint id [[thread_position_in_grid]]) {
    if (id >= count) return;
    Entity e = ents[id];
    if (e.alive == 0u || e.type == 255u) return;          // dead or player: skip
    float2 p = float2(e.px, e.py);
    float2 d = center - p;
    float dist = max(length(d), 1e-3);
    float speed = 90.0 + float(e.type) * 40.0;            // type-specific speed -> natural variety
    float2 v = d / dist * speed;
    p += v * dt;
    e.px = p.x; e.py = p.y; e.vx = v.x; e.vy = v.y;
    ents[id] = e;
}

struct VOut { float4 position [[position]]; float2 uv; uint type; };

// THE RENDER — one instanced draw; each instance reads its entity straight from the buffer.
vertex VOut v_main(uint vid [[vertex_id]], uint iid [[instance_id]],
                   const device Entity* ents [[buffer(0)]],
                   constant float2& worldHalf [[buffer(1)]],
                   constant float& sprite [[buffer(2)]]) {
    float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 c = corners[vid];
    Entity e = ents[iid];
    VOut o; o.uv = c; o.type = e.type;
    if (e.alive == 0u) { o.position = float4(2,2,2,1); return o; }   // cull dead off-screen
    float ts = (e.type == 255u) ? 4.0 : (1.0 + 0.45 * float(e.type));
    float2 world = float2(e.px, e.py) + c * (sprite * ts);
    o.position = float4(world / worldHalf, 0, 1);          // world -> NDC (the camera matmul)
    return o;
}

fragment float4 f_main(VOut in [[stage_in]]) {
    float r = length(in.uv);
    if (r > 1.0) discard_fragment();
    float3 pal[5] = { float3(0.95,0.35,0.25), float3(0.30,0.70,0.95),
                      float3(0.55,0.90,0.45), float3(0.95,0.82,0.30), float3(0.80,0.45,0.95) };
    float3 col = (in.type == 255u) ? float3(1.0) : pal[in.type % 5u];
    float a = smoothstep(1.0, 0.6, r);                    // soft round sprite
    return float4(col, 1.0) * a;                          // premultiplied
}
"""

// MARK: - args
func arg(_ k: String, _ d: Int) -> Int { CommandLine.arguments.firstIndex(of: "--\(k)").flatMap { Int(CommandLine.arguments[$0 + 1]) } ?? d }
func argS(_ k: String, _ d: String) -> String { CommandLine.arguments.firstIndex(of: "--\(k)").map { CommandLine.arguments[$0 + 1] } ?? d }
let N = arg("count", 100_000)
let ticks = arg("ticks", 40)
let size = arg("size", 1400)
let outPath = argS("out", "render.png")
let worldHalf = SIMD2<Float>(1000, 1000)
let sprite: Float = 4.0

// MARK: - Metal setup
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fputs("no Metal device\n", stderr); exit(1)
}
let lib = try device.makeLibrary(source: shaderSrc, options: nil)
let tickPSO = try device.makeComputePipelineState(function: lib.makeFunction(name: "tick")!)

let rpd = MTLRenderPipelineDescriptor()
rpd.vertexFunction = lib.makeFunction(name: "v_main")
rpd.fragmentFunction = lib.makeFunction(name: "f_main")
let att = rpd.colorAttachments[0]!
att.pixelFormat = .bgra8Unorm
att.isBlendingEnabled = true                              // premultiplied-alpha over
att.rgbBlendOperation = .add; att.alphaBlendOperation = .add
att.sourceRGBBlendFactor = .one; att.sourceAlphaBlendFactor = .one
att.destinationRGBBlendFactor = .oneMinusSourceAlpha; att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
let renderPSO = try device.makeRenderPipelineState(descriptor: rpd)

// MARK: - world state buffer (the "matrix")
var rng = SystemRandomNumberGenerator()
var ents = [Entity]()
ents.reserveCapacity(N)
ents.append(Entity(px: 0, py: 0, vx: 0, vy: 0, type: 255, alive: 1))   // player at center
for _ in 1..<N {
    let ang = Float.random(in: 0..<(2 * .pi), using: &rng)
    let rad = Float.random(in: 300..<980, using: &rng)
    ents.append(Entity(px: cos(ang) * rad, py: sin(ang) * rad, vx: 0, vy: 0,
                       type: UInt32.random(in: 0...4, using: &rng), alive: 1))
}
let entBuf = device.makeBuffer(bytes: ents, length: MemoryLayout<Entity>.stride * N, options: .storageModeShared)!

// MARK: - render target
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
let tex = device.makeTexture(descriptor: td)!

// MARK: - encode: K compute ticks, then ONE instanced draw
var dt: Float = 1.0 / 60.0, center = SIMD2<Float>(0, 0), count = UInt32(N), wh = worldHalf, sp = sprite
let t0 = DispatchTime.now()
let cmd = queue.makeCommandBuffer()!
for _ in 0..<ticks {
    let ce = cmd.makeComputeCommandEncoder()!
    ce.setComputePipelineState(tickPSO)
    ce.setBuffer(entBuf, offset: 0, index: 0)
    ce.setBytes(&dt, length: 4, index: 1); ce.setBytes(&center, length: 8, index: 2); ce.setBytes(&count, length: 4, index: 3)
    let tg = min(tickPSO.maxTotalThreadsPerThreadgroup, 256)
    ce.dispatchThreads(MTLSize(width: N, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
    ce.endEncoding()
}
let rp = MTLRenderPassDescriptor()
rp.colorAttachments[0].texture = tex
rp.colorAttachments[0].loadAction = .clear
rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
rp.colorAttachments[0].storeAction = .store
let re = cmd.makeRenderCommandEncoder(descriptor: rp)!
re.setRenderPipelineState(renderPSO)
re.setVertexBuffer(entBuf, offset: 0, index: 0)
re.setVertexBytes(&wh, length: 8, index: 1); re.setVertexBytes(&sp, length: 4, index: 2)
re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: N)
re.endEncoding()
cmd.commit(); cmd.waitUntilCompleted()
let secs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9

// MARK: - readback -> PNG
var px = [UInt8](repeating: 0, count: size * size * 4)
tex.getBytes(&px, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
let ctx = CGContext(data: &px, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue)!
let img = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)

print(String(format: "Rendered %d entities (%d ticks) -> %@  [%dx%d]", N, ticks, outPath, size, size))
print(String(format: "  GPU compute+render: %.1f ms  (%.0f entity-updates/sec across %d ticks)", secs * 1000, Double(N * ticks) / secs, ticks))
print("  one MTLBuffer state, one instanced draw, no SpriteKit nodes.")
