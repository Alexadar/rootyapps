import Foundation

/// Limits on the model's output, kept together because they answer one question: when has the
/// model stopped writing a reading and started looping?
///
/// A 3-billion-parameter model sampling at temperature 0.8 can fall into a degenerate repetition
/// loop, and with no token ceiling it will keep going until it exhausts the context window —
/// minutes of output, ending in `exceededContextWindowSize`. That is not theoretical: it happened
/// on device, and it took the next draw down with it, because the service was still working on
/// the runaway request when the new one arrived.
public enum WritingLimits {

    /// The hard ceiling. `GenerationOptions.maximumResponseTokens` exists in the SDK and is
    /// documented nowhere prominent — it was left nil, which is what made a runaway possible at
    /// all. Sized per method from the sentence budget in the prompt, with roughly 2x headroom so
    /// a legitimately full reading is never truncated mid-word.
    public static func maximumTokens(for spread: Spread) -> Int {
        switch spread.positions.count {
        case 1: 400          // one card, five or six sentences
        case 5: 900
        case 10: 1400        // ten brief passages plus a synthesis
        default: 650         // three cards, measured at ~1350 characters
        }
    }

    /// Roughly the characters a well-behaved reading occupies, used only to spot output that has
    /// run far past any plausible length.
    public static func expectedCharacters(for spread: Spread) -> Int {
        switch spread.positions.count {
        case 1: 900
        case 5: 2400
        case 10: 3800
        default: 1600
        }
    }

    /// True when the text has stopped being a reading.
    ///
    /// Two independent signals, because repetition shows up in two shapes: the model repeats a
    /// whole sentence over and over, or it never terminates and simply runs long. Either is enough
    /// on its own — a reading that is three times its budget is wrong even if every sentence
    /// differs, and a passage that says the same sentence four times is wrong even if it is short.
    public static func isDegenerate(_ text: String, expectedCharacters: Int) -> Bool {
        if text.count > expectedCharacters * 3 { return true }
        let sentences = text
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count > 12 }          // ignore fragments; they repeat innocently
        guard sentences.count > 3 else { return false }
        var counts: [String: Int] = [:]
        for s in sentences {
            counts[s, default: 0] += 1
            if counts[s]! >= 3 { return true }
        }
        return false
    }
}
