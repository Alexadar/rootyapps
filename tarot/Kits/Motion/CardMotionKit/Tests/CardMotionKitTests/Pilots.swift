import Foundation
@testable import CardMotionKit

/// Scripted pilots: deterministic intent generators that stand where the thumb stands
/// (citypigeon's `Policy` pattern). Each produces an `[N]`-shaped intent per tick, varied
/// per world from the seed, so a batch of 256 is 256 *different* drags through the same code.
///
/// Tests may loop freely — the discipline binds Sources, not Tests.
enum Pilots {

    static func uniform(seed: UInt64, tick: UInt64, stream: UInt64, world: Int) -> Double {
        let bits = LaneNoise.combined(seed: seed, tick: tick, stream: stream,
                                      world: UInt64(world), lane: 0)
        return Double(bits >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// One full three-card draw: for each slot, press on the deck, drag to the slot along a
    /// slightly-noisy path, release, wait out the flight. Completes a draw in every world.
    static func scriptedDraw(worlds n: Int, seed: UInt64, config: MotionConfig,
                             tick: UInt64, dt: Double) -> MotionIntent {
        let t = Double(tick) * dt
        let phaseDuration = 2.0                      // grab+drag+release+settle per card
        let card = min(Int(t / phaseDuration), config.slotCount - 1)
        let local = (t - Double(card) * phaseDuration) / phaseDuration   // 0..1 within card

        var pxs = [Double](repeating: 0, count: n)
        var pzs = [Double](repeating: 0, count: n)
        var press = [Double](repeating: 0, count: n)
        for w in 0..<n {
            let jx = (uniform(seed: seed, tick: UInt64(card), stream: 10, world: w) - 0.5) * 0.08
            let jz = (uniform(seed: seed, tick: UInt64(card), stream: 11, world: w) - 0.5) * 0.08
            let from = (x: config.deckX + jx, z: config.deckZ + jz)
            let to = (x: config.slotX[card] + jx * 0.5, z: config.slotZ[card] + jz * 0.5)
            // 0.0–0.1: approach deck; 0.1–0.6: drag; at 0.6: release; then settle.
            let drag = min(max((local - 0.1) / 0.5, 0), 1)
            let eased = drag * drag * (3 - 2 * drag)
            pxs[w] = from.x + (to.x - from.x) * eased
            pzs[w] = from.z + (to.z - from.z) * eased
            press[w] = (local >= 0.02 && local < 0.6) ? 1 : 0
        }
        return MotionIntent(pointerX: Tensor(shape: [n], data: pxs),
                            pointerZ: Tensor(shape: [n], data: pzs),
                            press: Tensor(shape: [n], data: press),
                            lightX: .zeros([n]), lightZ: .zeros([n]))
    }

    /// Pointer teleports violently every few frames while holding — the stress test for the
    /// follow/velocity smoothing and the roll clamp.
    static func jerkyDrag(worlds n: Int, seed: UInt64, config: MotionConfig,
                          tick: UInt64, dt: Double) -> MotionIntent {
        var pxs = [Double](repeating: 0, count: n)
        var pzs = [Double](repeating: 0, count: n)
        var press = [Double](repeating: 0, count: n)
        let jump = tick / 7        // a new random target every 7 ticks
        for w in 0..<n {
            if tick < 3 {
                pxs[w] = config.deckX
                pzs[w] = config.deckZ
            } else {
                pxs[w] = (uniform(seed: seed, tick: jump, stream: 12, world: w) - 0.5) * 2 * config.tableExtentX
                pzs[w] = (uniform(seed: seed, tick: jump, stream: 13, world: w) - 0.5) * 2 * config.tableExtentZ
            }
            press[w] = tick >= 1 ? 1 : 0
        }
        return MotionIntent(pointerX: Tensor(shape: [n], data: pxs),
                            pointerZ: Tensor(shape: [n], data: pzs),
                            press: Tensor(shape: [n], data: press),
                            lightX: .zeros([n]), lightZ: .zeros([n]))
    }

    /// Grab, fling fast toward nowhere in particular, release mid-motion — exercises the
    /// return flight with a large Hermite tangent.
    static func fling(worlds n: Int, seed: UInt64, config: MotionConfig,
                      tick: UInt64, dt: Double) -> MotionIntent {
        let t = Double(tick) * dt
        var pxs = [Double](repeating: 0, count: n)
        var pzs = [Double](repeating: 0, count: n)
        var press = [Double](repeating: 0, count: n)
        for w in 0..<n {
            // Angle restricted to the +z half-plane: away from the slots (z = −0.30), so a
            // fling is always a return flight — the slot-landing path has its own pilot.
            let angle = uniform(seed: seed, tick: 0, stream: 14, world: w) * Double.pi
            let speed = 2.5 + uniform(seed: seed, tick: 0, stream: 15, world: w) * 2
            if t < 0.15 {
                pxs[w] = config.deckX
                pzs[w] = config.deckZ
                press[w] = t >= 0.05 ? 1 : 0
            } else if t < 0.4 {
                pxs[w] = config.deckX + cos(angle) * speed * (t - 0.15)
                pzs[w] = config.deckZ + sin(angle) * speed * (t - 0.15)
                press[w] = 1
            } else {
                press[w] = 0        // pointer position irrelevant after release
            }
        }
        return MotionIntent(pointerX: Tensor(shape: [n], data: pxs),
                            pointerZ: Tensor(shape: [n], data: pzs),
                            press: Tensor(shape: [n], data: press),
                            lightX: .zeros([n]), lightZ: .zeros([n]))
    }

    /// Press and release on the deck within two frames — the degenerate tap.
    static func tap(worlds n: Int, seed: UInt64, config: MotionConfig,
                    tick: UInt64, dt: Double) -> MotionIntent {
        let press = (tick == 2 || tick == 3) ? 1.0 : 0.0
        return MotionIntent(pointerX: Tensor(repeating: config.deckX, shape: [n]),
                            pointerZ: Tensor(repeating: config.deckZ, shape: [n]),
                            press: Tensor(repeating: press, shape: [n]),
                            lightX: .zeros([n]), lightZ: .zeros([n]))
    }

    /// Nothing at all — the idle table. Ambient wobble only.
    static func idle(worlds n: Int, seed: UInt64, config: MotionConfig,
                     tick: UInt64, dt: Double) -> MotionIntent {
        MotionIntent.idle(worlds: n)
    }

    typealias Pilot = (Int, UInt64, MotionConfig, UInt64, Double) -> MotionIntent

    static let all: [(name: String, pilot: Pilot)] = [
        ("scriptedDraw", scriptedDraw),
        ("jerkyDrag", jerkyDrag),
        ("fling", fling),
        ("tap", tap),
        ("idle", idle),
    ]

    /// Run a pilot for `steps` ticks, invoking `inspect` after every step.
    static func run(_ pilot: Pilot, worlds n: Int, seed: UInt64, config: MotionConfig,
                    steps: Int, dt: Double = 1.0 / 120.0,
                    inspect: (MotionWorld, MotionEvents, UInt64) -> Void = { _, _, _ in }) -> MotionWorld {
        var world = MotionWorld(batch: n, config: config, seed: seed)
        for tick in 0..<steps {
            let intent = pilot(n, seed, config, UInt64(tick), dt)
            let events = MotionStep.advance(&world, intent: intent, dt: dt, config: config)
            inspect(world, events, UInt64(tick))
        }
        return world
    }
}

/// A small config for tests that don't need 78 lanes: capacity 8 keeps the batch fast while
/// exercising exactly the same kernel.
extension MotionConfig {
    static var test: MotionConfig {
        var c = MotionConfig()
        c.cardCapacity = 8
        return c
    }
    /// Any layout, capacity trimmed for test speed (never below the slot count + a spare).
    static func test(_ layout: MotionConfig) -> MotionConfig {
        var c = layout
        c.cardCapacity = max(8, layout.slotCount + 2)
        return c
    }
    static var testReduced: MotionConfig {
        var c = MotionConfig.test
        c.reduceMotion = true
        return c
    }
}
