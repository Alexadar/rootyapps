import Testing
import Foundation
@testable import BenchmarkKit

// ORACLE = EBU Tech 3341 documented expectations, validated on spec-defined signals we synthesize
// exactly (no WAV download): a −23 dBFS 1 kHz stereo tone reads −23.0 LUFS; −33 dBFS → −33.0.
@Suite("BS.1770 / EBU R128 loudness")
struct LoudnessTests {
    static let sr = 48000.0

    static func sine(dbfs: Double, hz: Double, seconds: Double) -> [Double] {
        let amp = pow(10, dbfs / 20)             // dBFS relative to full-scale sine
        let n = Int(sr * seconds)
        return (0..<n).map { amp * sin(2 * .pi * hz * Double($0) / sr) }
    }

    @Test func minus23dBFSReadsMinus23LUFS() {
        let ch = Self.sine(dbfs: -23, hz: 1000, seconds: 3)
        let lufs = Loudness.integratedLUFS(channels: [ch, ch])
        #expect(abs(lufs - (-23.0)) < 0.1, "got \(lufs) LUFS (EBU Tech 3341 Test 1 → −23.0)")
    }

    @Test func minus33dBFSReadsMinus33LUFS() {
        let ch = Self.sine(dbfs: -33, hz: 1000, seconds: 3)
        let lufs = Loudness.integratedLUFS(channels: [ch, ch])
        #expect(abs(lufs - (-33.0)) < 0.1, "got \(lufs) LUFS")
    }

    @Test func gatingRemovesSilence() {
        // 2 s of −23 dBFS tone + 2 s of silence → integrated ≈ −23 (silence below the −70 gate).
        let tone = Self.sine(dbfs: -23, hz: 1000, seconds: 2)
        let silence = [Double](repeating: 0, count: Int(Self.sr * 2))
        let ch = tone + silence
        let lufs = Loudness.integratedLUFS(channels: [ch, ch])
        // Silence is gated out (ungated this would read ~−26); residual ≈0.3 is the correct
        // contribution of the 400 ms blocks straddling the tone/silence boundary.
        #expect(abs(lufs - (-23.0)) < 0.5, "gated \(lufs) LUFS should ≈ −23 (silence removed)")
    }
}
