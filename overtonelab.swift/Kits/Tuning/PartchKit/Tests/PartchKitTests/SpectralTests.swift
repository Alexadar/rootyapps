import Testing
import Foundation
@testable import PartchKit

// ORACLE = self-generated ground truth: synthesize a signal of KNOWN frequency content, then
// require the analyzer to recover it. The expected values come from the synthesis, exactly.
@Suite("Spectral analysis vs synthesized ground truth")
struct SpectralTests {
    @Test func recoversKnownPartials() {
        let sr = 8000.0, n = 4096
        // ground truth: 440 Hz (strong) + 880 Hz (half amplitude)
        let samples = (0..<n).map { i -> Double in
            let t = Double(i) / sr
            return sin(2 * .pi * 440 * t) + 0.5 * sin(2 * .pi * 880 * t)
        }
        let mag = Spectral.magnitude(samples)
        let peaks = Spectral.peakBins(mag, count: 2).map { Spectral.binToHz($0, sampleRate: sr, n: n) }.sorted()
        let binWidth = sr / Double(n)                       // ≈1.95 Hz
        #expect(peaks.count == 2)
        #expect(abs(peaks[0] - 440) < 2 * binWidth)
        #expect(abs(peaks[1] - 880) < 2 * binWidth)
    }

    @Test func fftImpulseIsFlat() {
        // FFT of a unit impulse is flat magnitude 1 across all bins (Parseval sanity).
        var x = [Complex](repeating: Complex(0, 0), count: 8); x[0] = Complex(1, 0)
        let spec = FFT.transform(x)
        for c in spec { #expect(abs(c.magnitude - 1) < 1e-12) }
    }
}

// IDENTITY: just-intonation ratio identification.
@Suite("Just-intonation ratios")
struct RatioTests {
    @Test func nearestRatios() {
        // A tempered fifth (700¢) is nearest 3/2 (701.955¢); a major third (400¢) nearest 5/4 (386.31¢).
        let fifth = Spectral.nearestJustRatio(cents: 700)
        #expect(fifth.num == 3 && fifth.den == 2)
        let third = Spectral.nearestJustRatio(cents: 400)
        #expect(third.num == 5 && third.den == 4)
    }
    @Test func consonanceOrdering() {
        // 3/2 is more consonant (lower Tenney height) than 7/5.
        #expect(Spectral.tenneyHeight(num: 3, den: 2) < Spectral.tenneyHeight(num: 7, den: 5))
    }
}
