#include <metal_stdlib>
using namespace metal;

// The whole game is drawn from ONE unit cube, instanced.
//
// A low-poly city of boxes needs no mesh pipeline, no asset format and no loader: buildings, street,
// cars, pedestrians, the pigeon's body parts, the payload, the arc and the landing ring are all the
// same eight vertices with a different transform and colour. That is not a shortcut for its own
// sake — it is what makes the art budget "primitives plus flat materials in froggo 1's hexes", which
// is the register PROMPT §4 asks for.
//
// The one texture is froggo 1's `scraper.png`, tiled across building facades exactly the way the
// original 2-D game tiled it with an SKShader.

// NOT `packed_float3`. Swift's `SIMD3<Float>` is 16-byte aligned with a stride of 16, while
// `packed_float3` is 12 — so a packed layout here makes the Swift struct 64 bytes and the Metal one
// 56, and every colour and flag reads shifted garbage. Plain `float3` matches Swift exactly.
struct Instance {
    float3 center;
    float3 halfExtent;
    float4 color;
    // x: 1 = sample the facade texture, 0 = flat colour.
    // y: tiling density in tiles per metre.
    // z: extra emissive lift, used for lit windows and the landing ring.
    // w: unused.
    float4 flags;
};

// Same alignment rule as `Instance` above — `float3`, never `packed_float3`.
struct Uniforms {
    float4x4 viewProjection;
    float3 lightDirection;
    float ambient;
    float3 fogColor;
    float fogDensity;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
    float shade;
    float textured;
    float emissive;
    float fog;
};

// Unit cube, 24 vertices — four per face, so every face carries its own normal and UVs.
//
// **The order within a face is a triangle-STRIP order, not a loop order**, and the difference is not
// cosmetic. A strip over `A,B,C,D` draws triangles `ABC` and `BCD`; for corners listed as a loop
// those two share the *edge* BC rather than a diagonal, so together they cover the quad minus a
// triangular hole. The first build rendered a city of translucent wedges because of exactly this.
//
// Each face below is therefore listed as `P0, P1, P3, P2` of a counter-clockwise loop `P0..P3`,
// which is the zig-zag a strip wants, and which also keeps the first triangle wound
// counter-clockwise so back-face culling removes the inside rather than the outside.
constant float3 kCubeCorner[24] = {
    // +x
    float3( 1,-1, 1), float3( 1,-1,-1), float3( 1, 1, 1), float3( 1, 1,-1),
    // -x
    float3(-1,-1,-1), float3(-1,-1, 1), float3(-1, 1,-1), float3(-1, 1, 1),
    // +y
    float3(-1, 1, 1), float3( 1, 1, 1), float3(-1, 1,-1), float3( 1, 1,-1),
    // -y
    float3(-1,-1,-1), float3( 1,-1,-1), float3(-1,-1, 1), float3( 1,-1, 1),
    // +z
    float3(-1,-1, 1), float3( 1,-1, 1), float3(-1, 1, 1), float3( 1, 1, 1),
    // -z
    float3( 1,-1,-1), float3(-1,-1,-1), float3( 1, 1,-1), float3(-1, 1,-1),
};

constant float3 kCubeNormal[6] = {
    float3( 1, 0, 0), float3(-1, 0, 0), float3( 0, 1, 0),
    float3( 0,-1, 0), float3( 0, 0, 1), float3( 0, 0,-1),
};

// Per-face UV basis, so a tiled texture runs across a face in world units rather than being
// stretched to the face's extent. Without this a tall building's windows stretch into streaks —
// the same failure froggo2 hit when it mapped its sky texture by extent.
// Matching the strip order above: (0,0), (1,0), (0,1), (1,1) — NOT a loop.
constant float2 kFaceUV[4] = {
    float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1),
};

vertex VertexOut cube_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             const device Instance *instances [[buffer(0)]],
                             constant Uniforms &u [[buffer(1)]])
{
    Instance inst = instances[iid];
    uint face = vid / 4;
    uint corner = vid % 4;

    float3 local = kCubeCorner[vid] * inst.halfExtent;
    float3 world = inst.center + local;

    VertexOut out;
    out.position = u.viewProjection * float4(world, 1.0);
    out.color = inst.color;

    // Flat directional shading, computed per face from the cube's own normals. Cheap, and it is what
    // stops a box city reading as a flat silhouette.
    float3 n = kCubeNormal[face];
    float lambert = max(0.0, dot(n, normalize(u.lightDirection)));
    out.shade = u.ambient + (1.0 - u.ambient) * lambert;

    // UVs in metres across the face, so tiling density is uniform on every building whatever its size.
    float2 spanUV;
    if (face == 0 || face == 1)      spanUV = float2(inst.halfExtent.z, inst.halfExtent.y) * 2.0;
    else if (face == 2 || face == 3) spanUV = float2(inst.halfExtent.x, inst.halfExtent.z) * 2.0;
    else                             spanUV = float2(inst.halfExtent.x, inst.halfExtent.y) * 2.0;
    out.uv = kFaceUV[corner] * spanUV * inst.flags.y;

    out.textured = inst.flags.x;
    out.emissive = inst.flags.z;

    // Aerial perspective, measured from the PLAY PLANE rather than from the camera.
    //
    // `fogDensity` carries the camera's distance to the play plane, so this is how far *behind* the
    // action a surface sits. Keyed to raw camera depth instead, everything fogs equally and the
    // whole city washes toward the sky colour — which is what the first run looked like.
    float behind = max(0.0, out.position.w - u.fogDensity);
    out.fog = 1.0 - exp(-behind * 0.009);
    return out;
}

fragment float4 cube_fragment(VertexOut in [[stage_in]],
                              constant Uniforms &u [[buffer(1)]],
                              texture2d<float> facade [[texture(0)]],
                              sampler facadeSampler [[sampler(0)]])
{
    float3 base = in.color.rgb;
    if (in.textured > 0.5) {
        float4 t = facade.sample(facadeSampler, in.uv);
        base = t.rgb;
    }
    float3 lit = base * in.shade + base * in.emissive;
    lit = mix(lit, u.fogColor, in.fog);
    return float4(lit, in.color.a);
}

// ── Sky ─────────────────────────────────────────────────────────────────────────────────────
//
// A full-screen triangle with a vertical gradient, drawn first with depth writes off. Cheaper than a
// skybox mesh and, for a locked side view that never pitches, indistinguishable from one.

struct SkyOut {
    float4 position [[position]];
    float2 ndc;
};

vertex SkyOut sky_vertex(uint vid [[vertex_id]])
{
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    SkyOut out;
    out.position = float4(p, 1.0, 1.0);
    out.ndc = p;
    return out;
}

fragment float4 sky_fragment(SkyOut in [[stage_in]],
                             constant float4 *colors [[buffer(0)]])
{
    float t = saturate(in.ndc.y * 0.5 + 0.5);
    return float4(mix(colors[1].rgb, colors[0].rgb, t), 1.0);
}
