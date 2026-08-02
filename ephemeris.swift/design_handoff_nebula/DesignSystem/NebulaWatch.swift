import SwiftUI

/// Nebula on watchOS. The watch app is a **standalone product** — it ships its own
/// App Store listing and must read on its own, so nothing here assumes the phone.
///
/// Design floor is 41 mm = 176×215 pt. If it fails there it fails.
/// Palette and text hierarchy come from NebulaPalette; this file only carries the
/// watch-specific geometry, the stripped wheel, and the type scale.
enum NebulaWatch {

    // MARK: - Type scale
    //
    // SF Compact. Two sizes only: 41 mm and 49 mm. Numerics are ALWAYS
    // .monospacedDigit() at full size — a degree value must never quietly compress.
    //
    // role                 41 mm      49 mm      weight
    // centre readout       12 / 13    11.5/12.5  bold / semibold
    // planet glyph         13         13         regular
    // sign glyph (ring)    10         9.5        regular   (♈ ♋ ♎ ♑ only at 41 mm)
    // row value (mono)     13.5       14.5       regular · monospacedDigit
    // row primary          12.5       13.5       regular
    // section header       10         11         semibold
    // faint / caption      9.5        10.5       regular
    //
    // Four rules that make 17 languages safe:
    //  1. Glyphs and numbers carry the data. Wheel, Positions and every
    //     complication contain NO translatable prose — byte-identical in all 17.
    //  2. No uppercase for CJK: .textCase(nil) and tracking 0 outside Latin.
    //  3. A label never shares a line with its value. "Nächster Zeichenwechsel"
    //     cannot fit beside a date at 176 pt, so it gets its own row.
    //  4. One step of shrink then wrap: .minimumScaleFactor(0.85) + .lineLimit(2)
    //     on prose only, never on numerics.

    static func size(_ mm41: CGFloat, _ mm49: CGFloat, large: Bool) -> CGFloat {
        large ? mm49 : mm41
    }

    /// True when the screen is 49 mm or wider. Drive it from the actual bounds
    /// rather than a device enum so future sizes fall on the right side.
    static func isLarge(_ width: CGFloat) -> Bool { width >= 195 }

    // MARK: - Corner-safe insets
    //
    // The display corner radius (54 pt at 41 mm, 60 pt at 49 mm) eats content near
    // the corners. At a header baseline of y ≈ 13 pt the required left inset is
    // R - sqrt(R² - (R-y)²) ≈ 12.8 pt at 41 mm — more than the 10 pt you would
    // naturally reach for.
    //
    // Rather than fight that per-screen, **screen headers are centred groups**, not
    // edge-to-edge HStacks with a Spacer. Centring removes the problem structurally
    // and costs no vertical space, which matters because Now is already full.
    static func cornerSafeInset(radius R: CGFloat, atY y: CGFloat) -> CGFloat {
        guard y < R else { return 0 }
        return R - sqrt(max(R * R - (R - y) * (R - y), 0))
    }

    // MARK: - Wheel geometry (fractions of the square side `s`)
    //
    // The stripped wheel is legible at 41 mm ONLY with all three of these. Drop any
    // one and it fails:
    //  1. Two planet tracks with collision de-clustering (below).
    //  2. Cardinal signs only at 41 mm — twelve glyphs in a 10 pt band forces
    //     ~8.5 pt, under the floor. All twelve return at 49 mm.
    //  3. Precision lives in the CENTRE, never on the ring. You cannot read
    //     arcminutes off a 108 pt circle. The ring carries gestalt and motion; the
    //     hole carries the authoritative date/time and becomes the scrub readout.
    static let ringOuter: CGFloat = 0.432   // zodiac band outer
    static let ringInner: CGFloat = 0.375   // zodiac band inner
    static let signRadius: CGFloat = 0.403  // sign glyph centre
    static let trackOuter: CGFloat = 0.307  // primary planet track
    static let trackInner: CGFloat = 0.227  // de-clustered planet track
    static let coreRadius: CGFloat = 0.176  // centre readout

    /// Minimum angular separation before two glyphs collide, in degrees.
    /// At r ≈ 54 pt a 13 pt glyph subtends ~14°, so 15° is the threshold.
    static let minSeparation: Double = 15

    /// Two-track de-clustering. Real charts cluster constantly — on 29 Jul 2026
    /// Jupiter and the Sun are 0.4° apart in Leo, Saturn and Neptune 9.8° apart in
    /// Aries. Without this the wheel is a blob roughly one week in three.
    ///
    /// Returns each body's longitude paired with a track index (0 = outer, 1 = inner).
    static func declusterTracks(longitudes: [Double]) -> [(lon: Double, track: Int)] {
        let sorted = longitudes.sorted()
        var out: [(lon: Double, track: Int)] = []
        for (i, lon) in sorted.enumerated() {
            guard i > 0 else { out.append((lon, 0)); continue }
            let gap = lon - sorted[i - 1]
            out.append((lon, gap < minSeparation ? (out[i - 1].track + 1) % 2 : 0))
        }
        // Wrap-around: if the last and first are within minSeparation, push the last inward.
        if out.count > 1, (360 - out[out.count - 1].lon) + out[0].lon < minSeparation,
           out[0].track == out[out.count - 1].track {
            out[out.count - 1].track = (out[0].track + 1) % 2
        }
        return out
    }

    /// Cardinal signs get a glyph at 41 mm; the rest are tick marks only.
    static func labelsSign(_ index: Int, large: Bool) -> Bool { large || index % 3 == 0 }

    // MARK: - Digital Crown
    //
    // The crown is the whole point of this app: it scrubs time and moves the
    // planets around the ring. It is the one interaction the watch does better
    // than the phone, so it is the hero, not a secondary control.
    //
    //   .digitalCrownRotation($offsetDays,
    //                         from: -3650, through: 3650, by: 0.02,
    //                         sensitivity: .medium,
    //                         isContinuous: false,
    //                         isHapticFeedbackEnabled: true)
    //
    // Mid-scrub state: header switches to "SCRUBBING" + signed delta in accent,
    // the centre readout ring tints accent, planets leave short motion trails along
    // their track, and the sign ring dims to 60% so the moving glyphs dominate.
    // Everything recomputes per frame — no throttling, no loading state.
    static let scrubStep: Double = 0.02          // days per crown detent (~29 min)
    static let trailOpacity: Double = 0.45
}
