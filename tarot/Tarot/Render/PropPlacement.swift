import CardMotionKit
import Foundation

/// Where the séance props may stand — COMPUTED, never eyeballed (owner, 2026-08-17:
/// candles must not interfere with flying cards, and must not sit on any possible card
/// spot). The first ring was placed by eye and half of it fell inside the area a dragged
/// card can reach; this file makes that impossible by construction.
///
/// The rule: a card is centred on the pointer, and the pointer is clamped to the table
/// extents of whatever layout is in play. Grow that clamp rectangle by the card's
/// half-diagonal (a card may be tilted) and you have a rectangle no card can ever leave —
/// across EVERY layout, so switching method can't invalidate a placement. Props live
/// strictly outside it.
enum PropPlacement {

    /// Every layout a card can be played in. A new method automatically widens the
    /// forbidden zone and pushes the props out — no coordinate needs re-checking by hand.
    static let layouts: [MotionConfig] = [.oneCard, .threeCard, .fiveCrossroads, .celticCross]

    /// The half-extents of the rectangle a card can never leave.
    static let cardReach: (x: Double, z: Double) = {
        var x = 0.0, z = 0.0
        for c in layouts {
            let halfDiagonal = (c.cardWidth * c.cardWidth + c.cardLength * c.cardLength)
                .squareRoot() / 2
            x = max(x, c.tableExtentX + halfDiagonal)
            z = max(z, c.tableExtentZ + halfDiagonal)
        }
        return (x, z)
    }()

    /// Breathing room between the forbidden rectangle and the nearest prop surface.
    static let margin = 0.05

    /// Can any card touch a prop of this footprint standing here?
    static func isClear(x: Double, z: Double, radius: Double) -> Bool {
        abs(x) >= cardReach.x + radius + margin || abs(z) >= cardReach.z + radius + margin
    }

    /// The smallest distance from the table centre, along `angle`, at which a prop of
    /// `radius` clears the rectangle. Near the z axis that is close in (the table is
    /// shallow); out along x it is far — so the prop ring traces the true frontier of
    /// play rather than a circle that ignores it.
    static func safeRadius(angle: Double, radius: Double) -> Double {
        let x = (cardReach.x + radius + margin) / max(abs(cos(angle)), 1e-9)
        let z = (cardReach.z + radius + margin) / max(abs(sin(angle)), 1e-9)
        return min(x, z)
    }

    struct Candle {
        let x: Double, z: Double
        /// Wax radius and body height, table units.
        let radius: Double, height: Double
        /// Private flicker phase — the candle's shader, its flame and its light share it.
        let phase: Double
        /// Whether this one carries a real dynamic point light. Almost none do: a light
        /// is paid for by every lit fragment on screen, while the warmth a candle throws
        /// on the cloth is baked into the lightmap and its flame lights itself. Only the
        /// reader's own pair — the ones close enough to touch the cards — stay dynamic.
        let lit: Bool
    }

    /// A ring of candles hugging the frontier: twelve around the table, plus two taller
    /// ones drawn in close on the left where the reader's hand would rest.
    static let candles: [Candle] = {
        var out: [Candle] = []
        // Varied on a fixed cycle so the ring reads as a set of real candles burned to
        // different lengths, not a stamped pattern. Deterministic: no RNG in a renderer.
        let sizes: [(Double, Double)] = [(0.052, 0.175), (0.040, 0.105), (0.046, 0.140),
                                         (0.036, 0.085), (0.050, 0.155), (0.042, 0.120)]
        for i in 0..<12 {
            let angle = Double(i) * .pi / 6 + 0.13
            let (radius, height) = sizes[i % sizes.count]
            // Sit exactly on the frontier, plus a hair of outward stagger per candle.
            let r = safeRadius(angle: angle, radius: radius) + Double(i % 3) * 0.035
            out.append(Candle(x: cos(angle) * r, z: sin(angle) * r,
                              radius: radius, height: height,
                              phase: Double(i) * 1.37, lit: false))
        }
        // The reader's own pair: closest the geometry allows, on the near-left diagonal.
        for (k, angle) in [2.62, 2.30].enumerated() {
            let radius = k == 0 ? 0.058 : 0.048
            let r = safeRadius(angle: angle, radius: radius) + 0.02
            out.append(Candle(x: cos(angle) * r, z: sin(angle) * r,
                              radius: radius, height: k == 0 ? 0.20 : 0.13,
                              phase: 0.4 + Double(k) * 2.1, lit: true))
        }
        return out
    }()

    /// The crystal ball's glass radius, and where it stands: the far right, out past the
    /// frontier, where a portrait frame still shows it because the table is deeper than
    /// it is wide.
    static let ballRadius = 0.13
    static let ballCentre: (x: Double, z: Double) = {
        // ≈ −67.6°: right of the spread and behind it, and deliberately halfway between
        // two ring candles so the glass gets air around it.
        let angle = -1.18
        let r = safeRadius(angle: angle, radius: ballRadius) + 0.02
        return (cos(angle) * r, sin(angle) * r)
    }()
}
