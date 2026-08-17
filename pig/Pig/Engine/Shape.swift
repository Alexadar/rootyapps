import Foundation

/// The pig's body, as a function of one number.
///
/// **This is the game.** `fat ∈ [0, 1]` is simulation state; every dimension of the animal is derived
/// from it here, batch-first, and nothing else in the program is allowed to invent a body dimension.
/// The renderer receives these values as shader uniforms and evaluates the surface from them — it
/// does not author geometry, and there is no rest-pose mesh anywhere to drift out of sync.
///
/// Two consequences worth stating, because they are why the shape lives in `Engine/` and not in
/// `Render/`:
///
///  * **It is testable.** "Eating always makes the pig bigger", "the belly never sinks through the
///    ground", "the legs can always reach the ground" are properties of *this file*, provable across
///    the whole `fat` range by sweeping a batch. None of them is checkable in a vertex shader.
///  * **It is batched.** `derive` takes `[N]` and returns `[N]`s. One pig and ten thousand pigs are
///    the same call.
///
/// The surface itself — how these radii become vertices — is `Render/Shaders.metal`'s `pigPoint`,
/// which is the single authority for that and is used by the body mesh AND by every attachment
/// (legs, ears, eyes, snout, tail) so nothing can come unwelded from a belly that just swelled.
struct BodyShape: Sendable {

    // MARK: - The radius profile, snout → tail (metres)
    //
    // Six control radii along the spine. The shader interpolates them with a monotone (smoothstep)
    // blend rather than a Catmull-Rom, deliberately: a spline through these overshoots between
    // chest and belly at high fat, and an overshooting radius is a bulge the shape maths does not
    // know about — which is how a surface self-intersects.

    var snout: Double
    var head: Double
    var chest: Double
    var belly: Double
    var rump: Double
    var tailBase: Double

    /// Snout tip to rump, metres.
    var length: Double
    /// Spine height above the ground, metres. **Derived, never authored** — see `derive`.
    var stand: Double

    // MARK: - Cross-section

    /// How far the belly's centre line drops below the spine, metres.
    var sag: Double
    /// Horizontal radius ÷ vertical radius. A fat pig is wider than it is tall.
    var squash: Double
    /// Superellipse exponent. 2 is a circle; higher is a loaf.
    var superE: Double
    /// Extra radius under the jaw. The double chin.
    var jowl: Double

    // MARK: - Attachments

    var legLength: Double
    var legRadius: Double
    /// How far the legs splay outward, radians. A wide body pushes them out.
    var legSplay: Double
    var earScale: Double
    /// How much the head lifts clear of the swelling shoulders, metres.
    var headLift: Double

    // MARK: - Feel

    /// Amplitude of the belly wobble per unit of spring displacement. Scales hard with fat: a lean
    /// pig is rigid, a fat one is a water balloon.
    var wobbleGain: Double

    /// How far the cross-section's lower half extends, relative to its radius. Above 1 the belly
    /// hangs below the spine's circle; below 1 it flattens where it meets the field. The shader reads
    /// this rather than holding its own copy, because the clearance proof below is stated over it.
    var underside: Double

    /// Belly clearance above the ground, metres. Negative means the pig is sunk into the field, which
    /// `ShapeOracleTests` proves cannot happen at any `fat`.
    var bellyClearance: Double { stand - sag - belly * underside }

    /// A proxy for the animal's volume: the tube's radii squared, summed along the spine, times its
    /// length. Not a real integral — it is a monotonicity witness, and that is all it is used for.
    var bulk: Double {
        let r = [snout, head, chest, belly, rump, tailBase]
        return r.reduce(0) { $0 + $1 * $1 } * length * squash
    }
}

/// Batch-first derivation of the body from `fat`. One implementation, used at `N = 1` by the game and
/// at `N = 512` by the oracle sweep.
enum PigShape {

    /// Every dimension, as `[N]` tensors, from a `[N]` fat.
    struct Batch {
        var snout, head, chest, belly, rump, tailBase: Tensor
        var length, stand, sag, squash, superE, jowl: Tensor
        var legLength, legRadius, legSplay, earScale, headLift, wobbleGain, underside: Tensor
    }

    /// Linear blend, elementwise. The only interpolation in this file, so the tuning table below
    /// reads as "lean → round" and nothing else.
    @inline(__always)
    private static func lerp(_ a: Double, _ b: Double, _ t: Tensor) -> Tensor {
        t * (b - a) + a
    }

    static func derive(fat: Tensor) -> Batch {
        let f = fat.clamped(min: 0, max: 1)
        // The belly leads the other radii: it grows superlinearly so the first mouthful is barely
        // visible and the last one is absurd. That curve is the comedy, and it is one line.
        let fb = f * f * 0.55 + f * 0.45
        // Everything that shrinks with fat uses the plain ramp, so nothing shrinks faster than the
        // belly grows — the ground-clearance proof depends on that ordering.
        let snout = lerp(0.085, 0.120, f)
        let head = lerp(0.155, 0.230, f)
        let chest = lerp(0.195, 0.360, fb)
        let belly = lerp(0.210, 0.500, fb)
        let rump = lerp(0.200, 0.425, fb)
        let tailBase = lerp(0.070, 0.108, f)

        let legLength = lerp(0.320, 0.150, f)
        let sag = lerp(0.0, 0.085, fb)
        let underside = lerp(1.06, 0.88, fb)

        // **Derived, not authored.** The spine sits high enough that the belly always clears the
        // field: the leg carries it, plus most of the belly's actual underside, plus the whole sag.
        // Authoring `stand` as its own tuning number is how a fat pig ends up wading through the
        // ground — there would be nothing tying the two numbers together, and only the eye would
        // catch it.
        let stand = legLength + belly * underside * 0.94 + sag

        return Batch(
            snout: snout, head: head, chest: chest, belly: belly, rump: rump, tailBase: tailBase,
            length: lerp(1.10, 1.34, fb),
            stand: stand,
            sag: sag,
            squash: lerp(1.00, 1.17, fb),
            superE: lerp(2.00, 2.30, f),
            jowl: lerp(0.0, 0.058, fb),
            legLength: legLength,
            legRadius: lerp(0.058, 0.090, f),
            legSplay: lerp(0.04, 0.34, fb),
            earScale: lerp(0.135, 0.172, f),
            headLift: lerp(0.045, 0.090, fb),
            wobbleGain: lerp(0.010, 0.080, fb),
            underside: underside
        )
    }

    /// One world's body, as host scalars for the shader uniform.
    static func scalar(fat: Double) -> BodyShape {
        let b = derive(fat: Tensor(shape: [1], data: [fat]))
        return BodyShape(
            snout: b.snout[0], head: b.head[0], chest: b.chest[0], belly: b.belly[0],
            rump: b.rump[0], tailBase: b.tailBase[0],
            length: b.length[0], stand: b.stand[0], sag: b.sag[0], squash: b.squash[0],
            superE: b.superE[0], jowl: b.jowl[0],
            legLength: b.legLength[0], legRadius: b.legRadius[0], legSplay: b.legSplay[0],
            earScale: b.earScale[0], headLift: b.headLift[0], wobbleGain: b.wobbleGain[0],
            underside: b.underside[0])
    }

    /// The widest half-width of the animal at a given fat — what the eating reach and any future
    /// collision radius must both be measured against, so they cannot disagree.
    static func girth(_ s: BodyShape) -> Double { s.belly * s.squash }
}
