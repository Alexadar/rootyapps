import Foundation
import simd

/// The palette, measured from the game's own art.
///
/// **Do not invent a colour.** Every value below is either a hex sampled from one of the three
/// source PNGs or is derived from one with the derivation stated on the line. This is the same rule
/// `citypigeon/CityPigeon/Render/Palette.swift` follows, and it is the oracle discipline applied to
/// art: the implementation comes from one place and the numbers from another.
///
/// Sources, all under `BigPinkCat/output_story/images/`, sampled by 12-colour median-cut
/// quantisation at 256×256:
///
///   * `char2.png` — the Big Pink Cat. Supplies the wine→pink family.
///   * `char1.png` — the astronaut. Supplies the suit navies and the amber instrumentation warmth.
///   * `style.png` — the environment key art. Supplies the void teals.
///
/// The marketing gradient (#FF69B4 → #8B008B) that shipped on the 2025 store screenshots is
/// **not** a source. It was chosen for a screenshot, and it is nowhere in the actual art — the cat's
/// real pink is duller and warmer than that, and the difference is the whole character of the thing.
enum Palette {

    // MARK: - Measured: the cat (char2.png)

    /// 16.0% of the cat. Its shadow side, and the darkest value that still reads as pink.
    static let catShadow = rgb(0x5F2D3F)
    /// 7.8%. The pink everyone actually means when they say "big pink cat".
    static let catPink = rgb(0xD7687F)
    /// 6.9%. The midtone between shadow and light.
    static let catMid = rgb(0xA54A63)
    /// 5.8%, and the most saturated colour in the entire source set (S = 0.67). Reserved, like
    /// kerfcalc's signal yellow, for exactly the loud things.
    static let catSignal = rgb(0x8E2F51)
    /// 8.2%. Warm pale highlight along the cat's lit edge.
    static let catHighlight = rgb(0xF4B9AB)
    /// 9.8%. The purple the cat's darks fall into before they reach true black.
    static let voidPurple = rgb(0x27182D)

    // MARK: - Measured: the astronaut (char1.png)

    /// 13.1%. Deep navy — the suit in shadow, and the darkest structural colour available.
    static let suitDark = rgb(0x121C2E)
    /// 11.3%. Suit midtone, blue-grey.
    static let suitMid = rgb(0x3E4C5C)
    /// 7.3%. Suit white, slightly warm.
    static let suitLight = rgb(0xCFCBC5)
    /// 6.7%. The brightest value in any source image.
    static let suitBright = rgb(0xEFEBE4)
    /// 8.7% and 5.2%. The amber trim and visor glow. This is the game's instrumentation colour:
    /// anything the engineer reads off a gauge is one of these two.
    static let amber = rgb(0xCD8856)
    static let amberBright = rgb(0xEFB162)
    /// 6.1%. Cool grey-blue, the suit's specular.
    static let suitSpecular = rgb(0xA4B5B8)

    // MARK: - Measured: the environment (style.png)

    /// 13.3%. Deep teal — the colour the void is, in this game's art, rather than black.
    static let voidTeal = rgb(0x285767)
    /// 7.0%. The bright teal that lifts it.
    static let voidTealBright = rgb(0x459AA0)
    /// 12.9%. The purple-dark that sits between the teal and true shadow.
    static let voidDark = rgb(0x382C40)
    /// 9.2% and 7.2%. Warm rust, for anything hot.
    static let hotRust = rgb(0xBB624A)
    static let hotBright = rgb(0xD48051)

    // MARK: - Derived, with the derivation stated

    /// The event horizon. **Derived:** `voidPurple` taken to 12% value — not pure black, because a
    /// true #000000 hole against a dark scene reads as a rendering failure rather than as a hole,
    /// and because nothing else in this palette is pure black either.
    static let horizon = voidPurple * 0.12

    /// The ergosphere's tint. **Derived:** `catSignal`, the most saturated source colour, at 35%
    /// mixed over `voidTeal`. The work site gets the loudest colour in the palette because "you
    /// cannot stand still here" is the loudest rule in the game.
    static let ergosphere = mix(voidTeal, catSignal, 0.35)

    /// The bubble wall. **Derived:** `voidTealBright` lifted toward `suitBright` by 25% — it is a
    /// human-made surface, so it belongs to the suit's family rather than the void's.
    static let bubbleWall = mix(voidTealBright, suitBright, 0.25)

    /// Gravitational redshift ramp, far → deep. **Derived:** the measured warm family in value
    /// order — `amberBright` → `hotBright` → `hotRust` → `catSignal` → `horizon`. Redshift is
    /// physically a shift toward longer wavelengths, and this ramp happens to already run that way
    /// in the source art, which is why no new colour was needed.
    static let redshiftRamp: [SIMD3<Float>] = [amberBright, hotBright, hotRust, catSignal, horizon]

    /// Relativistic blueshift, for the approaching side of a disk. **Derived:** `suitSpecular`
    /// pushed 40% toward `voidTealBright`, the only cool pair in the measured set.
    static let blueshift = mix(suitSpecular, voidTealBright, 0.4)

    /// Background, far exterior. **Derived:** `voidDark` at 45% — the sky is the void seen from
    /// safely far away, so it is the same colour with the drama taken out.
    static let skyFar = voidDark * 0.45

    /// Background, deep field. **Derived:** `suitDark` at 30%, the darkest structural navy.
    static let skyDeep = suitDark * 0.30

    // MARK: - Helpers

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255.0,
              Float((hex >> 8) & 0xFF) / 255.0,
              Float(hex & 0xFF) / 255.0)
    }

    /// Linear blend, `t = 0` gives `a`.
    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    /// Sample the redshift ramp at `t ∈ [0, 1]`, 0 = far away, 1 = at the horizon.
    static func redshift(_ t: Float) -> SIMD3<Float> {
        let clamped = Swift.min(Swift.max(t, 0), 1)
        let scaled = clamped * Float(redshiftRamp.count - 1)
        let i = Int(scaled)
        if i >= redshiftRamp.count - 1 { return redshiftRamp[redshiftRamp.count - 1] }
        return mix(redshiftRamp[i], redshiftRamp[i + 1], scaled - Float(i))
    }

    /// Every colour that must be traceable to a source pixel or a stated derivation.
    /// `PaletteTests` walks this so a newly invented colour fails the build.
    static let allNamed: [(String, SIMD3<Float>)] = [
        ("catShadow", catShadow), ("catPink", catPink), ("catMid", catMid),
        ("catSignal", catSignal), ("catHighlight", catHighlight), ("voidPurple", voidPurple),
        ("suitDark", suitDark), ("suitMid", suitMid), ("suitLight", suitLight),
        ("suitBright", suitBright), ("amber", amber), ("amberBright", amberBright),
        ("suitSpecular", suitSpecular), ("voidTeal", voidTeal),
        ("voidTealBright", voidTealBright), ("voidDark", voidDark),
        ("hotRust", hotRust), ("hotBright", hotBright),
        ("horizon", horizon), ("ergosphere", ergosphere), ("bubbleWall", bubbleWall),
        ("blueshift", blueshift), ("skyFar", skyFar), ("skyDeep", skyDeep),
    ]

    /// The 18 hexes sampled directly from the PNGs. A derived colour must be reachable from these.
    static let measuredHexes: [UInt32] = [
        0x5F2D3F, 0xD7687F, 0xA54A63, 0x8E2F51, 0xF4B9AB, 0x27182D,
        0x121C2E, 0x3E4C5C, 0xCFCBC5, 0xEFEBE4, 0xCD8856, 0xEFB162, 0xA4B5B8,
        0x285767, 0x459AA0, 0x382C40, 0xBB624A, 0xD48051,
    ]
}
