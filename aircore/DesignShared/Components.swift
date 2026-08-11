import SwiftUI
import UnitsKit

/// A tabular numeric readout with its unit attached in a smaller, quieter style.
///
/// The unit is drawn as part of the same text run so it wraps and scales with the number under
/// Dynamic Type instead of drifting onto its own line.
public struct NumberReadout: View {
    private let value: String
    private let unit: String
    private let size: CGFloat
    private let colour: Color

    public init(_ value: String, unit: String, size: CGFloat = 26, colour: Color = DS.ink) {
        self.value = value
        self.unit = unit
        self.size = size
        self.colour = colour
    }

    public var body: some View {
        (Text(value).font(DS.number(size)).foregroundStyle(colour)
         + Text(unit.isEmpty ? "" : " \(unit)")
            .font(DS.number(size * 0.55, .medium)).foregroundStyle(DS.ink2))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// One computed result: a label, a number, a unit.
///
/// The whole tile is a single accessibility element reading "Wet bulb, 62.5 degrees Fahrenheit" —
/// a screen reader landing on the number alone would have no idea what it was.
public struct ResultTile: View {
    private let label: LocalizedStringKey
    private let spokenLabel: String
    private let value: String
    private let unit: String
    private let spoken: String
    private let emphasised: Bool

    public init(label: LocalizedStringKey, spokenLabel: String,
                value: String, unit: String, spoken: String, emphasised: Bool = false) {
        self.label = label
        self.spokenLabel = spokenLabel
        self.value = value
        self.unit = unit
        self.spoken = spoken
        self.emphasised = emphasised
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DS.ui(11, .medium))
                .foregroundStyle(emphasised ? DS.water : DS.ink2)
            NumberReadout(value, unit: unit, size: 19)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.s3)
        .padding(.vertical, DS.s2)
        .background(emphasised ? DS.waterTint : DS.card)
        .overlay(RoundedRectangle(cornerRadius: DS.radiusTile)
            .stroke(emphasised ? DS.water : DS.border, lineWidth: emphasised ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusTile))
        .accessibilityElement(children: .ignore)
        // Name and number in the LABEL, not split across label and value.
        //
        // macOS does not publish `accessibilityValue` for this element: the tile surfaces as a
        // group, `value` comes back empty, and a VoiceOver user on the Mac hears "Wet bulb" and no
        // number — every result on every screen, silently. iOS carries the value fine, which is
        // exactly why this survived until the suite was first run on macOS.
        //
        // The label is the one attribute both platforms carry (uitests.md §3, Trap 3), so the
        // whole utterance goes there: "Wet bulb, 62.6 degrees Fahrenheit".
        .accessibilityLabel("\(spokenLabel), \(spoken)")
    }
}

/// A status message that never relies on colour.
///
/// Every state carries an icon **and** a word as well as a tint, because "nothing conveyed by
/// colour alone" is an accessibility floor for this app, and because a red banner in bright sun on
/// a phone at arm's length is just a grey banner.
public struct StatusBanner: View {
    public enum Kind: Sendable {
        case ok, warning, error

        var colour: Color {
            switch self {
            case .ok: return DS.inRange
            case .warning, .error: return DS.warn
            }
        }
        var tint: Color {
            switch self {
            case .ok: return DS.okTint
            case .warning, .error: return DS.warnTint
            }
        }
        var symbol: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    private let kind: Kind
    private let title: String
    private let detail: String

    public init(kind: Kind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DS.s2) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.colour)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.ui(12.5, .semibold)).foregroundStyle(kind.colour)
                if !detail.isEmpty {
                    Text(detail).font(DS.number(11, .regular)).foregroundStyle(DS.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.s3)
        .background(kind.tint)
        .overlay(RoundedRectangle(cornerRadius: DS.radiusTile)
            .stroke(kind.colour, lineWidth: kind == .ok ? 1 : 1.5))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusTile))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

/// The elevation chip: always on screen, never buried in a settings pane.
public struct AltitudeChip: View {
    private let elevationMetres: Double
    private let system: UnitSystem
    private let action: () -> Void

    public init(elevationMetres: Double, system: UnitSystem, action: @escaping () -> Void) {
        self.elevationMetres = elevationMetres
        self.system = system
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.s1) {
                Image(systemName: "mountain.2.fill").font(.system(size: 9, weight: .bold))
                Text(Fmt.valueWithUnit(si: elevationMetres, .elevation, system))
                    .font(DS.number(12))
            }
            .foregroundStyle(DS.ink)
            .padding(.horizontal, DS.s3)
            .padding(.vertical, 6)
            .background(DS.panel)
            .overlay(Capsule().stroke(DS.border, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Site elevation")
        .accessibilityValue(Fmt.spoken(si: elevationMetres, .elevation, system))
        .accessibilityHint("Changes the elevation every tool computes at")
        .accessibilityIdentifier("settings.elevation")
    }
}

/// IP ⇄ SI. One tap, everywhere, and the stored value never moves.
public struct UnitToggle: View {
    @Binding private var system: UnitSystem

    public init(system: Binding<UnitSystem>) {
        self._system = system
    }

    public var body: some View {
        Button {
            system = system.other
        } label: {
            Text(system.rawValue)
                .font(DS.number(12))
                .foregroundStyle(DS.ink)
                .padding(.horizontal, DS.s3)
                .padding(.vertical, 6)
                .background(DS.panel)
                .overlay(Capsule().stroke(DS.border, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unit system")
        .accessibilityValue(system == .ip ? "Imperial" : "Metric")
        .accessibilityHint("Switches every value between imperial and metric")
        .accessibilityIdentifier("settings.units")
    }
}
