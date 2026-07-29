import SwiftUI

/// Deep-space backdrop for the Nebula theme. Replaces the existing `AppBackground`.
///
/// Layers, bottom → top:
///   1. Vertical gradient  #0C0525 → #10082E
///   2. Magenta glow  radial from top-left  (#3A0E6B)
///   3. Cyan glow      radial from upper-right (#0E3A6B)
///   4. Star field     (deterministic, faint)
struct NebulaBackground: View {
    // Shared so tilt persists across tab switches / view rebuilds.
    @ObservedObject private var motion = MotionParallax.shared

    var body: some View {
        // Glow radii are proportional to the canvas, not absolute. At the phone's ~390pt width
        // the original 520/460 read as two soft corner glows; on a 176pt watch face the same
        // numbers cover the whole screen, so the cyan flooded it and the backdrop came out blue
        // instead of purple. Expressed as multiples of the width they look identical at any size.
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            ZStack {
                // ── Layer 0: static, fixed. Purple gradient + glows never move. ──
                LinearGradient(colors: [NebulaPalette.bgTop, NebulaPalette.bgBottom],
                               startPoint: .top, endPoint: .bottom)

                RadialGradient(colors: [NebulaPalette.glowMagenta.opacity(0.9), .clear],
                               center: UnitPoint(x: 0.18, y: 0.0),
                               startRadius: 0, endRadius: w * 1.33)

                RadialGradient(colors: [NebulaPalette.glowCyan.opacity(0.8), .clear],
                               center: UnitPoint(x: 0.92, y: 0.26),
                               startRadius: 0, endRadius: w * 1.18)

                // ── Layer 1: stars only. Parallax happens *inside* the canvas (overscanned
                //    field), so this transparent layer always fills the screen. ──
                StarField(tilt: motion.tilt)
            }
        }
        .ignoresSafeArea()
        .onAppear { motion.start() }
    }
}

/// A faint star field with a brisk per-star twinkle plus tilt parallax. Positions are
/// seeded (stable) and drawn over an area larger than the canvas by `margin` on every side,
/// then shifted by the tilt — so the parallax never exposes a bare edge. Driven at 10fps.
private struct StarField: View {
    var tilt: CGSize

    /// Fewer, slower stars on the wrist. 90 stars at 10fps is right for a phone and is both
    /// visually cluttered and needlessly expensive on a 176pt screen — watchOS already pauses
    /// animation when the wrist drops, but there is no reason to burn the frames it does render.
    #if os(watchOS)
    static let starCount = 34
    static let frameInterval = 0.2
    #else
    static let starCount = 90
    static let frameInterval = 0.1
    #endif

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval)) { tl in
            let time = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let margin = 26.0                       // ≥ max parallax shift (|tilt|·18 ≤ 18)
                let dx = tilt.width * 18, dy = tilt.height * 18
                var rng = SeededRNG(seed: 0xEDA5)
                for _ in 0..<Self.starCount {
                    let x = -margin + Double(rng.next()) / Double(UInt32.max) * (size.width + 2 * margin)
                    let y = -margin + Double(rng.next()) / Double(UInt32.max) * (size.height + 2 * margin)
                    let r = 0.6 + Double(rng.next()) / Double(UInt32.max) * 1.1
                    let baseA = 0.25 + Double(rng.next()) / Double(UInt32.max) * 0.5
                    let phase = Double(rng.next()) / Double(UInt32.max) * 2 * .pi
                    let speed = 1.2 + Double(rng.next()) / Double(UInt32.max) * 1.4   // brisk turnover
                    let twinkle = 0.5 + 0.5 * sin(time * speed + phase)
                    let a = baseA * (0.4 + 0.6 * twinkle)                             // never fully off
                    let rect = CGRect(x: x + dx, y: y + dy, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Tiny xorshift RNG for a repeatable star field.
private struct SeededRNG {
    var state: UInt32
    init(seed: UInt32) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt32 {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return state
    }
}
