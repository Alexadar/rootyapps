import Foundation

/// ITU-R BS.1770 / EBU R128 loudness: K-weighting + gated integrated LUFS. Pure, stateless.
/// K-weighting biquad coefficients are the standard's reference values at 48 kHz.
public enum Loudness {

    struct Biquad {
        let b0, b1, b2, a1, a2: Double
        func run(_ x: [Double]) -> [Double] {
            var y = [Double](repeating: 0, count: x.count)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in 0..<x.count {
                let out = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                y[i] = out; x2 = x1; x1 = x[i]; y2 = y1; y1 = out
            }
            return y
        }
    }
    // Stage 1: high-shelf pre-filter (48 kHz). Stage 2: RLB high-pass (48 kHz).
    static let stage1 = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                               a1: -1.69065929318241, a2: 0.73248077421585)
    static let stage2 = Biquad(b0: 1.0, b1: -2.0, b2: 1.0,
                               a1: -1.99004745483398, a2: 0.99007225036621)

    static func kWeight(_ x: [Double]) -> [Double] { stage2.run(stage1.run(x)) }

    /// Gated integrated loudness (LUFS) of interleaved-by-channel audio at 48 kHz.
    /// `channels` = array of per-channel sample arrays (L, R, …); each channel weight G = 1.0.
    public static func integratedLUFS(channels: [[Double]], sampleRate: Double = 48000) -> Double {
        let weighted = channels.map { kWeight($0) }
        let blockLen = Int(0.4 * sampleRate)     // 400 ms
        let step = Int(0.1 * sampleRate)         // 100 ms (75% overlap)
        let n = weighted.first?.count ?? 0
        guard n >= blockLen else { return -.infinity }

        // per-block mean-square sum over channels (z_j) and its block loudness
        var zs: [Double] = []
        var i = 0
        while i + blockLen <= n {
            var z = 0.0
            for ch in weighted {
                var s = 0.0
                for k in i..<(i + blockLen) { s += ch[k] * ch[k] }
                z += s / Double(blockLen)        // G_c = 1
            }
            zs.append(z)
            i += step
        }
        let loud = { (z: Double) in -0.691 + 10 * log10(z) }

        // absolute gate at −70 LUFS
        let absGated = zs.filter { loud($0) >= -70 }
        guard !absGated.isEmpty else { return -.infinity }
        // relative gate: 10 LU below the mean of the absolute-gated blocks
        let meanAbs = absGated.reduce(0, +) / Double(absGated.count)
        let relThreshold = loud(meanAbs) - 10
        let gated = zs.filter { loud($0) >= -70 && loud($0) >= relThreshold }
        guard !gated.isEmpty else { return -.infinity }
        let meanGated = gated.reduce(0, +) / Double(gated.count)
        return loud(meanGated)
    }
}
