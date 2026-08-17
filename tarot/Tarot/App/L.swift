import Foundation

/// The view-boundary localizer (ephemeris pattern): TarotKit deliberately returns English —
/// its display strings double as the FM prompt vocabulary (the guardrail label table was
/// measured against English names) and as stable identifiers — and `L.loc` turns that
/// English into a catalog lookup exactly where it meets the user.
enum L {
    static func loc(_ english: String) -> String {
        NSLocalizedString(english, comment: "")
    }
}
