import Foundation

/// Delay & propagation timing. Pure, stateless.
public enum Delay {
    public static let speedOfSound = 343.0   // m/s, 20 °C dry air

    /// Delay time (ms) synced to a note value at tempo.
    public static func noteDelayMs(bpm: Double, division: Double, dotted: Bool = false, triplet: Bool = false) -> Double {
        Tempo.noteMs(bpm: bpm, division: division, dotted: dotted, triplet: triplet)
    }

    /// LFO/modulation rate (Hz) equivalent to a delay time.
    public static func rateHz(ms: Double) -> Double { ms > 0 ? 1000 / ms : 0 }

    /// Acoustic propagation delay (ms) over a distance — e.g. loudspeaker time-alignment.
    public static func distanceMs(meters d: Double, speed c: Double = speedOfSound) -> Double {
        c > 0 ? d / c * 1000 : 0
    }
    /// Distance (m) covered by a given delay.
    public static func metersForMs(_ ms: Double, speed c: Double = speedOfSound) -> Double { ms / 1000 * c }

    /// First comb-filter null frequency when a signal sums with a delayed copy: f = 1 / (2·t).
    public static func combFirstNullHz(delayMs ms: Double) -> Double { ms > 0 ? 1000 / (2 * ms) : 0 }

    /// Haas fusion window: below ~35 ms a delayed copy fuses into one perceived source.
    public static let haasFusionMaxMs = 35.0
}
