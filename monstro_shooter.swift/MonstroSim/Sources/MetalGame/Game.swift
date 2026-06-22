import Foundation
import Metal
import simd

// The actual game, run on the GPU: world state in one MTLBuffer, the whole tick (steering, bullets,
// collision, contact damage) as Metal compute kernels, rendered with one instanced draw. The player
// is entity[0], managed on the CPU (input/agent + health); everything else lives on the GPU.

struct Entity {                  // must match the Metal struct (stride 32)
    var px: Float = 0, py: Float = 0
    var vx: Float = 0, vy: Float = 0
    var kind: UInt32 = 0         // 0 monster, 1 bullet, 2 player
    var type: UInt32 = 0
    var hp: Int32 = 0
    var alive: UInt32 = 0
}

let gameShaders = """
#include <metal_stdlib>
using namespace metal;
struct Entity { float px; float py; float vx; float vy; uint kind; uint type; int hp; uint alive; };

kernel void steer(device Entity* e [[buffer(0)]], constant float2& player [[buffer(1)]],
                  constant float& dt [[buffer(2)]], constant uint& count [[buffer(3)]],
                  uint id [[thread_position_in_grid]]) {
    if (id >= count) return; device Entity& m = e[id];
    if (m.alive == 0u || m.kind != 0u) return;
    float2 p = float2(m.px, m.py); float2 d = player - p; float dist = max(length(d), 1e-3);
    float speed = 130.0 + float(m.type) * 30.0;          // ~real monster speeds (bug 150-ish)
    p += d / dist * speed * dt; m.px = p.x; m.py = p.y;
}

kernel void moveBullets(device Entity* e [[buffer(0)]], constant float& dt [[buffer(1)]],
                        constant uint& count [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    if (id >= count) return; device Entity& b = e[id];
    if (b.alive == 0u || b.kind != 1u) return;
    b.px += b.vx * dt; b.py += b.vy * dt; b.hp -= 1;        // hp = lifetime ticks
    if (b.hp <= 0) b.alive = 0u;
}

kernel void collide(device Entity* e [[buffer(0)]], device atomic_uint* kills [[buffer(1)]],
                    constant uint& count [[buffer(2)]], uint id [[thread_position_in_grid]]) {
    if (id >= count) return; device Entity& b = e[id];
    if (b.alive == 0u || b.kind != 1u) return;
    float2 bp = float2(b.px, b.py);
    for (uint j = 0; j < count; j++) {
        device Entity& m = e[j];
        if (m.alive == 0u || m.kind != 0u) continue;
        float2 d = float2(m.px, m.py) - bp;
        if (dot(d, d) < 20.0 * 20.0) {
            int prev = atomic_fetch_sub_explicit((device atomic_int*)&m.hp, 10, memory_order_relaxed);
            b.alive = 0u;
            if (prev > 0 && prev - 10 <= 0) { m.alive = 0u; atomic_fetch_add_explicit(kills, 1u, memory_order_relaxed); }
            break;
        }
    }
}

kernel void contact(device Entity* e [[buffer(0)]], constant float2& player [[buffer(1)]],
                    device atomic_int* dmg [[buffer(2)]], constant uint& count [[buffer(3)]],
                    uint id [[thread_position_in_grid]]) {
    if (id >= count) return; device Entity& m = e[id];
    if (m.alive == 0u || m.kind != 0u) return;
    float2 d = float2(m.px, m.py) - player;
    if (dot(d, d) < 34.0 * 34.0) atomic_fetch_add_explicit(dmg, int(2 + m.type), memory_order_relaxed);
}

kernel void aimNearest(device Entity* e [[buffer(0)]], constant uint& count [[buffer(1)]],
                       device float2* out [[buffer(2)]]) {
    float2 pp = float2(e[0].px, e[0].py); float best = 1e30; float2 dir = float2(0, 0);
    for (uint j = 1; j < count; j++) {
        device Entity& m = e[j];
        if (m.alive == 0u || m.kind != 0u) continue;
        float2 d = float2(m.px, m.py) - pp; float dd = dot(d, d);
        if (dd < best) { best = dd; dir = d * rsqrt(max(dd, 1e-6)); }
    }
    out[0] = dir;
}

struct VOut { float4 position [[position]]; float2 uv; uint kind; uint type; };
vertex VOut v_main(uint vid [[vertex_id]], uint iid [[instance_id]],
                   const device Entity* e [[buffer(0)]],
                   constant float2& camCenter [[buffer(1)]], constant float2& camHalf [[buffer(2)]]) {
    float2 corners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 c = corners[vid]; Entity en = e[iid];
    VOut o; o.uv = c; o.kind = en.kind; o.type = en.type;
    if (en.alive == 0u) { o.position = float4(2,2,2,1); return o; }
    float size = en.kind == 2u ? 22.0 : (en.kind == 1u ? 6.0 : (14.0 + 3.0 * float(en.type)));
    float2 world = float2(en.px, en.py) + c * size;
    o.position = float4((world - camCenter) / camHalf, 0, 1);
    return o;
}
fragment float4 f_main(VOut in [[stage_in]]) {
    float r = length(in.uv); if (r > 1.0) discard_fragment();
    float3 mon[5] = { float3(0.95,0.35,0.25), float3(0.30,0.70,0.95), float3(0.55,0.90,0.45), float3(0.95,0.82,0.30), float3(0.80,0.45,0.95) };
    float3 col = in.kind == 2u ? float3(1.0) : (in.kind == 1u ? float3(1.0,0.95,0.5) : mon[in.type % 5u]);
    float a = smoothstep(1.0, 0.55, r);
    return float4(col, 1.0) * a;
}
"""

final class Game {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let cap = 16384
    let maxMon = 7000
    var bulletBase: Int { 1 + maxMon }
    var bulletCap: Int { cap - bulletBase }

    let buf: MTLBuffer
    let ptr: UnsafeMutablePointer<Entity>
    let killsBuf, dmgBuf, aimBuf: MTLBuffer

    let psoSteer, psoBullets, psoCollide, psoContact, psoAim: MTLComputePipelineState
    let psoRender: MTLRenderPipelineState

    // CPU-side player + bookkeeping
    var ppos = SIMD2<Float>(0, 0)
    var php: Float = 100
    var aim = SIMD2<Float>(0, 1)
    let worldHalf: Float = 1100
    let playerSpeed: Float = 300
    var monW = 0, bulW = 0
    var spawnT: Float = 0, fireT: Float = 0
    // aligned to the training regime (BatchWorld/brax) so the Core ML policy transfers:
    // ~2 spawns/sec, pistol 0.5s fire cadence (vs the old 10/sec + 0.18s demo values).
    let spawnInterval: Float = 0.5, fireInterval: Float = 0.5
    var rng = SystemRandomNumberGenerator()
    var frames = 0

    init() throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else {
            throw NSError(domain: "game", code: 1, userInfo: [NSLocalizedDescriptionKey: "no Metal device"])
        }
        device = d; queue = q
        let lib = try d.makeLibrary(source: gameShaders, options: nil)
        func cp(_ n: String) throws -> MTLComputePipelineState { try d.makeComputePipelineState(function: lib.makeFunction(name: n)!) }
        psoSteer = try cp("steer"); psoBullets = try cp("moveBullets"); psoCollide = try cp("collide")
        psoContact = try cp("contact"); psoAim = try cp("aimNearest")
        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = lib.makeFunction(name: "v_main"); rpd.fragmentFunction = lib.makeFunction(name: "f_main")
        let a = rpd.colorAttachments[0]!
        a.pixelFormat = .bgra8Unorm; a.isBlendingEnabled = true
        a.sourceRGBBlendFactor = .one; a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        psoRender = try d.makeRenderPipelineState(descriptor: rpd)

        buf = d.makeBuffer(length: MemoryLayout<Entity>.stride * cap, options: .storageModeShared)!
        ptr = buf.contents().bindMemory(to: Entity.self, capacity: cap)
        for i in 0..<cap { ptr[i] = Entity() }
        killsBuf = d.makeBuffer(length: 4, options: .storageModeShared)!
        dmgBuf = d.makeBuffer(length: 4, options: .storageModeShared)!
        aimBuf = d.makeBuffer(length: 8, options: .storageModeShared)!
    }

    var kills: UInt32 { killsBuf.contents().load(as: UInt32.self) }
    var alive: Bool { php > 0 }

    private func spawnMonster() {
        let ang = Float.random(in: 0..<(2 * .pi), using: &rng)
        let rad = Float.random(in: 650..<950, using: &rng)
        let t = UInt32.random(in: 0...4, using: &rng)
        let slot = 1 + (monW % maxMon); monW += 1
        ptr[slot] = Entity(px: ppos.x + cos(ang) * rad, py: ppos.y + sin(ang) * rad, vx: 0, vy: 0,
                           kind: 0, type: t, hp: Int32(6 + t * 4), alive: 1)   // ~real low hp
    }
    private func fireBullet() {
        guard length(aim) > 0.01 else { return }
        let slot = bulletBase + (bulW % bulletCap); bulW += 1
        ptr[slot] = Entity(px: ppos.x, py: ppos.y, vx: aim.x * 800, vy: aim.y * 800,   // pistol speed
                           kind: 1, type: 0, hp: 40, alive: 1)                          // ~500u range
    }

    /// One frame: CPU spawn/fire/move + GPU kernels (steer, bullets, collide, contact, aim).
    func step(dt: Float, moveDir: SIMD2<Float>) {
        frames += 1
        spawnT += dt; while spawnT >= spawnInterval { spawnMonster(); spawnT -= spawnInterval }
        // sync player into the buffer for the kernels
        ptr[0] = Entity(px: ppos.x, py: ppos.y, vx: 0, vy: 0, kind: 2, type: 0, hp: Int32(php), alive: 1)
        dmgBuf.contents().storeBytes(of: Int32(0), as: Int32.self)

        var dtv = dt, count = UInt32(cap), player = ppos
        let cmd = queue.makeCommandBuffer()!
        func dispatch(_ pso: MTLComputePipelineState, _ setup: (MTLComputeCommandEncoder) -> Void) {
            let e = cmd.makeComputeCommandEncoder()!; e.setComputePipelineState(pso)
            e.setBuffer(buf, offset: 0, index: 0); setup(e)
            let tg = min(pso.maxTotalThreadsPerThreadgroup, 256)
            e.dispatchThreads(MTLSize(width: cap, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
            e.endEncoding()
        }
        dispatch(psoAim) { $0.setBytes(&count, length: 4, index: 1); $0.setBuffer(aimBuf, offset: 0, index: 2) }
        dispatch(psoSteer) { $0.setBytes(&player, length: 8, index: 1); $0.setBytes(&dtv, length: 4, index: 2); $0.setBytes(&count, length: 4, index: 3) }
        dispatch(psoBullets) { $0.setBytes(&dtv, length: 4, index: 1); $0.setBytes(&count, length: 4, index: 2) }
        dispatch(psoCollide) { $0.setBuffer(self.killsBuf, offset: 0, index: 1); $0.setBytes(&count, length: 4, index: 2) }
        dispatch(psoContact) { $0.setBytes(&player, length: 8, index: 1); $0.setBuffer(self.dmgBuf, offset: 0, index: 2); $0.setBytes(&count, length: 4, index: 3) }
        cmd.commit(); cmd.waitUntilCompleted()

        // read GPU results, apply to CPU player
        aim = aimBuf.contents().load(as: SIMD2<Float>.self)
        let dmg = dmgBuf.contents().load(as: Int32.self)
        php -= Float(dmg) * dt
        fireT += dt; while fireT >= fireInterval { fireBullet(); fireT -= fireInterval }
        var mv = moveDir; if length(mv) > 1 { mv = normalize(mv) }
        ppos += mv * playerSpeed * dt
        ppos = clamp(ppos, min: SIMD2(repeating: -worldHalf), max: SIMD2(repeating: worldHalf))
        ptr[0].px = ppos.x; ptr[0].py = ppos.y
    }

    /// Egocentric observation matching training (brax/env.obs / BatchWorld.buildPlayerObs):
    /// [healthNorm, aliveNorm, threatX, threatY, nearestDist/1000, meanDist/1000]. `monsterNorm`
    /// is the training M (alive-count normalizer) so the obs scale matches the trained policy.
    func buildObs(monsterNorm: Float = 100) -> [Float] {
        var alive: Float = 0, nearest: Float = 1e9, sumDist: Float = 0
        var threat = SIMD2<Float>(0, 0)
        for i in 1..<(1 + maxMon) {
            let e = ptr[i]
            if e.alive == 0 || e.kind != 0 { continue }
            let d = SIMD2<Float>(e.px - ppos.x, e.py - ppos.y)
            let dist = max(simd_length(d), 1e-3)
            alive += 1; threat += d / dist; sumDist += dist
            if dist < nearest { nearest = dist }
        }
        let tl = simd_length(threat)
        let threatN = tl > 0 ? threat / tl : SIMD2<Float>(0, 0)
        let meanD = alive > 0 ? sumDist / alive : 0
        if nearest > 1e8 { nearest = 0 }
        return [php / 100, alive / monsterNorm, threatN.x, threatN.y, nearest / 1000, meanD / 1000]
    }

    /// Instanced render of the whole entity buffer into `tex`.
    func render(into tex: MTLTexture) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        var center = ppos, half = SIMD2<Float>(worldHalf, worldHalf)
        let cmd = queue.makeCommandBuffer()!
        let e = cmd.makeRenderCommandEncoder(descriptor: rp)!
        e.setRenderPipelineState(psoRender); e.setVertexBuffer(buf, offset: 0, index: 0)
        e.setVertexBytes(&center, length: 8, index: 1); e.setVertexBytes(&half, length: 8, index: 2)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: cap)
        e.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
    }

    /// Render into a view's render pass and present its drawable (live window path).
    func render(passDescriptor rp: MTLRenderPassDescriptor, drawable: MTLDrawable) {
        var center = ppos, half = SIMD2<Float>(worldHalf, worldHalf)
        let cmd = queue.makeCommandBuffer()!
        let e = cmd.makeRenderCommandEncoder(descriptor: rp)!
        e.setRenderPipelineState(psoRender); e.setVertexBuffer(buf, offset: 0, index: 0)
        e.setVertexBytes(&center, length: 8, index: 1); e.setVertexBytes(&half, length: 8, index: 2)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: cap)
        e.endEncoding(); cmd.present(drawable); cmd.commit()
    }
}
