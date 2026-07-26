import Foundation

/// Musical tempo & note-timing math. Pure, stateless.
public enum Tempo {
    /// Duration of one beat (a quarter note) in milliseconds.
    public static func beatMs(bpm: Double) -> Double { bpm > 0 ? 60000 / bpm : 0 }

    /// Note-value duration in ms. `division` is the note denominator (1 = whole, 2 = half,
    /// 4 = quarter, 8 = eighth, 16 = sixteenth…). Dotted = ×1.5, triplet = ×2⁄3.
    public static func noteMs(bpm: Double, division: Double, dotted: Bool = false, triplet: Bool = false) -> Double {
        guard bpm > 0, division > 0 else { return 0 }
        var ms = (60000 / bpm) * (4 / division)   // quarter note = one beat
        if dotted { ms *= 1.5 }
        if triplet { ms *= 2.0 / 3.0 }
        return ms
    }

    /// Bar duration in ms for a `beats`/`beatUnit` time signature (e.g. 4/4, 6/8).
    public static func barMs(bpm: Double, beats: Int, beatUnit: Double) -> Double {
        guard bpm > 0, beatUnit > 0 else { return 0 }
        return (60000 / bpm) * (4 / beatUnit) * Double(beats)
    }

    /// Tempo (BPM) from a measured beat duration in ms.
    public static func bpm(beatMs: Double) -> Double { beatMs > 0 ? 60000 / beatMs : 0 }

    /// Milliseconds ↔ samples at a sample rate.
    public static func msToSamples(ms: Double, sampleRate: Double) -> Double { ms / 1000 * sampleRate }
    public static func samplesToMs(samples: Double, sampleRate: Double) -> Double {
        sampleRate > 0 ? samples / sampleRate * 1000 : 0
    }

    /// Varispeed: semitone shift for a playback-rate ratio (newRate / oldRate). +12 st = 2× speed.
    public static func varispeedSemitones(rateRatio r: Double) -> Double { r > 0 ? 12 * log2(r) : 0 }
    /// Playback-rate ratio for a semitone shift.
    public static func rateRatio(semitones s: Double) -> Double { pow(2, s / 12) }
}
