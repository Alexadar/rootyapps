import Foundation

/// The framework-independent half of Audio Analysis: turning what an analyser reports into the
/// quantities the calculators consume. Pure and stateless, like every other Kit here.
///
/// ## What this deliberately does NOT do
///
/// It does not listen, and it does not import MusicUnderstanding. Capture lives in the app behind
/// `#if canImport`; this is the part that can be reasoned about and tested on any SDK — which
/// matters, because the framework is absent from the released one.
///
/// ## What can honestly be asserted
///
/// Only the boundary. A 120 BPM click reads 120; a −23 LUFS tone reads −23. **Section labels and
/// pace have no ground truth and are passed through untested by design** (DESIGN_GUIDELINES §10) —
/// inventing assertions for them would test this file's opinion, not the audio.
public enum Measure {

    // MARK: - Tempo

    /// BPM from beat onsets, in seconds.
    ///
    /// Returns **nil until two beats have landed** — never 0. One beat is a timestamp, not a tempo,
    /// and a zero here would render as a real reading on a screen whose whole job is honesty. The UI
    /// shows `—— listening` for nil and hides the Send buttons entirely.
    public static func bpm(beatTimes: [Double]) -> Double? {
        guard beatTimes.count >= 2 else { return nil }
        let sorted = beatTimes.sorted()
        let intervals = zip(sorted.dropFirst(), sorted).map(-)
        let usable = intervals.filter { $0 > 0 }
        guard !usable.isEmpty else { return nil }
        // Median, not mean: one dropped or doubled onset should not drag the answer, and a performer
        // slowing over eight bars should read as the middle of what they played.
        let mid = usable.sorted()
        let period = mid.count % 2 == 1
            ? mid[mid.count / 2]
            : (mid[mid.count / 2 - 1] + mid[mid.count / 2]) / 2
        return 60 / period
    }

    /// Bars covered by `beatCount` beats in a `beatsPerBar` meter, rounded down to whole bars.
    public static func barCount(beatCount: Int, beatsPerBar: Int) -> Int? {
        guard beatCount > 0, beatsPerBar > 0 else { return nil }
        return beatCount / beatsPerBar
    }

    // MARK: - Loudness

    /// Integrated LUFS, normalised for display.
    ///
    /// A passthrough with a guard, and that is the point: Analysis **measures** loudness and
    /// `benchmark` alone **reasons** about it. No target, no delta, no verdict lives on this side of
    /// the boundary (§10) — if a function here started comparing against −14, LUFS would exist in two
    /// places and the rule would be gone.
    public static func integratedLUFS(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        return raw
    }

    /// True peak in dBFS. Values above 0 are real (inter-sample peaks) and are NOT clamped —
    /// clamping would hide exactly the clipping an engineer opened the app to find.
    public static func peakDB(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        return raw
    }

    // MARK: - Key

    /// Pitch classes as the app names them. Sharps, matching `PitchKit`'s note naming, so a key handed
    /// to `pitch` reads in the same alphabet the tool already uses.
    public static let pitchClasses = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// A display name for a key: `"F# minor"`, `"C major"`.
    public static func keyName(tonic: String?, isMinor: Bool?) -> String? {
        guard let tonic, pitchClasses.contains(tonic) else { return nil }
        guard let isMinor else { return tonic }
        return tonic + (isMinor ? " minor" : " major")
    }

    /// The tonic as a MIDI note in a chosen octave, which is what `pitch` actually consumes.
    /// C4 = 60, so octave 4 puts the tonic in the middle of the keyboard.
    public static func tonicMIDI(tonic: String?, octave: Int = 4) -> Double? {
        guard let tonic, let index = pitchClasses.firstIndex(of: tonic) else { return nil }
        return Double((octave + 1) * 12 + index)
    }
}
