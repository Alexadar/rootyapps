import SwiftUI
import EphemerisKit

/// Translated display text for an `AstroEvent`.
///
/// `AstroEvent.label()` can't be localized directly: the Kit builds its ~1,300 legend strings
/// combinatorially ("Mars enters Aries", "Venus square Saturn"), so no individual label is ever a
/// catalog key — passing one to `L.loc` returns the English sentence unchanged. That English text
/// is still the CSV export contract, so it stays as it is.
///
/// Instead this rebuilds the sentence from the event's structured fields against a handful of
/// *pattern* keys, filling them with body/sign/aspect names the catalog already carries. The
/// patterns use positional specifiers (`%1$@`, `%2$@`) so translators can reorder them — several
/// languages put the sign before the verb, and a fixed order would force stilted phrasing.
enum EventLabel {

    static func text(for e: AstroEvent) -> Text {
        let body = Text(L.loc(e.bodyA.name))
        let sign = Text(L.loc(e.sign?.name ?? ""))

        switch e.kind {
        case .signIngress:
            return Text("\(body) enters \(sign)")
        case .newMoon:
            return Text("New Moon in \(sign)")
        case .fullMoon:
            return Text("Full Moon in \(sign)")
        case .stationRetrograde:
            return Text("\(body) stations retrograde")
        case .stationDirect:
            return Text("\(body) stations direct")
        case .inferiorConjunction:
            return Text("\(body) inferior conjunction")
        case .superiorConjunction:
            return Text("\(body) superior conjunction")
        case .greatestElongationEast:
            return Text("\(body) greatest elongation east")
        case .greatestElongationWest:
            return Text("\(body) greatest elongation west")
        case .conjunction:
            return Text("\(body) conjunction Sun")
        case .opposition:
            return Text("\(body) opposition Sun")
        case .mundaneAspect:
            // Planet–aspect–planet reads as three separate terms in every shipped language, so the
            // aspect name is translated on its own rather than baked into a per-pair pattern.
            let other = Text(L.loc((e.bodyB ?? e.bodyA).name))
            let aspect = Text(L.loc(e.aspect?.name ?? ""))
            return Text("\(body) \(aspect) \(other)")
        }
    }

    /// The small class chip under each row ("ingress", "station"…). The Kit's `rawValue` is a
    /// machine identifier, not display text, so it gets its own catalog entries.
    static func className(for e: AstroEvent) -> LocalizedStringKey {
        switch e.eventClass {
        case .ingress:     "ingress"
        case .lunation:    "lunation"
        case .station:     "station"
        case .conjunction: "conjunction"
        case .opposition:  "opposition"
        case .elongation:  "elongation"
        case .aspect:      "aspect"
        }
    }
}
