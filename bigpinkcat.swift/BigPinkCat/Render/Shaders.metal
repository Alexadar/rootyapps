#include <metal_stdlib>
using namespace metal;

// Two passes, and the split matters more than either of them.
//
//   1. A full-screen relativistic pass — the sky, seen through curved spacetime.
//   2. Instanced primitives — the cosmonaut, the cat, the machinery, the portals.
//
// Neither owns a rule. Everything here is a **read-only viewer over engine state**: the renderer
// runs no physics and holds no game state beyond what arrives in a Snapshot. Delete this file and
// the simulation still runs, still tests and still sweeps — the property that keeps the two from
// tangling, inherited from citypigeon/CityPigeon/Render/Renderer.swift.
//
// The Tier-1 lensing below is SCREEN-SPACE: it bends what you see, not where things are. That is
// deliberate for the early demos and is not the destination — world-space curvature lives in
// RelativityKit, where entities and photons integrate as geodesics through the same function, and
// this pass is then fed by it rather than approximating it.

// NOT `packed_float3`. Swift's `SIMD3<Float>` is 16-byte aligned with a stride of 16 while
// `packed_float3` is 12, so a packed layout here makes the Swift struct and the Metal struct
// different sizes and every colour and flag reads shifted garbage. Plain `float3` matches Swift.
struct Instance {
    float3 center;
    float3 halfExtent;
    float4 color;
    // x: emissive lift.  y: unused.  z: unused.  w: unused.
    float4 flags;
};

struct Uniforms {
    float4x4 viewProjection;
    float3 lightDirection;
    float ambient;
    float3 fogColor;
    float fogDensity;
};

// Relativistic scene parameters. All in geometrized units (G = c = M = 1) so they match
// RelativityKit exactly and no conversion can go missing between the two.
struct Relativity {
    float2 holeCenterNDC;   // where the hole projects on screen
    float  spin;            // a, dimensionless, |a| <= 1
    float  mass;            // M, always 1 in these units; present so the shader reads like the maths
    float  outerHorizon;    // r+ = M + sqrt(M^2 - a^2)
    float  ergosphereEq;    // static limit in the equatorial plane, always 2M
    float  photonSphere;    // 3M for Schwarzschild
    float  photonPrograde;  // r_ph co-rotating   — 3M at a=0, 1M at a=1  (BPT 1972)
    float  photonRetro;     // r_ph counter-rotating — 3M at a=0, 4M at a=1
    float  lensStrength;    // deflection scale in screen space
    float  bubbleRadiusNDC; // Alcubierre bubble wall, 0 = no bubble
    float  observerRedshift;// sqrt(1 - 2M/r) at the camera
    float  aspect;
    float  time;
    // The REAL camera, shared with the primitive pass.
    //
    // These two passes previously disagreed: the shader hardcoded a camera at r = 18 with its own
    // field of view while the cubes used Snapshot.camera. The scene then composited two different
    // viewpoints, and a body correctly placed at the ISCO rendered INSIDE the shadow — it looked
    // like a depth bug and was a camera bug. One camera, fed from one place.
    float3 camEye;
    float3 camRight;
    float3 camUp;
    float3 camForward;
    float  tanHalfFov;
    float  integrationSteps;   // RK4 steps per pixel; the thermal control
};

// ── Full-screen relativistic pass ────────────────────────────────────────────────────────────

struct FSOut {
    float4 position [[position]];
    float2 ndc;
};

vertex FSOut fullscreen_vertex(uint vid [[vertex_id]])
{
    // One oversized triangle, not a quad: no diagonal seam, one fewer vertex, and no index buffer.
    float2 p = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? 3.0 : -1.0);
    FSOut out;
    out.position = float4(p, 1.0, 1.0);
    out.ndc = p;
    return out;
}

// A cheap star field. Deterministic from the direction, so it does not swim when the camera moves —
// which is the failure mode of hashing screen coordinates instead of world directions.
static float starField(float2 dir)
{
    float2 g = floor(dir * 220.0);
    float h = fract(sin(dot(g, float2(127.1, 311.7))) * 43758.5453);
    return smoothstep(0.9975, 1.0, h);
}

// The 3-D version, hashed on the direction vector itself.
//
// The 2-D form above takes an equirectangular (atan2, asin) UV, and near the poles that mapping
// stretches without bound: a square cell in UV becomes a long thin sliver on the sphere, so the
// star field renders as white DASHES toward the top and bottom of frame rather than as points.
// It reads convincingly like lensing, which is what makes it worth naming — it is not, it is a
// projection artefact, and it appears exactly where the physics is doing nothing interesting.
//
// Hashing the unit direction in three dimensions has no poles, so cells stay isotropic everywhere.
static float starField3(float3 d)
{
    float3 g = floor(d * 190.0);
    float h = fract(sin(dot(g, float3(127.1, 311.7, 74.7))) * 43758.5453);
    return smoothstep(0.9972, 1.0, h);
}

fragment float4 relativistic_fragment(FSOut in [[stage_in]],
                                      constant Relativity &rel [[buffer(0)]],
                                      constant float4 *palette [[buffer(1)]])
{
    // palette[0] skyFar, [1] skyDeep, [2] horizon, [3] ergosphere,
    // [4] bubbleWall, [5..9] redshift ramp far→deep.
    float2 p = in.ndc - rel.holeCenterNDC;
    p.x *= rel.aspect;
    float r = length(p);

    // Weak-field deflection. The exact statement is alpha = 4GM/(c^2 b); in screen space the
    // impact parameter b is proportional to r, so the sample offset goes as 1/r along the radial
    // direction. ORACLE: Eddington 1919, and RelativityKitTests pins the same law to 1%.
    float deflection = rel.lensStrength / max(r, 1e-3);
    float2 dir = (r > 1e-6) ? (p / r) : float2(0.0, 0.0);
    float2 sampled = p - dir * deflection;

    // Sky, lensed.
    float3 sky = mix(palette[1].rgb, palette[0].rgb, saturate(length(sampled) * 0.5));
    sky += starField(sampled) * float3(1.0, 0.97, 0.92);

    // ── Units ────────────────────────────────────────────────────────────────────────────────
    //
    // `r` above is a SCREEN radius in NDC (0 at the hole's centre, ~2.4 in a corner). Everything
    // arriving in `rel` is a GEOMETRIZED radius in units of M (r+ = 1.6, photon sphere 3, ISCO 6).
    // Those are different quantities and mixing them is not a small error: the first build wrote
    // `saturate(outerHorizon / r)`, which saturated to 1 across the entire frame, and paired it
    // with a reversed smoothstep — so the whole screen came out flat #4C495F, exactly
    // Palette.ergosphere, and looked like a colour-space bug rather than a units bug.
    //
    // One explicit conversion, used everywhere below, and no geometrized value touches `r` raw.
    const float ndcPerM = 0.06;
    float rM = r / ndcPerM;                    // the screen radius, expressed in units of M

    // Gravitational redshift of everything behind the hole. 1 + z = (1 - 2M/r)^(-1/2), so the ramp
    // is indexed by how deep in the potential the light we are seeing had to climb from. Zero far
    // away, one at the horizon.
    float depth = saturate(rel.outerHorizon / max(rM, rel.outerHorizon));
    float t = clamp(depth * 4.0, 0.0, 3.99);
    int idx = int(t);
    float3 shifted = mix(palette[5 + idx].rgb, palette[6 + idx].rgb, t - float(idx));
    sky = mix(sky, shifted, depth * 0.85);

    // The photon sphere reads as a bright ring: light that orbited before escaping. Purely a
    // highlight here — the real Einstein ring comes out of the geodesic pass in Tier 2.
    float ring = exp(-pow((rM - rel.photonSphere) * 2.4, 2.0));
    sky += palette[3].rgb * ring * 0.55;

    // The ergosphere, where no static observer exists. `smoothstep` REQUIRES edge0 < edge1;
    // reversed edges are undefined and were returning 0 everywhere. Written the correct way round
    // and then inverted explicitly, which is also easier to read than relying on the reversal.
    float ergo = 1.0 - smoothstep(rel.outerHorizon, rel.ergosphereEq, rM);
    sky = mix(sky, palette[3].rgb, ergo * 0.55);

    // The horizon itself. Not pure black: a true #000000 hole against a dark scene reads as a
    // rendering failure rather than as a hole.
    float inside = 1.0 - smoothstep(rel.outerHorizon * 0.97, rel.outerHorizon * 1.03, rM);
    sky = mix(sky, palette[2].rgb, inside);

    // ── The bubble wall ──────────────────────────────────────────────────────────────────────
    //
    // Inside an Alcubierre bubble spacetime is FLAT and the occupants are inertial: no tidal
    // force, no time dilation, clocks ticking with a distant observer's. So the interior is drawn
    // undistorted and calm, and the wall is where the universe goes insane. The whole hero image
    // is that boundary, and it is a real feature of the metric rather than a vignette.
    if (rel.bubbleRadiusNDC > 0.0) {
        float2 q = in.ndc;
        q.x *= rel.aspect;
        float rq = length(q);
        float wall = abs(rq - rel.bubbleRadiusNDC);
        float interior = smoothstep(rel.bubbleRadiusNDC, rel.bubbleRadiusNDC * 0.97, rq);
        // Flat interior: undo the lensing entirely, because inside the bubble there is none.
        float3 flat = mix(palette[1].rgb, palette[0].rgb, saturate(length(q) * 0.5));
        flat += starField(q) * 0.35;
        sky = mix(sky, flat, interior * 0.92);
        // The wall glows: infalling radiation blueshifts catastrophically there, which is also
        // exactly where the exotic-matter shell the engineer maintains actually lives.
        sky += palette[4].rgb * exp(-wall * 90.0) * 0.9;
    }

    return float4(sky * rel.observerRedshift, 1.0);
}

// ── The geodesic pass: real world-space lensing ──────────────────────────────────────────────
//
// Tier 2. Where `relativistic_fragment` above offsets a texture lookup, this integrates the actual
// null-geodesic orbit equation for every pixel and reports where that photon came from. The
// difference is not cosmetic: this produces multiple images, the photon ring, and capture — the
// things a screen-space offset cannot produce at any tuning.
//
// Schwarzschild, in the plane containing the camera and the ray (every geodesic is planar, because
// the Killing symmetry conserves the orbital angular momentum). With u = 1/r and M = 1:
//
//     d²u/dφ² = -u + 3u²
//
// ORACLE: the Newtonian term alone gives a straight line; the 3u² term is what yields α = 4M/b in
// the weak field, which RelativityKitTests pins to 1% against Eddington 1919 with the SAME equation
// integrated on the CPU. The two are independent implementations of one published law, which is
// exactly the cross-check `docs/calculators_VALIDATION.md` asks for.
//
// Marching is by a FIXED step count. An adaptive controller would be faster, but this is the
// renderer: a variable schedule here costs reproducibility of a captured frame and buys nothing
// the eye can see.

// The REAL Kerr geodesic integrator, in the same Hamiltonian tensor form as RelativityKit.
//
// The first version of this pass solved d^2u/dphi^2 = -u + 3u^2 — the scalar, equatorial,
// Schwarzschild reduction. It is the standard textbook shortcut, it produces a convincing shadow,
// and it is NOT what the Kit computes. Two different physics implementations, only one of them
// tested, and the one on screen was the untested one. That is precisely the failure the oracle
// discipline exists to prevent, so the shortcut is gone.
//
// What runs now is the same thing RelativityKitTests pins against Carter 1968:
//
//     H = 1/2 g^{mu nu} p_mu p_nu
//     dx^mu/dlambda  =  g^{mu nu} p_nu
//     dp_mu/dlambda  = -1/2 (d_mu g^{alpha beta}) p_alpha p_beta
//
// with state (t, r, theta, phi, p_t, p_r, p_theta, p_phi) in Boyer-Lindquist coordinates. p_t and
// p_phi have identically zero derivatives — the two Killing vectors — so E and L_z are conserved
// structurally here exactly as they are on the CPU.
//
// `GeodesicParityTests` integrates the same initial conditions through RelativityKit and fails if
// the two disagree beyond RK4 truncation. The renderer is now answerable to the oracle.

struct KerrInv {
    float gtt, gtp, gpp, grr, gthth;
    float dr_gtt, dr_gtp, dr_gpp, dr_grr, dr_gthth;
    float dth_gtt, dth_gtp, dth_gpp, dth_grr, dth_gthth;
};

// Transliterated from KerrMetric.inverse(). Geometrized units, M = 1.
static KerrInv kerrInverse(float r, float th, float a)
{
    float sn = sin(th), cs = cos(th);
    float s2 = sn * sn, aa = a * a;

    float sig = r * r + aa * cs * cs;
    float del_raw = r * r - 2.0 * r + aa;
    // REGULARISED Delta.
    //
    // Boyer-Lindquist is singular at the horizons (Delta = 0): g^rr vanishes and g^tt diverges, so
    // a BL integrator cannot cross r+ at all. That is a COORDINATE singularity, not a physical
    // one — the spacetime is perfectly smooth there — but it is why the interior renders as a flat
    // disc rather than as anything.
    //
    // Softening |Delta| away from zero lets rays continue through and produces the correct
    // qualitative interior: the exterior sky compressing toward the outward direction, and the
    // region past the Cauchy horizon becoming reachable.
    //
    // MODEL CAVEAT: near r+ this is an approximation, and the proper fix is a coordinate change to
    // ingoing Kerr / Kerr-Schild, which are horizon-penetrating by construction. Quantities
    // computed strictly OUTSIDE the horizon are unaffected — eps only bites within ~0.02M of a
    // root — so every oracle the Kit pins still holds where it is tested.
    float eps = 0.02;
    float del = (abs(del_raw) < eps) ? (del_raw >= 0.0 ? eps : -eps) : del_raw;
    float r2a2 = r * r + aa;
    float bigA = r2a2 * r2a2 - aa * del * s2;

    float dsig_dr = 2.0 * r;
    float dsig_dth = -2.0 * aa * cs * sn;
    float ddel_dr = 2.0 * r - 2.0;
    float dA_dr = 4.0 * r * r2a2 - aa * s2 * ddel_dr;
    float dA_dth = -aa * del * (2.0 * sn * cs);

    float sd = sig * del;
    float dsd_dr = dsig_dr * del + sig * ddel_dr;
    float dsd_dth = dsig_dth * del;
    float sd2 = sd * sd;

    KerrInv g;
    g.gtt = -bigA / sd;
    g.dr_gtt = -(dA_dr * sd - bigA * dsd_dr) / sd2;
    g.dth_gtt = -(dA_dth * sd - bigA * dsd_dth) / sd2;

    float num_tp = -2.0 * a * r;
    g.gtp = num_tp / sd;
    g.dr_gtp = (-2.0 * a * sd - num_tp * dsd_dr) / sd2;
    g.dth_gtp = (-num_tp * dsd_dth) / sd2;

    float num_pp = del - aa * s2;
    float den_pp = sd * s2;
    float den_pp2 = den_pp * den_pp;
    float dnum_pp_dth = -aa * (2.0 * sn * cs);
    float dden_pp_dr = dsd_dr * s2;
    float dden_pp_dth = dsd_dth * s2 + sd * (2.0 * sn * cs);
    g.gpp = num_pp / den_pp;
    g.dr_gpp = (ddel_dr * den_pp - num_pp * dden_pp_dr) / den_pp2;
    g.dth_gpp = (dnum_pp_dth * den_pp - num_pp * dden_pp_dth) / den_pp2;

    float sig2 = sig * sig;
    g.grr = del / sig;
    g.dr_grr = (ddel_dr * sig - del * dsig_dr) / sig2;
    g.dth_grr = (-del * dsig_dth) / sig2;

    g.gthth = 1.0 / sig;
    g.dr_gthth = -dsig_dr / sig2;
    g.dth_gthth = -dsig_dth / sig2;
    return g;
}

// State as two float4s: y0 = (t, r, theta, phi), y1 = (p_t, p_r, p_theta, p_phi).
struct GState { float4 x; float4 p; };

static GState kerrDeriv(GState y, float a)
{
    KerrInv g = kerrInverse(y.x.y, y.x.z, a);
    float pt = y.p.x, pr = y.p.y, pth = y.p.z, pp = y.p.w;

    GState d;
    d.x = float4(g.gtt * pt + g.gtp * pp,     // dt
                 g.grr * pr,                   // dr
                 g.gthth * pth,                // dtheta
                 g.gtp * pt + g.gpp * pp);     // dphi

    float dpr = -0.5 * (g.dr_gtt * pt * pt + 2.0 * g.dr_gtp * pt * pp
                        + g.dr_gpp * pp * pp + g.dr_grr * pr * pr
                        + g.dr_gthth * pth * pth);
    float dpth = -0.5 * (g.dth_gtt * pt * pt + 2.0 * g.dth_gtp * pt * pp
                         + g.dth_gpp * pp * pp + g.dth_grr * pr * pr
                         + g.dth_gthth * pth * pth);
    // dp_t and dp_phi are identically zero: the stationary and axisymmetric Killing vectors.
    d.p = float4(0.0, dpr, dpth, 0.0);
    return d;
}

static GState gadd(GState y, GState d, float h)
{
    GState o; o.x = y.x + d.x * h; o.p = y.p + d.p * h; return o;
}

static GState kerrStep(GState y, float a, float h)
{
    GState k1 = kerrDeriv(y, a);
    GState k2 = kerrDeriv(gadd(y, k1, 0.5 * h), a);
    GState k3 = kerrDeriv(gadd(y, k2, 0.5 * h), a);
    GState k4 = kerrDeriv(gadd(y, k3, h), a);
    GState o;
    o.x = y.x + (h / 6.0) * (k1.x + 2.0 * k2.x + 2.0 * k3.x + k4.x);
    o.p = y.p + (h / 6.0) * (k1.p + 2.0 * k2.p + 2.0 * k3.p + k4.p);
    return o;
}

fragment float4 geodesic_fragment(FSOut in [[stage_in]],
                                  constant Relativity &rel [[buffer(0)]],
                                  constant float4 *palette [[buffer(1)]])
{
    float2 p = in.ndc;
    p.x *= rel.aspect;

    float3 camPos = rel.camEye;
    float3 dir = normalize(rel.camRight * (p.x * rel.tanHalfFov)
                           + rel.camUp * (in.ndc.y * rel.tanHalfFov)
                           + rel.camForward);

    float a = clamp(rel.spin, -0.999, 0.999);

    // Cartesian camera -> Boyer-Lindquist. For a != 0 these are oblate spheroidal, but at the radii
    // the camera occupies (r >> a) the spherical form is accurate to O(a^2/r^2); the INTEGRATION is
    // exact Kerr regardless, which is what matters.
    float r0 = max(length(camPos), rel.outerHorizon * 1.05);
    float th0 = acos(clamp(camPos.y / r0, -1.0, 1.0));
    float ph0 = atan2(camPos.z, camPos.x);

    // ── The camera's frame: a ZAMO orthonormal tetrad ────────────────────────────────────────
    //
    // The first version used flat-space spherical unit vectors (sin/cos of the angles) as if they
    // were a basis. They are not a tetrad: a tetrad is an ORTHONORMAL set of four 4-vectors built
    // FROM THE METRIC, satisfying g(e_mu, e_nu) = eta_mu_nu. Trigonometry alone only reproduces one
    // as r -> infinity, which is exactly why the exterior looked plausible and everything close in
    // degraded smoothly into nonsense.
    //
    // The frame used here is the ZAMO — Zero Angular Momentum Observer, a.k.a. the locally
    // non-rotating frame (Bardeen, Press & Teukolsky 1972). It is the right choice because it
    // exists everywhere OUTSIDE r+, including inside the ergosphere where a static observer does
    // not. Frame dragging is carried by the frame itself: the ZAMO co-rotates at
    //
    //     omega = -g_tphi / g_phiphi = 2 M a r / A
    //
    // which is the same quantity Regions.framePickupRate computes and the Kit already tests.
    //
    // Covariant metric components, from the same Sigma/Delta/A this file already builds.
    float sinT = max(sin(th0), 1e-5);
    float sin2 = sinT * sinT;
    float cosT = cos(th0);
    float sigC = r0 * r0 + a * a * cosT * cosT;
    float delC = r0 * r0 - 2.0 * r0 + a * a;
    float bigAC = (r0 * r0 + a * a) * (r0 * r0 + a * a) - a * a * delC * sin2;

    float g_tt   = -(1.0 - 2.0 * r0 / sigC);
    float g_tph  = -2.0 * a * r0 * sin2 / sigC;
    float g_phph = (bigAC / sigC) * sin2;
    float g_rr   = sigC / delC;          // NEGATIVE between the horizons: r is timelike there
    float g_thth = sigC;

    float omega = -g_tph / max(abs(g_phph), 1e-9);          // frame-dragging angular velocity
    // Lapse: alpha^2 = Sigma Delta / A. Real outside r+, and it is the factor that goes to zero
    // ON the horizon — which is the statement that the ZAMO family ends there.
    float alpha2 = sigC * delC / max(bigAC, 1e-9);
    float alpha = sqrt(max(alpha2, 1e-9));

    // The four tetrad legs, each normalised by the metric rather than assumed unit.
    //   e_0 : the ZAMO's own 4-velocity   (timelike)
    //   e_r, e_th, e_ph : its spatial triad
    // Written as components on (dt, dr, dtheta, dphi).
    float4 e0  = float4(1.0 / alpha, 0.0, 0.0, omega / alpha);
    float4 eR  = float4(0.0, 1.0 / sqrt(max(abs(g_rr), 1e-9)), 0.0, 0.0);
    float4 eTh = float4(0.0, 0.0, 1.0 / sqrt(max(g_thth, 1e-9)), 0.0);
    float4 ePh = float4(0.0, 0.0, 0.0, 1.0 / sqrt(max(abs(g_phph), 1e-9)));

    // The pixel direction, as a unit 3-vector in the camera's LOCAL SKY. This is the DNGR
    // construction: pick the direction on the local sky, build the photon's 4-momentum from the
    // tetrad, and only then integrate. Direction components are read against the same spherical
    // orientation the world uses, so the camera's yaw/pitch still mean what the UI says.
    float3 erHat  = float3(sinT * cos(ph0), cosT, sinT * sin(ph0));
    float3 ethHat = float3(cosT * cos(ph0), -sinT, cosT * sin(ph0));
    float3 ephHat = float3(-sin(ph0), 0.0, cos(ph0));
    float nR  = dot(dir, erHat);
    float nTh = dot(dir, ethHat);
    float nPh = dot(dir, ephHat);

    // Photon 4-momentum, CONTRAVARIANT: p = E_loc (e_0 + n^i e_i). Null by construction, because
    // the tetrad is orthonormal and n is a unit 3-vector — no quadratic solve, no sign ambiguity,
    // and nothing that breaks when a metric component changes sign.
    float4 pUp = e0 + nR * eR + nTh * eTh + nPh * ePh;

    // Lower with the covariant metric to get p_mu, which is what the Hamiltonian integrator wants.
    float pt  = g_tt * pUp.x + g_tph * pUp.w;
    float pr  = g_rr * pUp.y;
    float pth = g_thth * pUp.z;
    float pph = g_tph * pUp.x + g_phph * pUp.w;

    GState y;
    y.x = float4(0.0, r0, th0, ph0);
    y.p = float4(pt, pr, pth, pph);

    int STEPS = int(clamp(rel.integrationSteps, 16.0, 256.0));
    float rHor = rel.outerHorizon;
    // Inner (Cauchy) horizon: r- = M - sqrt(M^2 - a^2). Past it the ring singularity is TIMELIKE
    // and therefore avoidable, and the maximal analytic extension opens onto another
    // asymptotically flat region. That is where the cat's world is.
    float rInner = 1.0 - sqrt(max(1.0 - a * a, 0.0));
    bool cameraInside = (r0 < rHor);

    bool hitRing = false;
    bool crossedInner = false;
    float minR = r0;

    // DO NOT UNROLL.
    //
    // The body is kerrStep -> 4x kerrDeriv -> kerrInverse: roughly 100 lines of algebra with 15
    // divisions and a sin/cos pair. Unrolled even partially it becomes an enormous function, and
    // the compiler pegs the GPU optimising it — which is why `xcodebuild` itself started showing
    // 100% GPU once the real Kerr Hamiltonian replaced the scalar form.
    //
    // It costs twice, because the same unrolling blows up register pressure at runtime and register
    // pressure is what caps occupancy. Keeping the loop rolled trades a few branch instructions for
    // far more threads in flight, which is the right trade for a long arithmetic body.
    #pragma clang loop unroll(disable)
    for (int i = 0; i < STEPS; ++i) {
        // Step size from distance to the NEAREST horizon, since inside there are two of them and
        // the chart stiffens at both. A pure function of state, so the schedule is reproducible.
        float gap = min(abs(y.x.y - rHor), abs(y.x.y - rInner));
        float h = clamp(0.55 * max(gap, 0.02) / (1.0 + gap), 0.002, 0.65);
        y = kerrStep(y, a, h);
        minR = min(minR, y.x.y);

        if (y.x.y < rInner) crossedInner = true;
        // The ring singularity sits at r = 0, theta = pi/2. Everything else is passable.
        if (y.x.y < 0.06 && abs(cos(y.x.z)) < 0.12) { hitRing = true; break; }
        if (y.x.y < 0.0) { hitRing = true; break; }
        if (y.x.y > 400.0) break;
        if (!isfinite(y.x.y)) { hitRing = true; break; }

        // Seen from OUTSIDE, anything that falls through r+ is gone: it can no longer reach the
        // camera, which is exactly what makes a shadow. Seen from INSIDE, r+ is just a surface the
        // ray passes, so no early-out.
        if (!cameraInside && y.x.y <= rHor * 1.001) {
            return float4(palette[2].rgb, 1.0);
        }
    }

    if (hitRing) {
        // The ring itself. Bright rather than black: it is a naked timelike singularity from here,
        // not a horizon, and drawing it as a hole would be the wrong statement.
        return float4(mix(palette[2].rgb, palette[4].rgb, 0.65), 1.0);
    }

    if (crossedInner) {
        // Past the Cauchy horizon — the adjacent region.
        //
        // The first version tinted this with sin(phi * 3), which was an invented pattern dressed as
        // physics. It is now driven by the KRETSCHMANN SCALAR, a genuine curvature invariant:
        //
        //     K = 48 M^2 (r^2 - a^2cos^2 th)((r^2 + a^2cos^2 th)^2 - 16 r^2 a^2 cos^2 th) / Sigma^6
        //
        // Coordinate-independent, so it says the same thing in any chart. It DIVERGES at the ring
        // and is FINITE at both horizons — which is the visual demonstration that the horizons are
        // coordinate artefacts and the ring is not. Nothing else on screen makes that argument.
        float rr = y.x.y, ct = cos(y.x.z);
        float aa = a * a, a2c2 = aa * ct * ct;
        float sig = rr * rr + a2c2;
        float sig3 = sig * sig * sig;
        float K = 48.0 * (rr * rr - a2c2)
                       * ((rr * rr + a2c2) * (rr * rr + a2c2) - 16.0 * rr * rr * a2c2)
                       / max(sig3 * sig3, 1e-12);
        // log-compressed: K spans many orders of magnitude between r- and the ring.
        float curv = saturate(log2(1.0 + abs(K)) / 26.0);
        // Ramp across the REDSHIFT palette, not between palette[3] and palette[4].
        //
        // Those two are both teal, so the first version mixed teal into teal and the curvature
        // signal — which is real and correct — was invisible. A physically-driven value rendered
        // onto an indistinguishable colour pair is indistinguishable from having no signal at all,
        // which is a good reminder that "the maths is right" and "you can see it" are separate
        // claims. The warm ramp spans amber to near-black, so K now reads across its whole range.
        float ct2 = clamp(curv * 4.0, 0.0, 3.99);
        int ci = int(ct2);
        float3 other = mix(palette[5 + ci].rgb, palette[6 + ci].rgb, ct2 - float(ci));
        other += starField3(normalize(float3(sin(y.x.z) * cos(y.x.w), cos(y.x.z),
                                             sin(y.x.z) * sin(y.x.w)))) * (1.0 - curv) * 0.6;
        return float4(other, 1.0);
    }

    // Escaped: read the sky in the direction the ray ended up travelling.
    float3 outDir = normalize(float3(sin(y.x.z) * cos(y.x.w),
                                     cos(y.x.z),
                                     sin(y.x.z) * sin(y.x.w)));
    float3 sky = mix(palette[1].rgb, palette[0].rgb, saturate(0.5 + 0.5 * outDir.y));
    sky += starField3(outDir) * float3(1.0, 0.97, 0.92);

    // Redshift keyed to the ray's actual periapsis, which the integration now knows exactly.
    float depth = saturate(rHor / max(minR, rHor));
    float t = clamp(depth * 4.0, 0.0, 3.99);
    int idx = int(t);
    sky = mix(sky, mix(palette[5 + idx].rgb, palette[6 + idx].rgb, t - float(idx)), depth * 0.8);

    return float4(sky * rel.observerRedshift, 1.0);
}

// ── Instanced primitives ─────────────────────────────────────────────────────────────────────
//
// The cosmonaut, the cat, the machinery and the portal frames are all ONE unit cube, instanced.
// Primitives plus flat materials in the measured palette is the register froggo and city pigeon
// already established, it costs no asset pipeline, and against a background of real gravitational
// lensing a stylised figure reads as more deliberate than an attempt at realism would.

// Unit cube, 24 vertices — four per face, so every face carries its own normal.
//
// **The order within a face is triangle-STRIP order, not loop order**, and the difference is not
// cosmetic. A strip over A,B,C,D draws ABC and BCD; for corners listed as a loop those two share
// edge BC rather than a diagonal, so together they cover the quad minus a triangular hole. City
// Pigeon's first build rendered a city of translucent wedges because of exactly this.
constant float3 kCubeCorner[24] = {
    float3( 1,-1, 1), float3( 1,-1,-1), float3( 1, 1, 1), float3( 1, 1,-1),   // +x
    float3(-1,-1,-1), float3(-1,-1, 1), float3(-1, 1,-1), float3(-1, 1, 1),   // -x
    float3(-1, 1, 1), float3( 1, 1, 1), float3(-1, 1,-1), float3( 1, 1,-1),   // +y
    float3(-1,-1,-1), float3( 1,-1,-1), float3(-1,-1, 1), float3( 1,-1, 1),   // -y
    float3(-1,-1, 1), float3( 1,-1, 1), float3(-1, 1, 1), float3( 1, 1, 1),   // +z
    float3( 1,-1,-1), float3(-1,-1,-1), float3( 1, 1,-1), float3(-1, 1,-1),   // -z
};

constant float3 kCubeNormal[6] = {
    float3( 1, 0, 0), float3(-1, 0, 0), float3( 0, 1, 0),
    float3( 0,-1, 0), float3( 0, 0, 1), float3( 0, 0,-1),
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float shade;
    float emissive;
};

vertex VertexOut cube_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             const device Instance *instances [[buffer(0)]],
                             constant Uniforms &u [[buffer(1)]])
{
    Instance inst = instances[iid];
    uint face = vid / 4;

    float3 world = inst.center + kCubeCorner[vid] * inst.halfExtent;

    VertexOut out;
    out.position = u.viewProjection * float4(world, 1.0);
    out.color = inst.color;

    // Flat directional shading from the cube's own face normals. Cheap, and it is what stops a
    // figure built from boxes reading as a flat silhouette.
    float lambert = max(0.0, dot(kCubeNormal[face], normalize(u.lightDirection)));
    out.shade = u.ambient + (1.0 - u.ambient) * lambert;
    out.emissive = inst.flags.x;
    return out;
}

fragment float4 cube_fragment(VertexOut in [[stage_in]])
{
    float3 lit = in.color.rgb * in.shade + in.color.rgb * in.emissive;
    return float4(lit, in.color.a);
}

// ── Portals ──────────────────────────────────────────────────────────────────────────────────
//
// Portal's technique, in the form that suits a scene whose background is a full-screen geodesic
// pass rather than a mesh: the view through a portal is rendered from the VIRTUAL camera
// (T · realCamera) into an offscreen target, and the portal quad then samples that target using
// its own screen position. That is equivalent to the stencil-and-oblique-clip formulation for a
// single level of recursion, and it composes with the raymarched sky for free, which the stencil
// version does not.
//
// The transform T = P_dst · flip · P_src⁻¹ is computed in PortalKit, where `round-trip = I` is a
// unit test rather than something checked by walking through one and seeing if you feel taller.
//
// #14 differs from #12 in exactly one respect: T comes from the Kerr metric instead of from where
// a designer put the mouths. Same renderer, and the only portal in a game with a citation.

struct PortalOut {
    float4 position [[position]];
    float2 screenUV;
    float3 edge;        // xy = position within the quad in [-1,1], z = unused
    float4 tint;
};

vertex PortalOut portal_vertex(uint vid [[vertex_id]],
                               uint iid [[instance_id]],
                               const device Instance *portals [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]])
{
    // A quad as a triangle strip: (-1,-1), (1,-1), (-1,1), (1,1). Strip order, not loop order —
    // the same trap the cube corners carry a comment about.
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);

    Instance inst = portals[iid];
    // halfExtent.x/y span the mouth; the frame's orientation is baked into center + halfExtent by
    // the CPU side, which already has the PortalKit basis.
    float3 world = inst.center + float3(corner.x * inst.halfExtent.x,
                                        corner.y * inst.halfExtent.y,
                                        0.0);

    PortalOut out;
    out.position = u.viewProjection * float4(world, 1.0);
    // Sample the virtual-camera target at THIS fragment's screen position: the through-view is
    // already rendered from the right place, so the portal is a window onto it rather than a
    // texture pasted on a wall.
    out.screenUV = out.position.xy / max(out.position.w, 1e-4) * 0.5 + 0.5;
    out.screenUV.y = 1.0 - out.screenUV.y;
    out.edge = float3(corner, 0.0);
    out.tint = inst.color;
    return out;
}

fragment float4 portal_fragment(PortalOut in [[stage_in]],
                                texture2d<float> through [[texture(0)]],
                                sampler s [[sampler(0)]])
{
    // Elliptical mouth. A rectangular portal reads as a screen; an ellipse reads as an opening.
    float r = length(in.edge.xy);
    if (r > 1.0) discard_fragment();

    float3 view = through.sample(s, in.screenUV).rgb;
    // Rim: the throat glows where the geometry is doing the most work. For #14 this is literally
    // where the Einstein-Rosen throat pinches.
    float rim = smoothstep(0.78, 1.0, r);
    return float4(mix(view, in.tint.rgb, rim * 0.85), 1.0);
}

// Upscale the reduced-resolution geodesic pass to the drawable.
//
// Linear filtering is enough: the geodesic background is smooth by construction — a shadow edge and
// a redshift ramp — so there is no high-frequency detail for a fancier filter to recover. The one
// place it would show is the photon ring, which is why the scale is a control rather than a
// constant: turn it to 1.0 when you want to inspect the ring, leave it at 0.5 to play.
fragment float4 blit_fragment(FSOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]],
                              sampler s [[sampler(0)]])
{
    float2 uv = in.ndc * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    return float4(src.sample(s, uv).rgb, 1.0);
}
