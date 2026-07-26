import Testing
import Foundation
@testable import BiquadKit

// Oracle = RBJ "Audio EQ Cookbook" (https://webaudio.github.io/Audio-EQ-Cookbook/) — the canonical
// biquad coefficient reference. We assert its published structural identities and response anchors.
@Suite("Biquad — RBJ cookbook")
struct BiquadTests {
    let fs = 48000.0

    // Butterworth low-pass (Q = 1/√2) is exactly −3.0103 dB at the design frequency f0.
    @Test func lowpassMinus3dBAtF0() {
        let c = Biquad.design(.lowpass, fs: fs, f0: 1000, q: 0.7071067811865476)
        #expect(abs(Biquad.magnitudeDB(c, hz: 1000, fs: fs) - (-3.0103)) < 0.02)
    }

    // Low-pass passes DC unchanged (0 dB) and its numerator is symmetric with b1 = 2·b0.
    @Test func lowpassDCAndSymmetry() {
        let c = Biquad.design(.lowpass, fs: fs, f0: 1000, q: 0.7071)
        #expect(abs(Biquad.magnitudeDB(c, hz: 0, fs: fs) - 0) < 1e-9)   // DC gain = 1
        #expect(abs(c.b0 - c.b2) < 1e-15)                                // symmetric
        #expect(abs(c.b1 - 2 * c.b0) < 1e-15)                            // b1 = 1−cos = 2·(1−cos)/2
    }

    // High-pass passes Nyquist unchanged (0 dB).
    @Test func highpassAtNyquist() {
        let c = Biquad.design(.highpass, fs: fs, f0: 1000, q: 0.7071)
        #expect(abs(Biquad.magnitudeDB(c, hz: fs / 2, fs: fs) - 0) < 1e-9)
    }

    // Peaking EQ has EXACTLY its set gain at f0 (cookbook identity), for any gain/Q.
    @Test func peakingExactGainAtF0() {
        for g in [-12.0, -6, 3, 9, 18] {
            let c = Biquad.design(.peaking, fs: fs, f0: 2000, q: 1.0, gainDB: g)
            #expect(abs(Biquad.magnitudeDB(c, hz: 2000, fs: fs) - g) < 1e-6)
        }
    }

    // Notch drives f0 to (near) −∞, and its denominator coefficients mirror the numerator's a1.
    @Test func notchNullsF0() {
        let c = Biquad.design(.notch, fs: fs, f0: 1000, q: 4)
        #expect(Biquad.magnitudeDB(c, hz: 1000, fs: fs) < -80)
        #expect(abs(c.b1 - c.a1) < 1e-15)   // both = −2cosω0 / a0
    }

    // All-pass is unity magnitude (0 dB) at every frequency.
    @Test func allpassIsUnity() {
        let c = Biquad.design(.allpass, fs: fs, f0: 1200, q: 2)
        for f in [50.0, 500, 1200, 5000, 20000] {
            #expect(abs(Biquad.magnitudeDB(c, hz: f, fs: fs)) < 1e-9)
        }
    }

    // Shelves reach exactly the set gain at their far band edge (low-shelf at DC, high-shelf at Nyquist).
    @Test func shelfEndpointGains() {
        let low = Biquad.design(.lowShelf, fs: fs, f0: 300, q: 0.7071, gainDB: 6)
        #expect(abs(Biquad.magnitudeDB(low, hz: 0, fs: fs) - 6) < 1e-6)
        let high = Biquad.design(.highShelf, fs: fs, f0: 4000, q: 0.7071, gainDB: -9)
        #expect(abs(Biquad.magnitudeDB(high, hz: fs / 2, fs: fs) - (-9)) < 1e-6)
    }
}
