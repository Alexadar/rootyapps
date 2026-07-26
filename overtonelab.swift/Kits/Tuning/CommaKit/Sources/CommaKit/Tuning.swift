import Foundation

/// Microtonal tuning math: cents, equal divisions, historical temperaments, comma arithmetic,
/// and a parser for the Scala (.scl) scale-file format. Pure, stateless.
public enum Tuning {

    /// Interval size in cents for a frequency ratio.  1200·log2(ratio).
    public static func cents(ratio: Double) -> Double { 1200 * log2(ratio) }

    /// The N degrees (above the tonic) of N-tone equal temperament, in cents.
    public static func edo(_ n: Int) -> [Double] {
        precondition(n > 0)
        return (1...n).map { Double($0) * 1200 / Double(n) }
    }

    // MARK: Named intervals & commas (published values)

    /// Just perfect fifth 3:2.
    public static var justFifthCents: Double { cents(ratio: 3.0 / 2.0) }        // 701.955
    /// Quarter-comma meantone fifth: ratio 5^(1/4).
    public static var quarterCommaMeantoneFifthCents: Double { cents(ratio: pow(5.0, 0.25)) } // 696.578
    /// Syntonic comma 81:80.
    public static var syntonicCommaCents: Double { cents(ratio: 81.0 / 80.0) }  // 21.506
    /// Pythagorean comma (3/2)^12 / 2^7.
    public static var pythagoreanCommaCents: Double { cents(ratio: pow(1.5, 12) / pow(2.0, 7)) } // 23.460

    // MARK: Scala (.scl) parsing

    /// Parse a Scala scale file into its pitch list (cents above the 1/1). Returns nil if malformed.
    /// Format: `!`-comment lines ignored; first data line = description; second = note count N;
    /// then N pitches, each either cents (contains `.`) or a ratio (`a/b` or integer `n` = n/1).
    public static func parseSCL(_ text: String) -> [Double]? {
        var data: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("!") { continue }
            data.append(line)
        }
        guard data.count >= 2 else { return nil }
        // data[0] = description (may be blank); data[1] = count
        let countTok = data[1].split(separator: " ").first.map(String.init) ?? data[1]
        guard let count = Int(countTok), count >= 0 else { return nil }

        var pitches: [Double] = []
        var i = 2
        while i < data.count && pitches.count < count {
            let line = data[i]; i += 1
            if line.isEmpty { continue }
            let tok = String(line.split(whereSeparator: { $0.isWhitespace }).first ?? "")
            if tok.isEmpty { continue }
            if tok.contains(".") {
                guard let c = Double(tok) else { return nil }
                pitches.append(c)
            } else if tok.contains("/") {
                let p = tok.split(separator: "/")
                guard p.count == 2, let n = Double(p[0]), let d = Double(p[1]), d != 0, n / d > 0 else { return nil }
                pitches.append(cents(ratio: n / d))
            } else {
                guard let n = Double(tok), n > 0 else { return nil }
                pitches.append(cents(ratio: n))
            }
        }
        return pitches.count == count ? pitches : nil
    }
}
