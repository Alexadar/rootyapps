import Foundation

public struct Vowel: Sendable, Identifiable, Equatable {
    public let ipa: String, keyword: String, f1: Double, f2: Double
    public var id: String { ipa }
    public init(ipa: String, keyword: String, f1: Double, f2: Double) {
        self.ipa = ipa; self.keyword = keyword; self.f1 = f1; self.f2 = f2
    }
}

/// Vocal-tract formant resonances. Pure, stateless.
/// The tract is modeled as a uniform tube closed at the glottis, open at the lips
/// (a quarter-wave resonator), so formants are the odd-harmonic series (2n−1)·c/(4L).
public enum Formants {
    /// Warm, humid vocal-tract air ≈ 350 m/s.
    public static let vocalTractSpeed = 350.0

    /// nth formant (Hz) for a tract length L (m).
    public static func formantHz(tractLengthM L: Double, n: Int, speed c: Double = vocalTractSpeed) -> Double {
        L > 0 ? Double(2 * n - 1) * c / (4 * L) : 0
    }

    /// Formant frequency when the tract length changes (child/female/male): F′ = F·L/L′.
    public static func scaled(_ f: Double, fromLengthM L1: Double, toLengthM L2: Double) -> Double {
        L2 > 0 ? f * L1 / L2 : 0
    }

    /// Mean adult-male vowel formants (F1/F2, Hz) — Peterson & Barney (1952), JASA 24(2).
    public static let vowels: [Vowel] = [
        Vowel(ipa: "i", keyword: "heed",   f1: 270, f2: 2290),
        Vowel(ipa: "ɪ", keyword: "hid",    f1: 390, f2: 1990),
        Vowel(ipa: "ɛ", keyword: "head",   f1: 530, f2: 1840),
        Vowel(ipa: "æ", keyword: "had",    f1: 660, f2: 1720),
        Vowel(ipa: "ɑ", keyword: "hod",    f1: 730, f2: 1090),
        Vowel(ipa: "ɔ", keyword: "hawed",  f1: 570, f2: 840),
        Vowel(ipa: "ʊ", keyword: "hood",   f1: 440, f2: 1020),
        Vowel(ipa: "u", keyword: "who'd",  f1: 300, f2: 870),
        Vowel(ipa: "ʌ", keyword: "hud",    f1: 640, f2: 1190),
        Vowel(ipa: "ɝ", keyword: "heard",  f1: 490, f2: 1350),
    ]
}
