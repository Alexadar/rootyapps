import Foundation

/// Turning an estimate into a sentence, with hysteresis.
///
/// Used by the Live Activity and the completion notification. `GeneratingView` does its own
/// phrasing from the raw `TimeInterval` and is left alone.
///
/// The hysteresis is the point. A rolling estimate genuinely wobbles by a few percent every step,
/// and a countdown that reads 4 → 5 → 4 → 5 tells the user the app does not know what it is doing
/// — even when the underlying number is perfectly reasonable. The displayed phrase only changes
/// when the estimate has moved enough to mean something.
public enum RemainingPhrase {

    /// A new estimate must differ from the one behind the current phrase by at least this much
    /// before the words change.
    public static let hysteresis = 0.15

    public struct State: Sendable, Equatable, Codable, Hashable {
        public var text: String?
        /// The estimate the current text was computed from.
        public var anchorSeconds: TimeInterval?
        public init(text: String? = nil, anchorSeconds: TimeInterval? = nil) {
            self.text = text
            self.anchorSeconds = anchorSeconds
        }
    }

    /// - Returns: the phrase to show, and the state to carry into the next call.
    public static func update(_ state: State, seconds: TimeInterval?) -> State {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            // No measurement yet. Say nothing rather than invent a number.
            return State(text: nil, anchorSeconds: nil)
        }

        if let anchor = state.anchorSeconds, state.text != nil {
            let denominator = max(anchor, 1)
            let change = abs(seconds - anchor) / denominator
            let wouldRead = text(for: seconds)
            // Two ways to keep the old words: the estimate barely moved, or it moved but the
            // rounded sentence is identical anyway.
            if change < hysteresis || wouldRead == state.text {
                return state
            }
        }

        return State(text: text(for: seconds), anchorSeconds: seconds)
    }

    /// The unhysteretic phrasing.
    public static func text(for seconds: TimeInterval) -> String {
        if seconds < 45 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes <= 1 { return "about a minute left" }
        if minutes < 60 { return "about \(minutes) min left" }
        let hours = minutes / 60
        let leftover = minutes % 60
        if leftover == 0 { return hours == 1 ? "about an hour left" : "about \(hours) hours left" }
        return "about \(hours) h \(leftover) min left"
    }
}
