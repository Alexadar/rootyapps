import Foundation
import TarotKit

/// The scenario's reading, streamed through the same seam the real model uses.
///
/// The text is real on-device output captured once; this replays it at a fixed cadence so a
/// take is repeatable. Everything above `ReadingWriter` — the composer, the reveal frontier,
/// the auto-follow scroll, the auto-expanding panel — cannot tell the difference, which is the
/// whole point of having had the protocol in the first place.
///
/// Three contracts it has to honour, all of them learned from the real writer:
///  • `availability` must be `.available`, or `ReadingComposer.start` short-circuits to
///    `.unavailable` and nothing streams at all;
///  • every yield is the WHOLE draft so far — the composer replaces its draft on each yield
///    rather than accumulating;
///  • the shape of a partial draft must be one guided generation could actually produce:
///    passages fill in order, never empty, synthesis last.
@MainActor
final class ScriptedWriter: ReadingWriter {

    private let scenario: FilmScenario

    init(scenario: FilmScenario) {
        self.scenario = scenario
    }

    var availability: WriterAvailability { .available }

    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        let passages = scenario.passages
        // A one-position method has no synthesis field in its generable form, so a scripted
        // one would be filming a screen the app cannot produce.
        let synthesis = spread.positions.count == 1 ? nil : scenario.synthesis
        let total = passages.reduce(0) { $0 + $1.count } + (synthesis?.count ?? 0)
        let writing = scenario.writing
        let perChunk = max(1, Int((writing.charsPerSecond * writing.chunkInterval).rounded()))
        let chunks = max(1, Int(ceil(Double(total) / Double(perChunk))))

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                // The model takes real time to think before its first word, and the reading
                // panel is timed to open while text is still arriving. Absolute deadlines on
                // a monotonic clock, never accumulated sleeps: jitter must not compound over
                // a thirty-second stream, or two takes drift apart.
                let start = ContinuousClock.now
                try? await Task.sleep(until: start + .seconds(writing.firstDelay),
                                      clock: .continuous)
                for chunk in 1...chunks {
                    guard !Task.isCancelled else { return }
                    continuation.yield(Self.draft(budget: chunk * perChunk,
                                                  passages: passages, synthesis: synthesis))
                    let deadline = start + .seconds(writing.firstDelay
                                                    + Double(chunk) * writing.chunkInterval)
                    try? await Task.sleep(until: deadline, clock: .continuous)
                }
                guard !Task.isCancelled else { return }
                continuation.yield(Self.draft(budget: total, passages: passages, synthesis: synthesis))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole draft at a character budget — pure, so the reveal shape is testable.
    ///
    /// Passages fill sequentially and no element is ever empty: `ReadingOverlay` draws a gold
    /// position label for every element of `passages`, so an empty one shows a heading with
    /// nothing under it, which the real writer never produces. Prefixes stop on a word
    /// boundary because the reveal frontier chases `text.count`, and a half-word makes it
    /// stutter backwards over the same glyph.
    nonisolated static func draft(budget: Int, passages: [String], synthesis: String?) -> PassageDraft {
        var draft = PassageDraft()
        var remaining = budget
        for passage in passages {
            guard remaining > 0 else { break }
            if remaining >= passage.count {
                draft.passages.append(passage)
                remaining -= passage.count
            } else {
                let prefix = wordPrefix(of: passage, count: remaining)
                if !prefix.isEmpty { draft.passages.append(prefix) }
                remaining = 0
            }
        }
        // Synthesis only once every passage is complete — the order guided generation fills.
        if let synthesis, draft.passages.count == passages.count, remaining > 0 {
            let prefix = remaining >= synthesis.count ? synthesis
                                                      : wordPrefix(of: synthesis, count: remaining)
            if !prefix.isEmpty { draft.synthesis = prefix }
        }
        return draft
    }

    nonisolated private static func wordPrefix(of text: String, count: Int) -> String {
        guard count < text.count else { return text }
        let cut = text.index(text.startIndex, offsetBy: count)
        if let space = text[..<cut].lastIndex(where: { $0 == " " || $0 == "\n" }) {
            return String(text[..<space])
        }
        return ""
    }
}
