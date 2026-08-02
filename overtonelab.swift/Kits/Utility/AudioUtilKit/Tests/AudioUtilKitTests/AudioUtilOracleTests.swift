import Testing
import Foundation
@testable import AudioUtilKit

/// Oracles (external, cited):
///  • dB definitions: voltage 20·log₁₀, power 10·log₁₀ → ×2 = +6.02 / +3.01 dB.
///  • Reference levels: 0 dBu = 0.7746 V (√(1 mW·600 Ω)), 0 dBV = 1 V (AES).
///  • PCM size = SR·bits·ch·time/8; quantization SNR = 6.02·N + 1.76 dB (Kester, ADI MT-001).
///  • Equal-power pan law: centre = −3.01 dB.
@Suite struct AudioUtilOracle {

    @Test func decibels() {
        #expect(abs(Levels.voltageDB(ratio: 2) - 6.0206) < 1e-3)     // ×2 voltage
        #expect(abs(Levels.powerDB(ratio: 2) - 3.0103) < 1e-3)       // ×2 power
        #expect(abs(Levels.voltageRatio(db: 6.0206) - 2) < 1e-3)     // round-trip
        #expect(abs(Levels.powerRatio(db: 3.0103) - 2) < 1e-3)
    }

    @Test func referenceLevels() {
        #expect(abs(Levels.dBuToVolts(0) - 0.7746) < 1e-4)           // 0 dBu
        #expect(abs(Levels.dBVToVolts(0) - 1) < 1e-9)                // 0 dBV
        #expect(abs(Levels.voltsToDBu(1) - 2.218) < 1e-3)            // 1 V ≈ +2.22 dBu
        #expect(abs(Levels.voltsToDBV(1)) < 1e-9)
    }

    @Test func fileInfo() {
        // 44.1 kHz / 16-bit / stereo / 60 s = 10,584,000 bytes.
        #expect(abs(FileInfo.sizeBytes(sampleRate: 44100, bitDepth: 16, channels: 2, seconds: 60) - 10_584_000) < 1e-3)
        #expect(abs(FileInfo.nyquistHz(sampleRate: 48000) - 24000) < 1e-9)
        #expect(abs(FileInfo.dynamicRangeDB(bitDepth: 16) - 98.09) < 0.01)   // 16-bit
        #expect(abs(FileInfo.dynamicRangeDB(bitDepth: 24) - 146.26) < 0.01)  // 24-bit
    }

    @Test func panLaw() {
        // Equal-power centre gain = 1/√2 → −3.01 dB.
        let g = Pan.gains(position: 0, law: .equalPower3dB)
        #expect(abs(g.left - 0.70711) < 1e-4 && abs(g.right - 0.70711) < 1e-4)
        #expect(abs(Pan.centerDropDB(law: .equalPower3dB) - (-3.0103)) < 1e-3)
        #expect(abs(Pan.centerDropDB(law: .linear6dB) - (-6.0206)) < 1e-3)
        // Hard left → all in left channel.
        let l = Pan.gains(position: -1, law: .equalPower3dB)
        #expect(abs(l.left - 1) < 1e-9 && l.right < 1e-9)
    }

    @Test func guards() {
        #expect(Levels.voltageDB(ratio: 0) == -.infinity)
    }
}
