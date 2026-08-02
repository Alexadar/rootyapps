import Foundation

/// Uncompressed-audio size, sample-rate & quantization facts. Pure, stateless.
public enum FileInfo {
    /// PCM audio-data size in bytes (header excluded): sampleRate·bitDepth·channels·seconds / 8.
    public static func sizeBytes(sampleRate sr: Double, bitDepth bits: Double, channels ch: Double, seconds s: Double) -> Double {
        sr * bits * ch * s / 8
    }
    public static func sizeMB(sampleRate sr: Double, bitDepth bits: Double, channels ch: Double, seconds s: Double) -> Double {
        sizeBytes(sampleRate: sr, bitDepth: bits, channels: ch, seconds: s) / 1_000_000
    }
    /// Nyquist frequency = sampleRate / 2.
    public static func nyquistHz(sampleRate sr: Double) -> Double { sr / 2 }
    /// Theoretical dynamic range (dB) of an N-bit PCM system: 6.0206·N + 1.7609 (full-scale-sine SNR).
    public static func dynamicRangeDB(bitDepth n: Double) -> Double { 6.0206 * n + 1.7609 }
}
