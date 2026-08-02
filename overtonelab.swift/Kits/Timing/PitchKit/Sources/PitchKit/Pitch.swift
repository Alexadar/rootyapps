import Foundation

/// Note ↔ frequency ↔ wavelength (12-TET, A4 = 440 Hz / ISO 16). Pure, stateless.
public enum Pitch {
    public static let a4 = 440.0
    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// MIDI note number → frequency. MIDI 69 = A4.
    public static func noteToHz(midi n: Double, a4: Double = a4) -> Double { a4 * pow(2, (n - 69) / 12) }
    /// Frequency → (fractional) MIDI note number.
    public static func hzToNote(_ f: Double, a4: Double = a4) -> Double { f > 0 ? 69 + 12 * log2(f / a4) : 0 }
    /// Wavelength in air (m) for a frequency.
    public static func wavelengthM(hz f: Double, speed c: Double = 343) -> Double { f > 0 ? c / f : 0 }
    /// Interval between two frequencies in cents (1200·log₂(f₂/f₁)).
    public static func centsBetween(_ f1: Double, _ f2: Double) -> Double { (f1 > 0 && f2 > 0) ? 1200 * log2(f2 / f1) : 0 }

    /// Scientific note name for a MIDI number (C4 = middle C = MIDI 60).
    public static func noteName(midi n: Int) -> String {
        let idx = ((n % 12) + 12) % 12
        return "\(names[idx])\(n / 12 - 1)"
    }
}

/// Harmonic series relative to a fundamental.
public enum Harmonics {
    public static func harmonicHz(fundamental f: Double, n: Int) -> Double { f * Double(n) }
    /// Cents deviation of the nth harmonic from the nearest 12-TET pitch.
    public static func centsFromET(n: Int) -> Double {
        let c = 1200 * log2(Double(n))
        return c - 100 * (c / 100).rounded()
    }
}

/// Beat frequency between two close tones.
public enum Beats {
    public static func beatHz(_ f1: Double, _ f2: Double) -> Double { abs(f1 - f2) }
}

/// Doppler frequency shift.
public enum Doppler {
    /// Observed frequency. Sign: vSource > 0 = source moving *toward* the observer,
    /// vObserver > 0 = observer moving *toward* the source. f′ = f·(c + vObs)/(c − vSrc).
    public static func observedHz(source f: Double, speed c: Double = 343,
                                  vSource: Double = 0, vObserver: Double = 0) -> Double {
        let denom = c - vSource
        return denom != 0 ? f * (c + vObserver) / denom : 0
    }
}
