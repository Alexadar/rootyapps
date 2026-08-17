import Foundation

/// The download card's numbers.
///
/// The design bundle fixes the exact strings: "1.1 of 2.6 GB", "Wi‑Fi · 4.6 MB/s", "Step 9 of 28".
/// Getting them here rather than inline in a view means they are the same on every screen and can
/// be checked at their boundaries, which is where byte formatting always goes wrong.
///
/// **Units are decimal (1 GB = 1000 MB), not binary.** Apple reports download sizes on the App Store
/// this way, and the model's stated 2.6 GB is a decimal figure; showing 2.4 GiB beside a store
/// listing that says 2.6 GB would read as a bug.
public enum ByteText {

    private static let kilo = 1000.0

    /// "2.6 GB" · "986 MB" · "0 KB". One decimal place from MB upward, none below — a wallpaper app
    /// showing "1.048576 MB" is noise, and a progress line that jitters in the third decimal is worse.
    public static func size(_ bytes: Int64) -> String {
        let magnitude = Double(max(0, bytes))
        switch magnitude {
        case ..<kilo:
            return "\(Int(magnitude)) B"
        case ..<(kilo * kilo):
            return "\(Int((magnitude / kilo).rounded())) KB"
        case ..<(kilo * kilo * kilo):
            return decimal(magnitude / (kilo * kilo), unit: "MB")
        default:
            return decimal(magnitude / (kilo * kilo * kilo), unit: "GB")
        }
    }

    /// "1.1 of 2.6 GB" — the unit is stated once, on the total, and both numbers are expressed in
    /// it. Writing "1.1 GB of 2.6 GB" is redundant; worse, formatting them independently can print
    /// "999.6 MB of 1.0 GB", where the two halves appear to be in different currencies.
    public static func progress(completed: Int64, total: Int64) -> String {
        guard total > 0 else { return size(completed) }
        let totalMagnitude = Double(total)
        let (divisor, unit): (Double, String) = totalMagnitude >= kilo * kilo * kilo
            ? (kilo * kilo * kilo, "GB")
            : (kilo * kilo, "MB")
        let done = Double(min(max(0, completed), total)) / divisor
        let whole = totalMagnitude / divisor
        return "\(decimal(done)) of \(decimal(whole)) \(unit)"
    }

    /// "4.6 MB/s". `nil` when there is nothing honest to say yet — a rate needs two samples, and
    /// inventing one for the first frame is exactly the kind of small lie the brief rules out.
    public static func rate(bytesPerSecond: Double?) -> String? {
        guard let rate = bytesPerSecond, rate > 0, rate.isFinite else { return nil }
        switch rate {
        case ..<kilo:
            return "\(Int(rate)) B/s"
        case ..<(kilo * kilo):
            return "\(Int((rate / kilo).rounded())) KB/s"
        case ..<(kilo * kilo * kilo):
            return decimal(rate / (kilo * kilo), unit: "MB/s")
        default:
            return decimal(rate / (kilo * kilo * kilo), unit: "GB/s")
        }
    }

    /// "About four minutes on this connection." — words, not a countdown.
    ///
    /// A digit-precise ETA on a variable connection is a promise the app cannot keep, and watching
    /// it jump from 2:14 to 9:40 is the thing that makes a download feel broken. `nil` while the
    /// rate is still unknown; the caller says something honest instead.
    public static func remainingPhrase(bytesRemaining: Int64, bytesPerSecond: Double?) -> String? {
        guard let rate = bytesPerSecond, rate > 0, rate.isFinite, bytesRemaining > 0 else { return nil }
        let seconds = Double(bytesRemaining) / rate
        switch seconds {
        case ..<45:               return "Less than a minute"
        case ..<90:               return "About a minute"
        case ..<(60 * 60):        return "About \(spelled(Int((seconds / 60).rounded()))) minutes"
        case ..<(60 * 60 * 2):    return "About an hour"
        default:                  return "Over an hour"
        }
    }

    /// "Step 9 of 28". Callers apply tabular numerals so the label does not shimmy as it counts.
    public static func step(_ step: Int, of total: Int) -> String { "Step \(step) of \(total)" }

    /// "12 wallpapers" · "1 wallpaper" · "No wallpapers yet".
    public static func wallpaperCount(_ count: Int) -> String {
        switch count {
        case 0:  return "No wallpapers yet"
        case 1:  return "1 wallpaper"
        default: return "\(count) wallpapers"
        }
    }

    // MARK: -

    private static func decimal(_ value: Double, unit: String? = nil) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = String(format: "%.1f", rounded)
        return unit.map { "\(text) \($0)" } ?? text
    }

    /// Numbers up to twelve read better as words in a sentence; beyond that digits win.
    private static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six",
                     "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return n >= 0 && n < words.count ? words[n] : "\(n)"
    }
}
