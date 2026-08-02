import Foundation

/// Constant-power & related pan laws. Pure, stateless.
public enum Pan {
    public enum Law: Sendable, CaseIterable { case equalPower3dB, linear6dB, compromise45dB }

    /// (left, right) linear gains for a pan position in [−1, +1] (0 = centre).
    public static func gains(position p: Double, law: Law = .equalPower3dB) -> (left: Double, right: Double) {
        let x = max(-1, min(1, p))
        let angle = (x + 1) / 2 * (.pi / 2)      // 0 … π/2
        switch law {
        case .equalPower3dB: return (cos(angle), sin(angle))
        case .linear6dB:     return ((1 - x) / 2, (1 + x) / 2)
        case .compromise45dB:
            let ep = (cos(angle), sin(angle)), lin = ((1 - x) / 2, (1 + x) / 2)
            return ((ep.0 * lin.0).squareRoot(), (ep.1 * lin.1).squareRoot())
        }
    }

    /// Gain drop (dB) applied to each channel at centre for a given law.
    public static func centerDropDB(law: Law) -> Double {
        let g = gains(position: 0, law: law)
        return 20 * log10(g.left)
    }
}
