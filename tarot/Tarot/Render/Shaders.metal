#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

// The card foil surface — one shader, three researched layers, driven by a single
// "light angle" uniform the kernel smooths (device gravity on iOS, cursor on Mac).
//
//   custom_parameter = (lightX, lightZ, time, tier)   tier: 0 back, 1 minor, 2 major
//   custom texture   = foil mask: R region, G film thickness, B fine relief
//
// Layers, lifted from the research (see the build plan for attribution):
//  1. counter-moving rainbow streak   — simeydotme pokemon-cards-css / Ilett holo tutorial:
//     hue ramp indexed by sin(dot(streak dir, light) · density + uv offset)
//  2. sparkle                         — voronoi-ish hash cells whose random direction dots
//     against the light vector (ameye.dev / TCG Pocket recreations)
//  3. thin-film hue for majors        — spectral ramp driven by per-pixel film thickness
//     (Zucconi car-paint approximation, reduced to a cosine palette)

namespace {

inline float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// Iñigo Quílez cosine palette — the cheap spectral ramp.
inline half3 spectral(float t) {
    float3 c = 0.5 + 0.5 * cos(6.28318 * (float3(1.0, 1.0, 1.0) * t + float3(0.0, 0.33, 0.67)));
    return half3(c);
}

// Bilinear value noise — smooth, unlike raw cell hashing (which renders as hard squares).
inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Three-octave fBM — the same shape as the five-octave one at a third of the cost.
// Used wherever the noise covers a lot of pixels (the cloth, the flames); the fine
// detail of octaves 4–5 is invisible under a lamp pool anyway.
inline float fbm3(float2 p) {
    const float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * vnoise(p);
        p = rot * p * 2.03 + float2(11.7, 5.3);
        amplitude *= 0.5;
    }
    return value;
}

// Five-octave fBM with rotation between octaves (kills axis-aligned artifacts).
inline float fbm(float2 p) {
    const float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * vnoise(p);
        p = rot * p * 2.03 + float2(11.7, 5.3);
        amplitude *= 0.5;
    }
    return value;
}


// Equirectangular lookup for a world-space direction — the convention the generated
// environment map is painted in (u = azimuth, v = 0 at zenith).
inline float2 equirectUV(float3 d) {
    float u = atan2(d.z, d.x) * (1.0 / 6.28318) + 0.5;
    float v = acos(clamp(d.y, -1.0, 1.0)) * (1.0 / 3.14159);
    return float2(u, v);
}

// Where a ray leaves a SOLID glass sphere, exactly: it refracts on the way in and again
// on the way out, and the sphere's symmetry makes the total deviation D = 2·(θi − θt).
// Rotating the incoming ray by −D inside the plane of incidence is the exit direction —
// which is why a real crystal ball shows the room magnified and upside down.
inline float3 sphereExitRay(float3 I, float3 N, float thetaI, float eta) {
    float sinT = min(sin(thetaI) / eta, 1.0);
    float D = 2.0 * (thetaI - asin(sinT));
    float3 axis = cross(I, N);
    float len = length(axis);
    if (len < 1e-4) { return I; }                       // dead centre: straight through
    axis /= len;
    // Rodrigues; the axis is perpendicular to I, so the parallel term vanishes.
    return normalize(I * cos(D) - cross(axis, I) * sin(D));
}

}

// The table: a séance surface rather than a flat plane.
//
// PERFORMANCE (2026-08-17): this shader covers the ENTIRE screen — 4 Mpx on an iPad Pro —
// so everything here is priced per-frame times four million. Three decisions follow from
// that: the material is UNLIT and multiplies a BAKED LIGHTMAP (the renderer paints the
// lamp pool and every candle's warmth into a 256² texture, so nine dynamic lights and a
// shadow-map lookup per pixel become one texture fetch); the expensive procedural work
// EARLY-OUTS past the lamp, where the cloth is black anyway and no detail can be seen;
// and the two fBMs are three-octave. Deep indigo nebula drifting very
// slowly, two engraved gold rings around the play area, sparse star points that twinkle,
// and a candle-pool vignette — all lit by the same light-angle uniform the cards use.
//   custom_parameter = (lightX, lightZ, time, 0)
[[visible]]
void tableSurface(realitykit::surface_parameters params)
{
    constexpr sampler lightSampler(address::clamp_to_edge, filter::linear);

    float4 knobs = params.uniforms().custom_parameter();
    float t = params.uniforms().time();
    float2 light = float2(knobs.x, knobs.y);

    // Model space, not UVs: every part of the table (slab, chamfer, apron, pedestal,
    // foot) is its own cylinder, and all of them are centred on the table's axis — so
    // model xz IS table space, and model y says where in the slab a fragment sits.
    float3 mp = params.geometry().model_position();
    float3 nrm = normalize(params.geometry().normal());
    float3 view = normalize(params.geometry().view_direction());
    float2 p = mp.xz;
    float r = length(p);
    float2 uv = p / 6.0 + 0.5;                    // where the lightmap was painted

    // ── The turned edge ─────────────────────────────────────────────────────────────
    // Anything not facing up is the table's THICKNESS: end grain running vertically and
    // a lit arris along the top. This is the surface that makes the table a solid you
    // could knock on rather than a picture of one.
    if (nrm.y < 0.55) {
        float ang = atan2(p.y, p.x);
        float endGrain = vnoise(float2(ang * 14.0, mp.y * 90.0)) * 0.6
                       + vnoise(float2(ang * 40.0, mp.y * 220.0)) * 0.4;
        half3 edge = mix(half3(0.020, 0.011, 0.006), half3(0.052, 0.028, 0.014),
                         half(endGrain));
        // The arris is the ONLY thing separating a black table from black air.
        float lip = smoothstep(-0.005, 0.045, mp.y);
        edge += half3(0.52, 0.38, 0.22) * half(lip * lip * 0.85);
        edge += half3((hash21(p * 913.7 + mp.y) - 0.5) / 255.0);
        params.surface().set_base_color(min(edge * half(2.0), half3(1.0)));
        params.surface().set_emissive_color(half3(0.0));
        params.surface().set_roughness(half(0.5));
        params.surface().set_metallic(half(0.0));
        params.surface().set_specular(half(0.3));
        params.surface().set_ambient_occlusion(half(1.0));
        params.surface().set_opacity(half(1.0));
        return;
    }

    // Crisp-line helper: distance→line with screen-derivative antialiasing, so every gold
    // hairline is 1–2 px sharp at any distance. NOTHING on this table is soft by design
    // (owner: "HQ, no soft") except the lighting itself.
    float aaBase = max(fwidth(r), 0.0008);

    // ── Cloth over wood ─────────────────────────────────────────────────────────────
    // How a reading table is actually dressed (owner, and the altar-cloth references
    // agree): a velvet cloth laid over dark timber, the bare wood showing at the rim.
    // The cloth carries the embroidery; the wood carries the grain.
    const float clothR = 1.48;
    float onCloth = 1.0 - smoothstep(clothR - 1.5 * aaBase, clothR + 1.5 * aaBase, r);

    half3 color;
    if (onCloth > 0.5) {
        // VELVET: a woven pile, a nap that blotches the tone, and the retroreflective
        // sheen that glows where the cloth turns away from the eye — the three cues that
        // separate cloth from painted plastic.
        float2 weaveP = p * 260.0;
        float weave = mix(sin(weaveP.x) * 0.5 + 0.5, sin(weaveP.y) * 0.5 + 0.5, 0.5) * 0.5
                    + vnoise(p * 190.0) * 0.5;
        float nap = fbm3(p * 3.2 + float2(t * 0.004, -t * 0.003));
        float tone = fbm3(p * 0.6 + float2(t * 0.008, -t * 0.005));
        color = half3(0.038, 0.031, 0.070);
        color = mix(color, half3(0.086, 0.055, 0.135), half(0.42 * smoothstep(0.45, 0.95, tone)));
        color *= half(0.90 + 0.20 * nap);
        color *= half(1.0 + (weave - 0.5) * 0.13);
        float sheen = pow(1.0 - saturate(dot(nrm, view)), 3.2);
        color += half3(0.30, 0.22, 0.42) * half(sheen * 0.30 * (0.7 + 0.3 * weave));

        // Hairline diamond lattice in gold thread, echoing the deck back (45°, 12 cm).
        float2 q = float2(p.x + p.y, p.x - p.y) * 0.70710678;
        float2 cellDist = abs(fract(q / 0.12) - 0.5) * 0.12;
        float latticeDist = min(cellDist.x, cellDist.y);
        float aaLat = max(fwidth(latticeDist), 0.0008);
        float lattice = 1.0 - smoothstep(0.0, 1.6 * aaLat, latticeDist - 0.0006);
        float stitchLat = 0.72 + 0.28 * sin((q.x + q.y) * 210.0);
        color += half3(0.62, 0.50, 0.28) * half(lattice * 0.085 * stitchLat);

        // Stars: sharp pinpoints with a four-ray flare, twinkling on private phases.
        float2 g = p * 3.0;
        float2 cell = floor(g);
        float2 fp = fract(g) - 0.5;
        float lit = step(0.93, hash21(cell));
        float2 starOffset = (float2(hash21(cell + 5.0), hash21(cell + 9.0)) - 0.5) * 0.6;
        float2 dvec = fp - starOffset;
        float dstar = length(dvec);
        float tw = pow(0.5 + 0.5 * sin(t * (0.6 + hash21(cell + 3.0))
                                       + hash21(cell + 31.0) * 6.28318), 3.0);
        float pin = exp2(-9000.0 * dstar * dstar);
        float flare = exp2(-(220.0 * dvec.x * dvec.x + 22000.0 * dvec.y * dvec.y))
                    + exp2(-(22000.0 * dvec.x * dvec.x + 220.0 * dvec.y * dvec.y));
        color += half3(1.0, 0.94, 0.78) * half(lit * (pin + flare * 0.22) * tw);
    } else {
        // WALNUT: planks across the table, growth rings warped by fBM so they never read
        // as tidy circles, fibre along the plank, and a restrained lacquer sheen.
        float plankWidth = 0.62;
        float plankIndex = floor((p.y + 3.0) / plankWidth);
        float plankPhase = hash21(float2(plankIndex, 3.7)) * 9.0;
        float seamDist = abs(fract((p.y + 3.0) / plankWidth) - 0.5) * plankWidth;
        float aaSeam = max(fwidth(seamDist), 0.0008);
        float seam = 1.0 - smoothstep(0.0, 2.2 * aaSeam, seamDist - 0.0015);
        float2 ringP = float2(p.x * 0.9 + plankPhase * 2.1, p.y * 0.30);
        float rings = fract(length(ringP - float2(-2.6, 0.0)) * 5.2
                            + fbm3(ringP * 1.2) * 1.7 + plankPhase);
        float ringBand = smoothstep(0.02, 0.42, rings) * (1.0 - smoothstep(0.52, 0.98, rings));
        float grain = vnoise(float2(p.x * 7.0 + plankPhase, p.y * 150.0)) * 0.62
                    + vnoise(float2(p.x * 19.0, p.y * 380.0)) * 0.38;
        half3 heartwood = half3(0.013, 0.0065, 0.0035);
        color = mix(heartwood, half3(0.038, 0.020, 0.0095), half(ringBand));
        color *= half(0.88 + 0.24 * grain);
        color = mix(color, heartwood * half(0.5), half(seam * 0.85));
        float sheen = pow(1.0 - saturate(dot(nrm, view)), 4.0);
        color += half3(0.42, 0.30, 0.17) * half(sheen * 0.035);
    }

    // The hem: cloth has thickness, so it shades the wood just outside it and catches a
    // thread of light along its own fold.
    float hemDist = abs(r - clothR);
    color *= half(1.0 - 0.45 * exp2(-hemDist * hemDist * 2600.0) * (1.0 - onCloth));
    color += half3(0.34, 0.27, 0.36) * half(exp2(-hemDist * hemDist * 9000.0) * onCloth * 0.30);

    // Engraved rings: crisp cores with the faintest halo, embroidered into the cloth.
    float dRing1 = abs(r - 1.05);
    float dRing2 = abs(r - 0.72);
    float ringCore = (1.0 - smoothstep(0.0, 2.0 * aaBase, dRing1 - 0.0012))
                   + (1.0 - smoothstep(0.0, 2.0 * aaBase, dRing2 - 0.0010));
    float ringHalo = 0.05 * exp2(-1500.0 * dRing1 * dRing1)
                   + 0.03 * exp2(-2000.0 * dRing2 * dRing2);
    float stitchRing = 0.68 + 0.32 * sin(atan2(p.y, p.x) * 420.0);
    color += half3(0.88, 0.72, 0.40) * half(ringCore * 0.55 * stitchRing + ringHalo);

    // 48 crisp radial ticks between the rings — the astrolabe.
    float ang = atan2(p.y, p.x) / 6.28318 + 0.5;
    float tickDist = abs(fract(ang * 48.0) - 0.5) * (6.28318 / 48.0) * r;
    float aaTick = max(fwidth(tickDist), 0.0008);
    float tick = 1.0 - smoothstep(0.0, 1.6 * aaTick, tickDist - 0.0008);
    float tickBand = step(0.80, r) * (1.0 - step(0.97, r));
    color += half3(0.80, 0.65, 0.36) * half(tick * tickBand * 0.16);

    // THE LIGHTMAP. The renderer bakes the hanging lamp's pool and every candle's warmth
    // into one texture — exact positions, no drift, since it is painted from the same
    // PropPlacement the props are built from. It multiplies AFTER every additive
    // engraving, so lattice, ticks and stars sink into the dark with the cloth. One fetch
    // replaces nine dynamic lights and a shadow-map lookup, on every pixel.
    half3 lightmap = params.textures().custom().sample(lightSampler, uv).rgb;
    float breath = 0.94 + 0.06 * sin(t * 0.9);
    // Exposure. Every colour above was authored as ALBEDO for a lit material — the light
    // rig used to supply this factor, and unlit the shader owns it. 15.5 is measured, not
    // guessed: the ratio between this frame and the approved pre-optimisation one,
    // sampled on bare cloth at four points.
    color *= lightmap * half(breath * 15.5);
    color += half3((hash21(p * 913.7) - 0.5) / 255.0);

    params.surface().set_base_color(min(color, half3(1.0)));
    params.surface().set_emissive_color(half3(0.88, 0.72, 0.40) * half(ringCore * 0.18 + ringHalo * 0.3)
                                        + color * half(0.10));
    params.surface().set_roughness(half(0.86) - half(onCloth * 0.0));
    params.surface().set_metallic(half(0.0));
    params.surface().set_ambient_occlusion(half(1.0));
    params.surface().set_specular(half(0.12));
    params.surface().set_opacity(half(1.0));
}

[[visible]]
void cardFoilSurface(realitykit::surface_parameters params)
{
    constexpr sampler linearSampler(address::repeat, filter::linear,
                                    mip_filter::linear, max_anisotropy(8));

    float2 uv = params.geometry().uv0();
    float4 knobs = params.uniforms().custom_parameter();
    float2 light = float2(knobs.x, knobs.y);
    float tier = knobs.w;

    half4 base = params.textures().base_color().sample(linearSampler, uv);
    half4 mask = params.textures().custom().sample(linearSampler, uv);

    float lightLen = length(light);
    float2 lightDir = lightLen > 0.001 ? light / lightLen : float2(0.707, 0.707);

    // 1 — rainbow streak: a band that sweeps across the card as the light angle moves.
    //     The uv term and the light term move at different rates (2.6/3.5-style counter
    //     motion) so the sheen reads as *under* the surface, not painted on it.
    float band = dot(uv - 0.5, lightDir) * 7.0 + dot(light, float2(2.6, 3.5));
    float streak = exp2(-3.0 * band * band);             // narrow gaussian band
    half3 rainbow = spectral(band * 0.35 + mask.g * 0.8) * half(streak);

    // 2 — sparkle: hashed cells fire when their private direction aligns with the light.
    float2 cell = floor(uv * float2(42.0, 72.0));
    float2 cellDir = normalize(float2(hash21(cell) - 0.5, hash21(cell + 17.0) - 0.5) + 0.001);
    float glint = pow(saturate(dot(cellDir, lightDir)), 24.0) * step(0.55, hash21(cell + 3.0));
    half3 sparkle = half3(1.0, 0.95, 0.85) * half(glint * (0.4 + 0.6 * lightLen));

    // 3 — thin-film hue for majors: film thickness (mask.G) + view sweep picks the color.
    half3 film = spectral(float(mask.g) * 2.2 + dot(light, float2(0.9, 1.3)) * 0.6)
               * half(0.5 + 0.5 * lightLen);
    float filmOn = step(1.5, tier);                       // majors only

    // Relief (mask.B) breaks the streak like etched lines.
    float relief = 1.0 - 0.55 * float(mask.b);

    half foil = mask.r;
    half3 shine = (rainbow * 0.85 + sparkle) * half(relief);
    // Weights tuned in the simulator: the first cut (0.9 / 0.35) drowned the major-arcana
    // art in rainbow — foil must decorate the illustration, not replace it.
    half3 color = base.rgb
                + shine * foil * half(0.55)
                + film * foil * half(filmOn) * half(0.16);

    params.surface().set_base_color(min(color, half3(1.0)));
    // Foil regions glow faintly so bloom-less lighting still reads as metal under sweep.
    params.surface().set_emissive_color((shine * foil) * half(0.25));
    params.surface().set_roughness(half(0.65) - foil * half(0.35));
    params.surface().set_metallic(foil * half(0.55));
    params.surface().set_ambient_occlusion(half(1.0));
    params.surface().set_specular(half(0.3));
    params.surface().set_opacity(base.a);
}

// ── The séance props (2026-08-17 redesign) ─────────────────────────────────────────────
// One shading language across the scene: every prop reads the same uniform convention the
// cards and table use — custom_parameter = (lightX, lightZ, presentationTime, extra) —
// so the crystal ball's glint and the foil's streak answer the same physical tilt, and
// candle flames flicker on the same clock as their point lights.

// Wax: cream body, vertical drip relief, and a warm subsurface glow strongest just under
// the flame — the translucency of a real candle, faked in one gradient.
//   custom_parameter = (lightX, lightZ, flickerPhase, —); time is RealityKit's own
[[visible]]
void candleWax(realitykit::surface_parameters params)
{
    float2 uv = params.geometry().uv0();                   // u wraps, v runs up the body
    float4 knobs = params.uniforms().custom_parameter();
    float t = params.uniforms().time();
    float phase = knobs.z;

    // Vertical drip streaks: tall thin noise, sharpened into ridges.
    float streak = vnoise(float2(uv.x * 22.0, uv.y * 2.6));
    float ridge = smoothstep(0.35, 0.75, streak);
    float fine = vnoise(float2(uv.x * 90.0, uv.y * 14.0));

    half3 cream = half3(0.90, 0.85, 0.74);
    half3 crevice = half3(0.72, 0.65, 0.53);
    half3 color = mix(crevice, cream, half(0.55 + 0.45 * ridge));
    color *= half(0.96 + 0.08 * fine);

    // Subsurface fake: the top of the body glows with the flame's own flicker, decaying
    // down the candle exactly the way light dies inside real wax.
    float flick = 1.0 + 0.10 * sin(t * 7.3 + phase) + 0.07 * sin(t * 11.9 + 1.3 + phase);
    float top = pow(saturate(uv.y), 3.0);
    half3 subsurface = half3(1.0, 0.52, 0.16) * half(top * 0.55 * flick);

    // Fresnel rim: wax softens at grazing angles instead of cutting a hard silhouette.
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float rim = pow(1.0 - saturate(dot(n, v)), 2.5);
    subsurface += half3(1.0, 0.62, 0.28) * half(rim * top * 0.35 * flick);

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(subsurface);
    params.surface().set_roughness(half(0.55 - 0.25 * ridge));
    params.surface().set_metallic(half(0.0));
    params.surface().set_specular(half(0.35));
    params.surface().set_ambient_occlusion(half(1.0));
    params.surface().set_opacity(half(1.0));
}

// Flame sway: the quad's tip leans on two incommensurate sines; the base stays anchored
// to the wick. Runs on the same clock/phase the wax and the point light use.
//   custom_parameter = (lightX, lightZ, flickerPhase, —); time is RealityKit's own
[[visible]]
void candleFlameSway(realitykit::geometry_parameters params)
{
    float2 uv = params.geometry().uv0();
    float4 knobs = params.uniforms().custom_parameter();
    float t = params.uniforms().time();
    float phase = knobs.z;
    float grip = uv.y * uv.y;                              // 0 at the wick, 1 at the tip
    float3 offset = float3(sin(t * 6.1 + phase) * 0.010 + sin(t * 9.7 + phase * 2.0) * 0.006,
                           0.0,
                           cos(t * 7.9 + phase) * 0.007);
    params.geometry().set_model_position_offset(offset * grip);
}

// The flame itself. EVERY falloff here is a gaussian and the whole thing is multiplied
// by an edge fade, because the first cut clamped (`saturate(1-d)`) and the clamp drew a
// hard-edged block — the "squares on the flames" the owner saw on device. Fire has no
// hard edge anywhere: a white heart, an amber body, a wide soft halo, a blue seed.
//   custom_parameter = (lightX, lightZ, flickerPhase, —); time is RealityKit's own
[[visible]]
void candleFlame(realitykit::surface_parameters params)
{
    float2 uv = params.geometry().uv0();
    float4 knobs = params.uniforms().custom_parameter();
    float t = params.uniforms().time();
    float phase = knobs.z;
    float flick = 1.0 + 0.16 * sin(t * 7.3 + phase) + 0.10 * sin(t * 11.9 + 1.3 + phase);

    // Flame space: x centred on the wick, y from wick (0) to the top of the quad (1).
    // The fire occupies the lower ~0.62 so its halo has room to fade inside the quad.
    float2 f = float2((uv.x - 0.5) * 2.0, uv.y / 0.62);
    float sway = sin(t * 5.3 + phase) * 0.05 * f.y * f.y;      // the tip leans as it burns
    f.x -= sway;

    // Teardrop: widest a third up, tapering to a point — as a smooth field, never a step.
    float taper = 1.0 - smoothstep(0.05, 1.05, f.y);
    float width = (0.34 * taper + 0.05) * (0.94 + 0.06 * flick);
    float across = f.x / max(width, 0.001);
    float along = smoothstep(-0.05, 0.16, f.y) * (1.0 - smoothstep(0.72, 1.12, f.y));
    float body = exp2(-2.6 * across * across) * along;

    // Turbulence erodes the outline so the edge licks instead of sitting still.
    float lick = fbm3(float2(f.x * 2.6, f.y * 2.2 - t * 2.1) + phase);
    body *= 0.72 + 0.55 * lick;

    // The white heart, and a wide warm halo that carries the glow well past the body.
    float heart = exp2(-9.0 * across * across)
                * smoothstep(0.02, 0.30, f.y) * (1.0 - smoothstep(0.34, 0.78, f.y));
    float halo = exp2(-(1.5 * f.x * f.x * 4.0 + 0.9 * (f.y - 0.42) * (f.y - 0.42) * 2.2));

    // The guarantee: whatever the maths above says, everything dies before the quad does.
    float edge = smoothstep(0.0, 0.16, uv.x) * (1.0 - smoothstep(0.84, 1.0, uv.x))
               * smoothstep(0.0, 0.05, uv.y) * (1.0 - smoothstep(0.80, 1.0, uv.y));

    float fire = body * flick * edge;
    float glow = halo * 0.42 * flick * edge;

    half3 color = half3(0.30, 0.42, 1.0) * half(exp2(-14.0 * across * across)
                                                * (1.0 - smoothstep(0.0, 0.13, f.y)) * 0.8 * edge)
                + half3(1.0, 0.36, 0.06) * half(glow)
                + half3(1.0, 0.60, 0.16) * half(fire)
                + half3(1.0, 0.94, 0.80) * half(heart * flick * edge * 1.15);

    params.surface().set_base_color(half3(0.0));
    params.surface().set_emissive_color(color * half(1.9));
    params.surface().set_roughness(half(1.0));
    params.surface().set_metallic(half(0.0));
    params.surface().set_specular(half(0.0));
    params.surface().set_opacity(half(saturate(fire * 1.5 + glow * 0.85 + heart)));
}

// The crystal ball — real glass, not a painted bauble (owner, 2026-08-17: "should
// reflect refract"). The renderer paints an equirectangular map of THIS room (lamp
// above, gold circle and cloth below, candle flames around) and hands it over as the
// custom texture; the shader then does what glass does:
//   • reflects the room off the surface, weighted by Fresnel;
//   • refracts THROUGH the solid sphere with the exact two-surface deviation, so the
//     room appears magnified and upside down inside — the crystal-ball signature;
//   • splits that refraction into R/G/B at slightly different indices, which is the
//     rainbow fringing real glass shows at its rim.
//   custom_parameter = (lightX, lightZ, —, —); time is RealityKit's own
//   custom texture   = the room, equirectangular
[[visible]]
void crystalBall(realitykit::surface_parameters params)
{
    constexpr sampler envSampler(address::repeat, filter::linear, mip_filter::linear);

    float4 knobs = params.uniforms().custom_parameter();
    float2 light = float2(knobs.x, knobs.y);
    float t = params.uniforms().time();
    // The heart breathes on the shared clock — nothing to push from the CPU.
    float breath = 0.5 + 0.5 * sin(t * 0.35);

    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());   // fragment → eye
    float cosI = saturate(dot(n, v));
    float thetaI = acos(clamp(cosI, -1.0, 1.0));

    // Schlick, with glass's F0 — the rim goes mirror while the centre stays a window.
    float fres = 0.06 + 0.94 * pow(1.0 - cosI, 5.0);

    // Refraction with dispersion: three indices, three exit rays, three channels.
    float3 I = -v;
    float3 exitR = sphereExitRay(I, n, thetaI, 1.505);
    float3 exitG = sphereExitRay(I, n, thetaI, 1.522);
    float3 exitB = sphereExitRay(I, n, thetaI, 1.545);
    half3 refracted = half3(
        params.textures().custom().sample(envSampler, equirectUV(exitR)).r,
        params.textures().custom().sample(envSampler, equirectUV(exitG)).g,
        params.textures().custom().sample(envSampler, equirectUV(exitB)).b);

    // Reflection of the same room off the glass.
    half3 reflected = params.textures().custom()
        .sample(envSampler, equirectUV(reflect(-v, n))).rgb;

    // A breath of the arcane still lives inside: a slow nebula and a few sparks, riding
    // the refracted ray so they swim as the ball is looked around.
    float2 ic = exitG.xz / (abs(exitG.y) + 0.9) * 2.2 + float2(t * 0.012, -t * 0.009);
    float neb = fbm(ic * 1.5);
    half3 inner = mix(half3(0.06, 0.04, 0.13), half3(0.30, 0.16, 0.46),
                      half(smoothstep(0.40, 0.90, neb)));
    float2 cell = floor(ic * 5.0);
    float2 fp = fract(ic * 5.0) - 0.5;
    float lit = step(0.90, hash21(cell));
    float ds = length(fp - (float2(hash21(cell + 5.0), hash21(cell + 9.0)) - 0.5) * 0.5);
    float tw = pow(0.5 + 0.5 * sin(t * (0.8 + hash21(cell + 3.0)) + hash21(cell) * 6.28), 2.0);
    inner += half3(0.95, 0.90, 1.0) * half(lit * exp2(-300.0 * ds * ds) * tw * 0.8);
    inner += half3(0.62, 0.42, 0.95) * half(pow(cosI, 3.0) * (0.10 + 0.22 * breath));

    // The specular the whole scene shares: the same tilt/cursor light the foil answers.
    float3 l = normalize(float3(light.x, 1.15, light.y));
    float3 h = normalize(l + v);
    float glint = pow(saturate(dot(n, h)), 200.0);
    float sheen = pow(saturate(dot(n, h)), 14.0) * 0.08;

    half3 color = mix(refracted * half(0.82) + inner * half(0.55), reflected, half(fres))
                + half3(1.0, 0.97, 0.90) * half(glint * 1.6 + sheen);

    params.surface().set_base_color(min(color, half3(1.0)));
    params.surface().set_emissive_color(inner * half(0.22)
                                        + half3(1.0, 0.97, 0.90) * half(glint * 0.7));
    params.surface().set_roughness(half(0.03));
    params.surface().set_metallic(half(0.0));
    params.surface().set_specular(half(1.0));
    params.surface().set_ambient_occlusion(half(1.0));
    params.surface().set_opacity(half(1.0));
}

// The caustic the ball throws on the cloth: a warm ellipse with a bright waist, faded by
// the same breath as the ball's heart. Unlit-style — all emission, transparent edges.
//   custom_parameter = (lightX, lightZ, —, —); time is RealityKit's own
[[visible]]
void crystalCaustic(realitykit::surface_parameters params)
{
    float2 uv = params.geometry().uv0();
    float breath = 0.5 + 0.5 * sin(params.uniforms().time() * 0.35);
    float2 p = (uv - 0.5) * float2(2.2, 2.0);
    float r = length(p);
    float pool = exp(-r * r * 3.2);
    float waist = exp(-r * r * 14.0);
    half3 color = half3(1.0, 0.85, 0.55) * half(pool * 0.35 + waist * 0.45) * half(0.7 + 0.3 * breath);
    params.surface().set_base_color(half3(0.0));
    params.surface().set_emissive_color(color);
    params.surface().set_roughness(half(1.0));
    params.surface().set_metallic(half(0.0));
    params.surface().set_specular(half(0.0));
    params.surface().set_opacity(half(saturate(pool * 0.5 + waist * 0.5)));
}

// A card's contact shadow. With the cloth unlit there is no shadow map to receive, and
// for a card lying flat on a table a real shadow would be a hidden sliver anyway — what
// the eye actually reads is the soft darkening under a LIFTED card, which this draws for
// a few pennies. (froggo2's analytic blob shadow, generalised to every played card.)
[[visible]]
void softBlob(realitykit::surface_parameters params)
{
    float2 uv = params.geometry().uv0();
    float2 d = (uv - 0.5) * 2.0;
    float r = length(d * float2(1.0, 0.94));
    float a = exp2(-3.2 * r * r) * (1.0 - smoothstep(0.80, 1.0, r));
    params.surface().set_base_color(half3(0.0));
    params.surface().set_emissive_color(half3(0.0));
    params.surface().set_roughness(half(1.0));
    params.surface().set_metallic(half(0.0));
    params.surface().set_specular(half(0.0));
    params.surface().set_ambient_occlusion(half(1.0));
    params.surface().set_opacity(half(a * 0.62));
}
