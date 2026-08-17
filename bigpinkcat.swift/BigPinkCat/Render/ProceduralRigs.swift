import Foundation
import simd

/// The cosmonaut and the cat, assembled from primitives.
///
/// This follows `froggo2/Froggo2/Render/ProceduralFrogRig.swift`, and its reasoning carries over
/// unchanged: everything animates **by transform**, so an authored model can slot in later without
/// touching a line of animation code. It costs no art budget, no USDZ pipeline and no rig.
///
/// Against a background of real gravitational lensing, a stylised figure of boxes reads as more
/// deliberate than an attempt at realism would — the spacetime is the thing being rendered
/// seriously, and the figures are legible silhouettes inside it.
///
/// Every colour comes from `Palette`, which is measured from the game's own art. Nothing here
/// invents one.
enum ProceduralCosmonautRig {

    /// Half a metre across at scale 1, and everything else derives from that — the same convention
    /// froggo uses, so the two projects' scales stay comparable.
    static func emit(into out: inout [Renderer.Instance],
                     at origin: SIMD3<Float>, scale s: Float, yaw: Float) {
        func add(_ offset: SIMD3<Float>, _ half: SIMD3<Float>,
                 _ color: SIMD3<Float>, emissive: Float = 0) {
            // Yaw by transform: the rig itself never rebuilds, it only rotates.
            let c = cos(yaw), sn = sin(yaw)
            let rotated = SIMD3(offset.x * c + offset.z * sn, offset.y,
                                -offset.x * sn + offset.z * c)
            out.append(Renderer.Instance(center: origin + rotated * s,
                                         halfExtent: half * s,
                                         color: SIMD4(color, 1),
                                         flags: SIMD4(emissive, 0, 0, 0)))
        }

        // Torso — the suit's midtone, the largest single mass so it sets the silhouette.
        add(SIMD3(0, 0, 0), SIMD3(0.20, 0.26, 0.14), Palette.suitMid)
        // Helmet. A sphere would be truer but a slightly flattened box holds a specular edge at
        // this camera distance and reads more clearly against a lensed background.
        add(SIMD3(0, 0.40, 0), SIMD3(0.15, 0.14, 0.15), Palette.suitLight)
        // Visor — amber, because amber is this game's instrumentation colour and the visor is the
        // one place the engineer's own readouts are visible from outside.
        add(SIMD3(0, 0.40, -0.13), SIMD3(0.11, 0.07, 0.04), Palette.amberBright, emissive: 0.55)
        // Backpack: the extraction rig. This is his job, so it is deliberately bulky.
        add(SIMD3(0, 0.05, 0.20), SIMD3(0.15, 0.20, 0.09), Palette.suitDark)
        // Two exotic-matter cells on the pack — the negative-energy shell he maintains.
        add(SIMD3(-0.09, 0.14, 0.28), SIMD3(0.04, 0.07, 0.03), Palette.voidTealBright, emissive: 0.8)
        add(SIMD3(0.09, 0.14, 0.28), SIMD3(0.04, 0.07, 0.03), Palette.voidTealBright, emissive: 0.8)
        // Arms.
        add(SIMD3(-0.26, 0.02, 0), SIMD3(0.06, 0.19, 0.06), Palette.suitMid)
        add(SIMD3(0.26, 0.02, 0), SIMD3(0.06, 0.19, 0.06), Palette.suitMid)
        // Legs.
        add(SIMD3(-0.10, -0.42, 0), SIMD3(0.07, 0.19, 0.07), Palette.suitDark)
        add(SIMD3(0.10, -0.42, 0), SIMD3(0.07, 0.19, 0.07), Palette.suitDark)
        // Suit trim, the one warm line that keeps the figure from reading as a grey blob.
        add(SIMD3(0, 0.16, -0.145), SIMD3(0.13, 0.02, 0.01), Palette.amber, emissive: 0.35)
    }
}

/// The Big Pink Cat.
///
/// Colossal by construction: its scale is set relative to the outer horizon, not to the cosmonaut,
/// because it is the consciousness of a neighbouring galaxy and the size relationship is the point.
/// The caller passes that scale in; the rig only knows proportions.
enum ProceduralCatRig {

    static func emit(into out: inout [Renderer.Instance],
                     at origin: SIMD3<Float>, scale s: Float, yaw: Float) {
        func add(_ offset: SIMD3<Float>, _ half: SIMD3<Float>,
                 _ color: SIMD3<Float>, emissive: Float = 0) {
            let c = cos(yaw), sn = sin(yaw)
            let rotated = SIMD3(offset.x * c + offset.z * sn, offset.y,
                                -offset.x * sn + offset.z * c)
            out.append(Renderer.Instance(center: origin + rotated * s,
                                         halfExtent: half * s,
                                         color: SIMD4(color, 1),
                                         flags: SIMD4(emissive, 0, 0, 0)))
        }

        // Body — one large mass in the measured mid pink.
        add(SIMD3(0, 0, 0), SIMD3(0.62, 0.40, 0.90), Palette.catMid)
        // Shadow underside, so the volume reads without needing a second light.
        add(SIMD3(0, -0.30, 0), SIMD3(0.56, 0.14, 0.84), Palette.catShadow)
        // Head.
        add(SIMD3(0, 0.42, -0.86), SIMD3(0.42, 0.36, 0.38), Palette.catPink)
        // Ears. froggo's note that the eyes "sit high and proud" is the species cue for a frog;
        // for a cat it is the ears, so they are deliberately oversized.
        add(SIMD3(-0.28, 0.80, -0.86), SIMD3(0.12, 0.22, 0.06), Palette.catMid)
        add(SIMD3(0.28, 0.80, -0.86), SIMD3(0.12, 0.22, 0.06), Palette.catMid)
        // Eyes — the constellation pattern. Emissive, because this is a galaxy wearing a cat.
        add(SIMD3(-0.18, 0.50, -1.20), SIMD3(0.10, 0.10, 0.04), Palette.catHighlight, emissive: 0.9)
        add(SIMD3(0.18, 0.50, -1.20), SIMD3(0.10, 0.10, 0.04), Palette.catHighlight, emissive: 0.9)
        add(SIMD3(-0.18, 0.50, -1.24), SIMD3(0.035, 0.075, 0.03), Palette.voidPurple)
        add(SIMD3(0.18, 0.50, -1.24), SIMD3(0.035, 0.075, 0.03), Palette.voidPurple)
        // Legs, folded — the cat is never standing, it is regarding you.
        add(SIMD3(-0.46, -0.44, -0.52), SIMD3(0.13, 0.16, 0.13), Palette.catShadow)
        add(SIMD3(0.46, -0.44, -0.52), SIMD3(0.13, 0.16, 0.13), Palette.catShadow)
        add(SIMD3(-0.46, -0.44, 0.56), SIMD3(0.13, 0.16, 0.13), Palette.catShadow)
        add(SIMD3(0.46, -0.44, 0.56), SIMD3(0.13, 0.16, 0.13), Palette.catShadow)

        // Tail: a chain of shrinking boxes, so it curls purely by transform — no skinning, no rig.
        let segments = 7
        for i in 0..<segments {
            let f = Float(i) / Float(segments - 1)
            let curl = f * 1.5
            add(SIMD3(sin(curl) * 0.55, 0.20 + f * 0.75, 0.95 + cos(curl) * 0.35),
                SIMD3(repeating: 0.13 - f * 0.07),
                Palette.mix(Palette.catMid, Palette.catSignal, f))
        }
    }
}
