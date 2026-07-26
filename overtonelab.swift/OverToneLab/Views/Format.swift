import Foundation

/// Number formatting for every displayed result.
///
/// These were `String(format: "%.2f")`, which always prints a dot. `NumberField` parses with
/// `.number`, which follows the locale — so a German user typed `0,17` and read back `0.17`.
/// Now both sides follow `Fmt.locale`, which `LanguageStore` sets from the chosen language (or
/// the device, when that is "System"). Display and entry can no longer disagree.
///
/// `locale` is a static rather than a parameter because that keeps all 141 call sites unchanged:
/// switching language re-renders the whole tree (the root `.environment(\.locale,)` changes), so
/// the new value is picked up during that rebuild.
enum Fmt {
    /// Kept in step with the app language by `LanguageStore`.
    nonisolated(unsafe) static var locale: Locale = .autoupdatingCurrent

    private static func decimal(_ x: Double, _ places: Int, signed: Bool = false) -> String {
        x.formatted(
            FloatingPointFormatStyle<Double>()
                .precision(.fractionLength(places))
                .sign(strategy: signed ? .always() : .automatic)
                // Grouping is OFF on purpose: the old String(format:) had none, and turning it on
                // would silently rewrite every displayed value (108000 fr → 108,000 fr). Only the
                // decimal separator is meant to follow the language.
                .grouping(.never)
                // String(format:) rounds half AWAY FROM ZERO; FloatingPointFormatStyle defaults to
                // half-to-even. Sabine's RT60 (0.161·200/40 = 0.805) is the case that exposed it:
                // 0.81 before, 0.80 after. Restore the old rule — these are oracle-checked numbers
                // and the display must not quietly disagree with the test corpus.
                .rounded(rule: .toNearestOrAwayFromZero)
                .locale(locale)
        )
    }

    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    static func timeOrDash(_ d: Date?) -> String { d.map { time.string(from: $0) } ?? "—" }

    static func f(_ x: Double, _ places: Int = 2) -> String { decimal(x, places) }
    static func signed(_ x: Double, _ places: Int = 2) -> String { decimal(x, places, signed: true) }
    static func deg(_ x: Double, _ p: Int = 2) -> String { f(x, p) + "°" }
    /// Percent sign placement and spacing are locale-dependent (fr puts a space before it), so
    /// this goes through the percent style instead of appending "%".
    static func pct(_ x: Double) -> String {
        x.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
    static func secs(_ x: Double) -> String { x >= 10 ? f(x, 1) + " s" : f(x, 2) + " s" }
    static func hours(_ x: Double) -> String { f(x, 1) + " h" }
}
