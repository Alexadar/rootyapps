import CardMotionKit
import Foundation

/// The take, as arithmetic. Pure on purpose: every beat of a filmed run is decided here, so
/// the whole choreography can be proven on a Mac with no device and no camera — and so a
/// future caption track can be computed from the same numbers the app plays rather than
/// measured off the video.
///
/// The clock is the kernel's already-clamped `dt`, never `Date()`. A dropped frame then slips
/// the cards and the script *together* instead of desynchronising them, which is what makes
/// two takes comparable.
struct ScenarioTimeline {
    let scenario: FilmScenario
    let config: MotionConfig

    /// What the director should do at scenario time `t`.
    struct Beat: Equatable {
        var typedCharacters: Int
        var shouldStartDraw: Bool
        var pointerX: Double
        var pointerZ: Double
        var press: Bool
        /// A named moment, emitted once, for the capture log (and a future caption track).
        var marker: String?
        var isOver: Bool
    }

    var cardCount: Int { scenario.cards.count }
    var typingEndsAt: Double { Double(scenario.question.count) * scenario.timing.typeInterval }
    var drawStartsAt: Double { typingEndsAt + scenario.timing.pauseAfter }
    var firstCardAt: Double { drawStartsAt + scenario.timing.settle }
    func cardStartsAt(_ k: Int) -> Double { firstCardAt + Double(k) * scenario.timing.perCard }
    var lastReleaseAt: Double {
        cardStartsAt(cardCount - 1) + scenario.timing.grabHold + scenario.timing.dragDuration
    }
    var readingOpensAt: Double { cardStartsAt(cardCount) + 1.1 }
    var endsAt: Double { readingOpensAt + scenario.timing.hold }

    func beat(at t: Double) -> Beat {
        let timing = scenario.timing
        var beat = Beat(typedCharacters: 0, shouldStartDraw: false,
                        pointerX: config.deckX, pointerZ: config.deckZ,
                        press: false, marker: nil, isOver: t >= endsAt)

        // 1 — the question types itself.
        beat.typedCharacters = min(scenario.question.count,
                                   max(0, Int(t / timing.typeInterval)))
        if t < drawStartsAt { return beat }

        // 2 — the draw begins (the director latches this; the timeline only says when).
        beat.shouldStartDraw = true
        guard t >= firstCardAt else { return beat }

        // 3 — one card per window: grab, drag, release, dwell.
        let k = Int((t - firstCardAt) / timing.perCard)
        guard k < cardCount else {
            // Past the last card the pointer must stay UP: a press here would zero the
            // landing hitstop and collapse the 1.1 s transition into the reading.
            return beat
        }
        let local = t - cardStartsAt(k)
        let slotX = config.slotX[min(k, config.slotCount - 1)]
        let slotZ = config.slotZ[min(k, config.slotCount - 1)]

        // The epsilon is deliberate: the release instant belongs to "released". Without it
        // the boundary lands on whichever side floating-point accumulation puts it, and the
        // one thing that must never happen is a press surviving into the landing — it would
        // zero the hitstop and collapse the transition into the reading.
        let epsilon = 1e-9
        if local < timing.grabHold - epsilon {
            beat.press = true                       // press on the deck, card lifts
        } else if local < timing.grabHold + timing.dragDuration - epsilon {
            let u = (local - timing.grabHold) / timing.dragDuration
            let eased = u * u * (3 - 2 * u)
            beat.pointerX = config.deckX + (slotX - config.deckX) * eased
            beat.pointerZ = config.deckZ + (slotZ - config.deckZ) * eased
            beat.press = true
        } else {
            beat.pointerX = slotX                   // released; the flight and the landing
            beat.pointerZ = slotZ                   // beat play out untouched
            beat.press = false
        }
        return beat
    }

    /// The named moments, in order — the capture log's beats, and the cut points a reel
    /// pipeline would trim against.
    var markers: [(key: String, at: Double)] {
        var out: [(String, Double)] = [("question", typingEndsAt), ("draw", drawStartsAt)]
        for k in 0..<cardCount {
            out.append(("card\(k)", cardStartsAt(k) + scenario.timing.grabHold + scenario.timing.dragDuration))
        }
        out.append(("reading", readingOpensAt))
        out.append(("end", endsAt))
        return out
    }
}
