import Foundation

/// An aspect between a body in one position set and a body in *another* set —
/// transits to natal, synastry chart A to chart B, progressions to radix.
///
/// This is deliberately a separate type from `DetectedAspect`, which describes a pair
/// inside one chart and therefore treats its two bodies as interchangeable. Here the
/// sides are NOT interchangeable: transiting Sun square natal Moon and transiting Moon
/// square natal Sun are different statements about different charts, and a type that
/// forgets which side a body came from cannot tell them apart.
public struct CrossAspect: Identifiable, Hashable {
    public let type: AspectType
    /// Body taken from the FIRST set (`between:`) — conventionally the transiting/moving chart.
    public let moving: CelestialBody
    /// Body taken from the SECOND set (`and:`) — conventionally the natal/reference chart.
    public let reference: CelestialBody
    /// Unsigned separation of the two longitudes, in [0, 180]. Kept so callers never
    /// re-derive it with a naive subtraction and lose the 0/360 wrap.
    public let separation: Double
    /// Distance from exactness: |separation − type.angle|, in degrees.
    public let orb: Double

    public init(type: AspectType, moving: CelestialBody, reference: CelestialBody,
                separation: Double, orb: Double) {
        self.type = type; self.moving = moving; self.reference = reference
        self.separation = separation; self.orb = orb
    }

    /// The same body on both sides. Legal here and meaningless within one chart —
    /// a body is always 0° from itself in its own chart, but 0° from its *natal*
    /// position only once per orbit.
    public var isSelfPair: Bool { moving == reference }

    /// A body back on its own natal degree: the Saturn return, the solar return,
    /// the lunar return. The single most-asked-for result of cross-set detection.
    public var isReturn: Bool { isSelfPair && type.angle == 0 }

    /// Side-tagged, so the two orderings of a body pair are distinct identities in a list.
    public var id: String { "t:\(moving.rawValue)-\(type.name)-n:\(reference.rawValue)" }

    /// The same geometry read from the other chart's point of view. Separation and orb are
    /// symmetric, so only the side labels move.
    public var mirrored: CrossAspect {
        CrossAspect(type: type, moving: reference, reference: moving,
                    separation: separation, orb: orb)
    }
}

extension Aspects {
    /// Every aspect between the two sets: the full |A|×|B| cross product, self-pairs included.
    ///
    /// Three things differ from `detect(in:)` and each is load-bearing:
    ///
    /// 1. No `i < j` guard. That guard exists within one chart to avoid reporting a pair twice;
    ///    across two charts the pairs are distinct, so 10 bodies against 10 is 100 comparisons,
    ///    not 45.
    /// 2. Self-pairs are kept. `moving[i]` and `reference[i]` are the same body at two different
    ///    moments; suppressing them would delete the returns, which is most of the point.
    /// 3. When the orb factor is wide enough for two aspect types to admit the same separation
    ///    (they start overlapping around factor 5 — square's ±30 reaches into sextile's ±20),
    ///    the TIGHTEST match wins rather than whichever type happens to be listed first in
    ///    `AspectType.all`. Order of a static array must not decide an astronomical answer.
    ///
    /// Sorted tightest-first, with a total tie-break on body order and aspect angle so the
    /// output is stable across runs and platforms (SwiftUI lists diff badly otherwise).
    public static func detect(between moving: [BodyPosition],
                              and reference: [BodyPosition],
                              orbFactor: Double) -> [CrossAspect] {
        var found: [CrossAspect] = []
        found.reserveCapacity(moving.count * reference.count)

        for m in moving {
            for r in reference {
                let sep = symmetricSeparation(m.longitude, r.longitude)
                var best: (type: AspectType, orb: Double)?
                for type in AspectType.all {
                    let orb = abs(sep - type.angle)
                    guard orb <= type.baseOrb * orbFactor else { continue }
                    if best == nil || orb < best!.orb { best = (type, orb) }
                }
                if let best {
                    found.append(CrossAspect(type: best.type, moving: m.body, reference: r.body,
                                             separation: sep, orb: best.orb))
                }
            }
        }
        return found.sorted(by: tighterFirst)
    }

    /// `AstroMath.separation` handles the 0/360 wrap (359° vs 1° is 2°, not 358°) but is only
    /// symmetric to within a rounding step: it normalizes `a − b`, and for the reversed pair
    /// the `m + 360` correction inside `norm360` lands on a different last bit. Across two
    /// charts that matters — swapping the arguments must return the *same* numbers, not
    /// numbers 1e-13 apart, or a pair sitting exactly on its orb limit could be reported in
    /// one direction and dropped in the other. Feeding the helper a canonically ordered pair
    /// makes the call bit-identical both ways without a second copy of the wrap logic.
    private static func symmetricSeparation(_ a: Double, _ b: Double) -> Double {
        let (x, y) = (AstroMath.norm360(a), AstroMath.norm360(b))
        return x <= y ? AstroMath.separation(x, y) : AstroMath.separation(y, x)
    }

    /// Total order: tightest orb, then the display order of each side, then aspect angle.
    /// Every field is compared so no two distinct results can compare equal in both directions.
    private static func tighterFirst(_ a: CrossAspect, _ b: CrossAspect) -> Bool {
        if a.orb != b.orb { return a.orb < b.orb }
        if a.moving != b.moving { return a.moving.displayOrder < b.moving.displayOrder }
        if a.reference != b.reference { return a.reference.displayOrder < b.reference.displayOrder }
        return a.type.angle < b.type.angle
    }
}

private extension CelestialBody {
    /// Position in `allCases` — the demo's display order, used only as a sort tie-break.
    var displayOrder: Int { CelestialBody.allCases.firstIndex(of: self) ?? 0 }
}
