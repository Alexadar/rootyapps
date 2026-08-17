#include <metal_stdlib>
using namespace metal;

// The pig is not a mesh. It is a function.
//
// `pigPoint(u, v, body)` below is the ONE definition of the animal's surface, and everything on
// screen that belongs to the pig is placed by it:
//
//   * the body itself — an indexed (U+1)×(V+1) parameter grid with no vertex buffer at all; the
//     vertex id IS the (u, v);
//   * every attachment — legs, ears, eyes, snout, nostrils, tail — which carries a `(u, v)` anchor
//     and is welded to the surface by evaluating the same function in the same shader.
//
// That second point is the reason the surface lives here and only here. The alternative — evaluating
// the shape on the CPU to place attachments and again on the GPU to draw the skin — is two copies of
// one equation, and the copies come apart exactly when the shape changes, which in this game is all
// the time. When the belly swells mid-frame the legs move with it because they are reading the belly,
// not a remembered copy of it.
//
// The dimensions themselves are NOT decided here. They arrive as uniforms from
// `Engine/Shape.swift`, which derives all of them from one simulation number, `fat`, and is where the
// proofs about them live.
//
// NOT `packed_float3` anywhere. Swift's `SIMD3<Float>` is 16-byte aligned with a stride of 16, while
// `packed_float3` is 12 — mixing them makes every field after the first read shifted garbage.

constant float kPi = 3.14159265358979323846;

// MARK: - Shared uniforms

struct Uniforms {
    float4x4 viewProjection;
    float3 cameraPosition;
    float time;
    float3 lightDirection;
    float ambient;
    float3 fogColor;
    float fogDensity;
    float3 groundColor;
    float paddockRadius;
    // Where to darken the field, and how much. The shadow is a ground-shader term rather than a
    // drawn quad: it costs nothing, it cannot z-fight, and it tracks the animal's real width.
    float3 shadowCenter;
    float shadowRadius;
};

// One pig. Every field is derived from `fat` by `PigShape.derive` — nothing here is authored art.
struct Body {
    float4x4 model;
    float4 rA;      // radii: snout, head, chest, belly
    float4 rB;      // radii: rump, tailBase, then bodyLength, standHeight
    float4 shape;   // sag, squash, superE, jowl
    float4 anim;    // gait, wobbleAmplitude, lie, breath
    float4 extra;   // headLift, chew, fat, unused
    float4 color;
};

// One attachment or one prop.
struct Blob {
    // free:     (x, y, z, 0)      — a point in the world.
    // attached: (u, v, unused, 1) — a point on the pig's surface.
    // spine:    (u, unused, unused, 2) — a point on the pig's centre line, which at u = 0 and u = 1
    //                                    is exactly the tip of the nose and of the rump, because the
    //                                    caps close there.
    float4 anchor;
    // Offset from that point. Attached blobs are offset in the surface's own frame
    // (binormal, normal, tangent), so an ear stays on the side of a head that has just widened.
    float4 offset;
    float4 scale;   // xyz radii, w = taper along local y
    // xyz euler in the local frame; w = 1 switches to "leg" mode, where the blob hangs from its
    // anchor down to the ground and `rot.x` is instead how far the foot is lifted, 0…1.
    float4 rot;
    float4 color;
};

// MARK: - The surface
//
// Six control radii along the spine, blended with chained smoothsteps rather than a spline.
// Deliberately: a Catmull-Rom through these overshoots between chest and belly at high fat, and an
// overshooting radius is a bulge the shape maths does not know about — which is how a surface
// self-intersects and starts shading itself black.

inline float bump(float u, float centre, float width) {
    float d = (u - centre) / width;
    return exp(-d * d * 2.0);
}

inline float profileRadius(float u, Body b) {
    // Six control radii, blended by a NORMALISED Gaussian weighting — a partition of unity, so the
    // result is a convex combination of the controls: smooth everywhere, and unable to overshoot.
    //
    // The first version chained `smoothstep`s between consecutive knots. That reads as correct and is
    // not: smoothstep has zero derivative at BOTH edges, so the profile arrives at every control point
    // with zero slope and leaves it the same way — a terrace at each of the six knots. Invisible on a
    // lean pig, whose radii are all within a fifth of each other, and unmistakable on a fat one, whose
    // back stepped down in three visible ledges. The normals stayed smooth throughout, which is why it
    // read as a shading bug for three renders: the geometry really was terraced.
    const float sigma = 0.155;
    float knot[6] = { 0.00, 0.15, 0.35, 0.60, 0.82, 1.00 };
    float radius[6] = { b.rA.x, b.rA.y, b.rA.z, b.rA.w, b.rB.x, b.rB.y };

    float num = 0.0, den = 0.0;
    for (int i = 0; i < 6; ++i) {
        float w = bump(u, knot[i], sigma);
        num += w * radius[i];
        den += w;
    }
    float r = num / den;

    // The neck: a pinch between head and shoulders, which a blend of positive radii cannot produce on
    // its own. It fades out as the pig fattens, because a fat pig does not have one.
    r *= 1.0 - 0.13 * bump(u, 0.27, 0.075) * (1.0 - 0.75 * b.extra.z);
    return r;
}

// Circular caps, so the tube closes into a rounded nose and a rounded rump instead of two holes.
inline float capFactor(float u) {
    float a = clamp(u / 0.13, 0.0, 1.0);
    float c = clamp((1.0 - u) / 0.10, 0.0, 1.0);
    return sqrt(max(0.0, a * (2.0 - a))) * sqrt(max(0.0, c * (2.0 - c)));
}

// Height of the spine at `u`, before the cross-section is added.
inline float spineHeight(float u, Body b) {
    float y = b.rB.w;                                       // stand
    y -= b.shape.x * bump(u, 0.62, 0.30);                   // the belly drags the centre line down
    y += b.extra.x * (1.0 - smoothstep(0.0, 0.34, u));      // the head lifts clear of the shoulders
    y += 0.020 * sin(u * kPi);                              // a little arch through the back
    return y;
}

/// The animal, at parameter `(u, v)`. `u` runs snout → tail, `v` runs around the body.
inline float3 pigPoint(float u, float v, Body b) {
    float r = profileRadius(u, b) * capFactor(u);

    // The wobble. One spring, integrated in the engine; its amplitude arrives here already scaled by
    // fat, so a lean pig is rigid and a fat one is a water balloon without a second code path.
    r *= 1.0 + b.anim.y * bump(u, 0.62, 0.34) * sin(u * 7.0 - b.anim.x * 2.0);
    // Breathing, non-zero only while asleep.
    r *= 1.0 + 0.035 * b.anim.w * bump(u, 0.58, 0.36);

    float th = v * 2.0 * kPi;
    float cs = cos(th), sn = sin(th);
    // Superellipse. e = 1 is a circle; e < 1 squares off into a loaf as the pig fattens.
    float e = 2.0 / max(b.shape.z, 1.0);
    float2 q = float2(sign(cs) * pow(abs(cs) + 1e-5, e), sign(sn) * pow(abs(sn) + 1e-5, e));

    // The double chin: extra radius under the jaw only.
    float rl = r + b.shape.w * bump(u, 0.22, 0.13) * max(0.0, -q.y);

    float px = q.x * rl * b.shape.y;                                // squash: wider than tall
    // The cross-section is NOT symmetric about the spine, and that asymmetry is most of what makes a
    // tube read as an animal: the back is flattened, and the belly hangs below — until the pig is
    // fat enough that the underside settles flat against the field again.
    // `underside` arrives from `PigShape`, because the ground-clearance proof in `ShapeOracleTests`
    // is stated over it — a second copy of the number here would make that proof about a different
    // pig than the one on screen.
    float ky = mix(0.93, b.extra.w, smoothstep(0.14, -0.14, q.y));
    float py = q.y * rl * ky;
    float pz = (0.5 - u) * b.rB.z;                                  // snout at +z

    return float3(px, spineHeight(u, b) + py, pz);
}

/// Outward normal, by central differences of the same function. Three extra evaluations, and it
/// means the normal can never disagree with the shape — which a stored normal buffer would, the
/// instant `fat` moved.
inline float3 pigNormal(float u, float v, Body b) {
    const float du = 0.010, dv = 0.010;
    float3 p = pigPoint(u, v, b);
    float3 tu = pigPoint(clamp(u + du, 0.0, 1.0), v, b) - pigPoint(clamp(u - du, 0.0, 1.0), v, b);
    float3 tv = pigPoint(u, v + dv, b) - pigPoint(u, v - dv, b);
    float3 n = cross(tv, tu);
    float l = length(n);
    if (l < 1e-8) { return float3(0.0, 1.0, 0.0); }
    n /= l;
    // Orient outward against the spine rather than trusting the cross product's winding: at the two
    // caps the parameterisation flips, and a shaded-black nose is the tell.
    float3 axis = float3(0.0, spineHeight(u, b), (0.5 - u) * b.rB.z);
    return (dot(n, p - axis) < 0.0) ? -n : n;
}

// MARK: - Body pass

struct BodyOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
    float fog;
};

vertex BodyOut body_vertex(uint vid [[vertex_id]],
                           constant Uniforms &g [[buffer(1)]],
                           constant Body &bodyRef [[buffer(2)]],
                           constant uint2 &grid [[buffer(3)]])
{
    Body b = bodyRef;
    uint ring = vid / (grid.y + 1);
    uint seg = vid % (grid.y + 1);
    float u = float(ring) / float(grid.x);
    float v = float(seg) / float(grid.y);

    float3 local = pigPoint(u, v, b);
    float3 n = pigNormal(u, v, b);

    float4 world = b.model * float4(local, 1.0);
    float3 worldN = normalize((b.model * float4(n, 0.0)).xyz);

    BodyOut out;
    out.position = g.viewProjection * world;
    out.world = world.xyz;
    out.normal = worldN;
    out.uv = float2(u, v);
    out.fog = 1.0 - exp(-max(0.0, out.position.w - 6.0) * g.fogDensity);
    return out;
}

// Half-lambert with a rim term. Skin, not metal: the wrap makes the shaded side read as flesh, and
// the rim is what separates a pink animal from a pink background at silhouette.
inline float3 shade(float3 base, float3 n, float3 world, constant Uniforms &g, float gloss)
{
    float3 l = normalize(g.lightDirection);
    float3 view = normalize(g.cameraPosition - world);
    float wrap = dot(n, l) * 0.5 + 0.5;
    float3 lit = base * (g.ambient + (1.0 - g.ambient) * wrap * wrap);
    // A cool bounce from the field, so the underside is not simply dark.
    lit += base * float3(0.10, 0.16, 0.09) * max(0.0, -n.y) * 0.6;
    float3 h = normalize(l + view);
    lit += gloss * pow(max(0.0, dot(n, h)), 42.0);
    float rim = pow(1.0 - max(0.0, dot(n, view)), 3.0);
    lit += base * rim * 0.35;
    return lit;
}

fragment float4 body_fragment(BodyOut in [[stage_in]],
                              constant Uniforms &g [[buffer(1)]],
                              constant Body &b [[buffer(2)]])
{
    float3 base = b.color.rgb;

    // How far under the animal this point is: +1 at the spine, −1 at the belly. Taken from the
    // cross-section angle rather than from `v` directly — `abs(v - 0.5)` was the first attempt and it
    // is not the underside at all, it is the far FLANK, so the shading it produced ran down the side
    // of the pig in bands instead of pooling under it.
    float down = -sin(in.uv.y * 2.0 * kPi);

    base = mix(base, base * 1.09, clamp(-down, 0.0, 1.0));    // sunlit back
    base = mix(base, base * 0.87, clamp(down, 0.0, 1.0));     // shaded belly
    // Dirt, because it has been rolling in a field. Pooled underneath and toward the rear.
    float grime = 0.07 * clamp(down, 0.0, 1.0) * smoothstep(0.35, 0.95, in.uv.x);
    base = mix(base, float3(0.42, 0.34, 0.28), grime);

    float3 lit = shade(base, normalize(in.normal), in.world, g, 0.10);
    lit = mix(lit, g.fogColor, in.fog);
    return float4(lit, 1.0);
}

// MARK: - Blob pass
//
// One unit sphere, instanced, with no vertex buffer: the vertex id is the (ring, segment). Every
// attachment is placed by evaluating the pig's surface at its anchor and building a frame there, so
// attachments deform with the body for free.

struct BlobOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float4 color;
    float fog;
};

inline float3x3 eulerMatrix(float3 e) {
    float cx = cos(e.x), sx = sin(e.x);
    float cy = cos(e.y), sy = sin(e.y);
    float cz = cos(e.z), sz = sin(e.z);
    float3x3 rx = float3x3(float3(1, 0, 0), float3(0, cx, sx), float3(0, -sx, cx));
    float3x3 ry = float3x3(float3(cy, 0, -sy), float3(0, 1, 0), float3(sy, 0, cy));
    float3x3 rz = float3x3(float3(cz, sz, 0), float3(-sz, cz, 0), float3(0, 0, 1));
    return ry * rx * rz;
}

vertex BlobOut blob_vertex(uint vid [[vertex_id]],
                           uint iid [[instance_id]],
                           const device Blob *blobs [[buffer(0)]],
                           constant Uniforms &g [[buffer(1)]],
                           constant Body &bodyRef [[buffer(2)]],
                           constant uint2 &grid [[buffer(3)]])
{
    Blob inst = blobs[iid];
    Body b = bodyRef;

    // Unit sphere from the vertex id.
    uint ring = vid / (grid.y + 1);
    uint seg = vid % (grid.y + 1);
    float phi = float(ring) / float(grid.x) * kPi;
    float th = float(seg) / float(grid.y) * 2.0 * kPi;
    float3 unit = float3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th));

    float3 centre;
    float3x3 frame;

    if (inst.anchor.w > 1.5) {
        // On the centre line. `u = 0` is the tip of the nose and `u = 1` the tip of the rump,
        // because `capFactor` closes the tube there — so the snout and the tail need no knowledge of
        // the current radii at all.
        float u = inst.anchor.x;
        float3 local = float3(0.0, spineHeight(u, b), (0.5 - u) * b.rB.z) + inst.offset.xyz;
        centre = (b.model * float4(local, 1.0)).xyz;
        frame = float3x3((b.model * float4(1, 0, 0, 0)).xyz,
                         (b.model * float4(0, 1, 0, 0)).xyz,
                         (b.model * float4(0, 0, 1, 0)).xyz);
    } else if (inst.anchor.w > 0.5) {
        // Welded to the pig. The frame is the surface's own: tangent along the spine, the surface
        // normal, and their cross product.
        float u = inst.anchor.x, v = inst.anchor.y;
        float3 p = pigPoint(u, v, b);
        float3 n = pigNormal(u, v, b);
        float3 tangent = normalize(pigPoint(clamp(u + 0.01, 0.0, 1.0), v, b)
                                   - pigPoint(clamp(u - 0.01, 0.0, 1.0), v, b));
        float3 binormal = normalize(cross(n, tangent));
        float3x3 surf = float3x3(binormal, n, tangent);
        float3 local = p + surf * inst.offset.xyz;
        centre = (b.model * float4(local, 1.0)).xyz;
        frame = float3x3((b.model * float4(surf[0], 0.0)).xyz,
                         (b.model * float4(surf[1], 0.0)).xyz,
                         (b.model * float4(surf[2], 0.0)).xyz);
    } else {
        centre = inst.anchor.xyz + inst.offset.xyz;
        frame = float3x3(float3(1, 0, 0), float3(0, 1, 0), float3(0, 0, 1));
    }

    float3x3 rot = frame * eulerMatrix(inst.rot.xyz);
    float3 radii = inst.scale.xyz;

    // A leg does not have an authored length: it hangs from wherever the belly currently is down to
    // the ground. When the pig doubles in girth its legs shorten by themselves, which is the joke and
    // also one fewer number to keep consistent. `rot.x` lifts the foot for the walk cycle, and the
    // leg stays world-upright rather than following the surface normal — a normal that points
    // sideways off a swollen flank would splay the legs out from under the animal.
    if (inst.rot.w > 0.5) {
        float h = max(0.05, centre.y);
        float lift = clamp(inst.rot.x, 0.0, 1.0);
        float footY = h * 0.45 * lift;              // how far off the ground the foot is
        float legLength = max(0.04, h - footY);
        if (inst.scale.y > 0.0) {
            // A hoof: a small cap that sits at the foot, wherever the foot turned out to be.
            radii.y = inst.scale.y;
            centre.y = footY + inst.scale.y * 0.5;
        } else {
            radii.y = legLength * 0.5;
            centre.y = footY + legLength * 0.5;
        }
        rot = float3x3(float3(1, 0, 0), float3(0, 1, 0), float3(0, 0, 1));
    }

    // Taper along the local y, so legs are thicker at the top and snouts flare at the tip.
    float taper = mix(inst.scale.w, 1.0, unit.y * 0.5 + 0.5);
    float3 scaled = float3(unit.x * radii.x * taper, unit.y * radii.y, unit.z * radii.z * taper);

    float3 world = centre + rot * scaled;
    float3 n = normalize(rot * (unit / max(radii, float3(1e-4))));

    BlobOut out;
    out.position = g.viewProjection * float4(world, 1.0);
    out.world = world;
    out.normal = n;
    out.color = inst.color;
    out.fog = 1.0 - exp(-max(0.0, out.position.w - 6.0) * g.fogDensity);
    return out;
}

fragment float4 blob_fragment(BlobOut in [[stage_in]], constant Uniforms &g [[buffer(1)]])
{
    float3 lit = shade(in.color.rgb, normalize(in.normal), in.world, g, in.color.a);
    lit = mix(lit, g.fogColor, in.fog);
    return float4(lit, 1.0);
}

// MARK: - Ground

struct GroundOut {
    float4 position [[position]];
    float3 world;
    float fog;
};

vertex GroundOut ground_vertex(uint vid [[vertex_id]], constant Uniforms &g [[buffer(1)]])
{
    // One quad from four vertex ids, in a triangle strip.
    float2 c = float2((vid == 1 || vid == 3) ? 1.0 : -1.0, (vid >= 2) ? 1.0 : -1.0);
    float extent = g.paddockRadius * 3.0;
    float3 world = float3(c.x * extent, 0.0, c.y * extent);

    GroundOut out;
    out.position = g.viewProjection * float4(world, 1.0);
    out.world = world;
    out.fog = 1.0 - exp(-max(0.0, out.position.w - 6.0) * g.fogDensity);
    return out;
}

fragment float4 ground_fragment(GroundOut in [[stage_in]], constant Uniforms &g [[buffer(1)]])
{
    float2 p = in.world.xz;

    // Two greens on a soft checker, plus a fine hatch, so motion is readable without a texture.
    float check = (fmod(floor(p.x * 0.5) + floor(p.y * 0.5), 2.0) < 0.5) ? 0.0 : 1.0;
    float3 base = mix(g.groundColor, g.groundColor * 1.12, check);
    float hatch = 0.5 + 0.5 * sin(p.x * 6.0) * sin(p.y * 6.0);
    base *= 0.97 + 0.03 * hatch;

    // The fence: a ring of posts, drawn as a band rather than as geometry.
    float r = length(p);
    float ring = smoothstep(0.22, 0.0, abs(r - g.paddockRadius));
    float posts = 0.5 + 0.5 * sin(atan2(p.y, p.x) * 64.0);
    base = mix(base, float3(0.52, 0.40, 0.28), ring * (0.35 + 0.5 * posts));
    // Outside the fence the field falls away to fog.
    base = mix(base, g.fogColor, smoothstep(g.paddockRadius, g.paddockRadius * 1.6, r));

    // The pig's shadow: an ellipse that tracks its actual width, soft at the edge.
    float d = length(p - g.shadowCenter.xz) / max(g.shadowRadius, 1e-3);
    float shadow = (1.0 - smoothstep(0.55, 1.0, d)) * 0.45;
    base *= 1.0 - shadow;

    float3 lit = base * (g.ambient + (1.0 - g.ambient) * max(0.0, normalize(g.lightDirection).y));
    lit = mix(lit, g.fogColor, in.fog);
    return float4(lit, 1.0);
}

// MARK: - Sky
//
// A full-screen triangle with a vertical gradient, drawn first with depth writes off. Cheaper than a
// skybox mesh and, for a camera that never pitches far, indistinguishable from one.

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

fragment float4 sky_fragment(SkyOut in [[stage_in]], constant float4 *colors [[buffer(0)]])
{
    float t = saturate(in.ndc.y * 0.5 + 0.5);
    float3 c = mix(colors[1].rgb, colors[0].rgb, t);
    return float4(c, 1.0);
}
