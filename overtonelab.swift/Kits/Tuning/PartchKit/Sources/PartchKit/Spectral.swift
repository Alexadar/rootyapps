import Foundation

/// Spectral analysis + just-intonation ratio identification. Pure, stateless.
public enum Spectral {
    /// Magnitude spectrum (first n/2 bins) of real samples.
    public static func magnitude(_ samples: [Double]) -> [Double] {
        let spec = FFT.transform(samples.map { Complex($0, 0) })
        return (0..<samples.count / 2).map { spec[$0].magnitude }
    }
    public static func binToHz(_ bin: Int, sampleRate: Double, n: Int) -> Double {
        Double(bin) * sampleRate / Double(n)
    }
    /// The `count` strongest spectral peaks (local maxima), as bin indices, strongest first.
    public static func peakBins(_ mag: [Double], count: Int) -> [Int] {
        var peaks: [Int] = []
        for i in 1..<(mag.count - 1) where mag[i] > mag[i - 1] && mag[i] >= mag[i + 1] {
            peaks.append(i)
        }
        return Array(peaks.sorted { mag[$0] > mag[$1] }.prefix(count))
    }

    /// Cents of a frequency ratio.
    public static func cents(_ ratio: Double) -> Double { 1200 * log2(ratio) }

    /// Nearest just-intonation ratio (n/d, both ≤ oddLimit, reduced) to a target interval in cents.
    public static func nearestJustRatio(cents target: Double, oddLimit: Int = 15) -> (num: Int, den: Int, cents: Double) {
        var best = (num: 1, den: 1, cents: 0.0, err: Double.greatestFiniteMagnitude)
        for n in 1...oddLimit {
            for d in 1...oddLimit {
                if gcd(n, d) != 1 { continue }
                let c = cents(Double(n) / Double(d))
                let err = abs(c - target)
                if err < best.err { best = (n, d, c, err) }
            }
        }
        return (best.num, best.den, best.cents)
    }

    /// Tenney harmonic distance log2(n·d) — a consonance proxy (lower = more consonant).
    public static func tenneyHeight(num n: Int, den d: Int) -> Double { log2(Double(n * d)) }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
