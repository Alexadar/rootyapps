import XCTest
import CardMotionKit
@testable import Tarot

/// The props must never share space with play (owner, 2026-08-17: candles must not
/// interfere with flying cards, nor stand on any possible card spot). The first ring was
/// eyeballed and half of it sat inside the reachable area — so the placement is computed
/// now, and this is the file that proves it, for every layout at once.
final class PropPlacementChecks: XCTestCase {

    /// A card is centred on the pointer; the pointer is clamped to the layout's table
    /// extents; the card may be tilted. Nothing the player does can push a card past
    /// `cardReach` — pinned here against the shipped layouts.
    func testCardReachCoversEveryLayout() {
        for config in PropPlacement.layouts {
            let halfDiagonal = (config.cardWidth * config.cardWidth
                                + config.cardLength * config.cardLength).squareRoot() / 2
            XCTAssertGreaterThanOrEqual(PropPlacement.cardReach.x,
                                        config.tableExtentX + halfDiagonal)
            XCTAssertGreaterThanOrEqual(PropPlacement.cardReach.z,
                                        config.tableExtentZ + halfDiagonal)
        }
        XCTAssertEqual(PropPlacement.layouts.count, 4, "a new method must join the reach")
    }

    /// Every shipped prop stands outside the reachable rectangle, with margin.
    func testEveryPropIsOutOfEveryCardsReach() {
        for candle in PropPlacement.candles {
            XCTAssertTrue(PropPlacement.isClear(x: candle.x, z: candle.z, radius: candle.radius),
                          "candle at (\(candle.x), \(candle.z)) is inside card reach")
        }
        XCTAssertTrue(PropPlacement.isClear(x: PropPlacement.ballCentre.x,
                                            z: PropPlacement.ballCentre.z,
                                            radius: PropPlacement.ballRadius),
                      "the crystal ball is inside card reach")
    }

    /// The stronger statement, checked the hard way: sweep every slot of every layout and
    /// every point the pointer clamp allows, and assert no card footprint ever overlaps a
    /// prop footprint. This is the claim the owner actually made — "not on all possible
    /// spots for cards" — rather than a proxy for it.
    func testNoCardPositionEverOverlapsAProp() {
        let props: [(x: Double, z: Double, r: Double)] =
            PropPlacement.candles.map { ($0.x, $0.z, $0.radius) }
            + [(PropPlacement.ballCentre.x, PropPlacement.ballCentre.z, PropPlacement.ballRadius)]

        for config in PropPlacement.layouts {
            let cardRadius = (config.cardWidth * config.cardWidth
                              + config.cardLength * config.cardLength).squareRoot() / 2
            // Every landing slot, exactly.
            for s in 0..<config.slotCount {
                for prop in props {
                    let dx = config.slotX[s] - prop.x, dz = config.slotZ[s] - prop.z
                    XCTAssertGreaterThan((dx * dx + dz * dz).squareRoot(), cardRadius + prop.r,
                                         "slot \(s) of a \(config.slotCount)-card layout overlaps a prop")
                }
            }
            // The deck, and then the whole reachable rectangle on a fine grid.
            var samples: [(Double, Double)] = [(config.deckX, config.deckZ)]
            let steps = 60
            for i in 0...steps {
                for j in 0...steps {
                    let x = -config.tableExtentX + 2 * config.tableExtentX * Double(i) / Double(steps)
                    let z = -config.tableExtentZ + 2 * config.tableExtentZ * Double(j) / Double(steps)
                    samples.append((x, z))
                }
            }
            for (x, z) in samples {
                for prop in props {
                    let dx = x - prop.x, dz = z - prop.z
                    XCTAssertGreaterThan((dx * dx + dz * dz).squareRoot(), cardRadius + prop.r,
                                         "a card centred at (\(x), \(z)) reaches a prop")
                }
            }
        }
    }

    /// The placement rule itself: a prop parked at the safe radius is clear in every
    /// direction, and one parked a hair inside it is not (a guard that cannot fail is
    /// not a guard — repo law).
    func testSafeRadiusIsTightAndActuallyBinding() {
        for degrees in stride(from: 0, to: 360, by: 7) {
            let angle = Double(degrees) * .pi / 180
            let radius = 0.05
            let safe = PropPlacement.safeRadius(angle: angle, radius: radius)
            let atSafe = (cos(angle) * safe, sin(angle) * safe)
            XCTAssertTrue(PropPlacement.isClear(x: atSafe.0, z: atSafe.1, radius: radius),
                          "safe radius is not safe at \(degrees)°")
            // Just inside it, the rule must reject — otherwise it is padding, not geometry.
            let inside = (cos(angle) * (safe - 0.02), sin(angle) * (safe - 0.02))
            XCTAssertFalse(PropPlacement.isClear(x: inside.0, z: inside.1, radius: radius),
                           "safe radius is loose at \(degrees)° — the frontier is wrong")
        }
    }

    /// The set itself stays a set: distinct candles, sane sizes, a few lights only.
    func testCandleSetIsWellFormed() {
        XCTAssertGreaterThanOrEqual(PropPlacement.candles.count, 12)
        for candle in PropPlacement.candles {
            XCTAssertGreaterThan(candle.radius, 0.02)
            XCTAssertGreaterThan(candle.height, 0.05)
        }
        // No two candles occupy the same spot.
        for (i, a) in PropPlacement.candles.enumerated() {
            for b in PropPlacement.candles[(i + 1)...] {
                let dx = a.x - b.x, dz = a.z - b.z
                XCTAssertGreaterThan((dx * dx + dz * dz).squareRoot(), a.radius + b.radius,
                                     "two candles overlap")
            }
        }
        // …and nothing crowds the crystal ball either.
        for candle in PropPlacement.candles {
            let dx = candle.x - PropPlacement.ballCentre.x
            let dz = candle.z - PropPlacement.ballCentre.z
            XCTAssertGreaterThan((dx * dx + dz * dz).squareRoot(),
                                 candle.radius + PropPlacement.ballRadius + 0.10,
                                 "a candle crowds the crystal ball")
        }
        // A performance guard with teeth: every dynamic light is paid for by every lit
        // fragment on screen, and nine of them are what cooked the M1 iPad. The candles'
        // warmth on the cloth is baked into the lightmap instead.
        let lit = PropPlacement.candles.filter(\.lit).count
        XCTAssertGreaterThan(lit, 0)
        XCTAssertLessThanOrEqual(lit, 2, "dynamic point lights must stay at 2 — bake the rest")
    }
}
