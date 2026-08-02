import SwiftUI

/// Deep-space backdrop for the Nebula theme. Replaces the existing `AppBackground`.
///
/// Layers, bottom → top:
///   1. Vertical gradient  #0C0525 → #10082E
///   2. Magenta glow  radial from top-left  (#3A0E6B)
///   3. Cyan glow      radial from upper-right (#0E3A6B)
///   4. Star field     (deterministic, faint)
struct NebulaBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [NebulaPalette.bgTop, NebulaPalette.bgBottom],
                           startPoint: .top, endPoint: .bottom)

            RadialGradient(colors: [NebulaPalette.glowMagenta.opacity(0.9), .clear],
                           center: UnitPoint(x: 0.18, y: 0.0),
                           startRadius: 0, endRadius: 520)

            RadialGradient(colors: [NebulaPalette.glowCyan.opacity(0.8), .clear],
                           center: UnitPoint(x: 0.92, y: 0.26),
                           startRadius: 0, endRadius: 460)

            StarField()
        }
        .ignoresSafeArea()
    }
}

/// A faint, static star field. Seeded so it never shimmers between frames.
private struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: 0xEDA5)
            for _ in 0..<90 {
                let x = Double(rng.next()) / Double(UInt32.max) * size.width
                let y = Double(rng.next()) / Double(UInt32.max) * size.height
                let r = 0.6 + Double(rng.next()) / Double(UInt32.max) * 1.1
                let a = 0.25 + Double(rng.next()) / Double(UInt32.max) * 0.5
                let rect = CGRect(x: x, y: y, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
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
