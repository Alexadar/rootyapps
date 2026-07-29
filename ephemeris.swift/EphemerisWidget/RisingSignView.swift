import WidgetKit
import SwiftUI
import EphemerisKit

/// Renders the Ascendant across all four accessory families.
///
/// Every family must handle `sign == nil`. That is not an error case to be tidied away later: the
/// Ascendant is undefined without an observer position, and the app can legitimately have none.
/// Showing a plausible-looking sign computed from a guessed location would be worse than showing
/// nothing, because there is no way for the wearer to tell it is wrong.
///
/// There is deliberately no loading or "updating" state. WidgetKit renders pre-computed timeline
/// entries with the app not running — a value here is exact or absent, never pending.
struct RisingSignView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RisingSignEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)

        case .accessoryCorner:
            // The corner gauge shows progress through the current sign — a slow sweep that
            // completes roughly every two hours, which is what makes this worth a face slot.
            Text(entry.sign?.glyph ?? "—")
                .font(.title2)
                .widgetLabel {
                    Gauge(value: entry.degreesIntoSign, in: 0...30) { Text(verbatim: "AC") }
                        .tint(.pink)
                }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "ASCENDANT").font(.caption2).foregroundStyle(.secondary)
                if let sign = entry.sign {
                    Text(verbatim: "\(sign.glyph) \(degreeText)").font(.headline)
                    if let place = entry.placeName {
                        Text(verbatim: place).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(noPlaceText).font(.caption)
                }
            }

        default:   // .accessoryCircular
            VStack(spacing: 0) {
                Text(entry.sign?.glyph ?? "—").font(.title3)
                if entry.sign != nil {
                    Text(verbatim: "\(Int(entry.degreesIntoSign))°").font(.system(size: 10))
                }
            }
        }
    }

    private var degreeText: String {
        let d = Int(entry.degreesIntoSign)
        let m = Int((entry.degreesIntoSign - Double(d)) * 60)
        return String(format: "%d° %02d′", d, m)
    }

    private var inlineText: String {
        guard let sign = entry.sign else { return noPlaceText }
        return "AC \(sign.glyph) \(degreeText)"
    }

    /// Not an apology — an instruction. The wearer can fix it, so say what to do.
    private var noPlaceText: String { "Set a place in Ephemeris" }
}
