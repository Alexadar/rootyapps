import SwiftUI
import DimensionKit

/// Stacked label-over-value. `hero` renders the one big honest number.
///
/// Label sits ABOVE its value, never beside it: a side-by-side row breaks the moment the label is
/// a German compound, whereas a stack just gets taller and the number never moves or shrinks.
struct StackedReadout: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var accent: Color = SP.textPrimary
    var hero: Bool = false
    /// Applied AFTER `.combine`. Without it the combined element has no identifier of its own and
    /// the platform is free to invent one from the children — see uitests.md §3 trap 4.
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(SP.textSecondary)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(hero ? .largeTitle : .headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(hero ? accent : SP.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(SP.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
        .accessibilityIdentifier(identifier ?? "readout")
    }
}

/// **The most important thing on the watch**: entering a feet-inch-fraction without a keyboard.
///
/// The crown drives *sixteenths of an inch* as a whole number, so every value it can reach is
/// exactly representable. Two-tier acceleration: a fine detent of 1/16", a fast spin of one inch.
///
/// The targeted field carries a filled accent rail down its leading edge — on a 41 mm screen a
/// 1 pt border is not enough to say "the crown drives THIS one".
struct TapeCrownField: View {
    let label: LocalizedStringKey
    /// The value in sixteenths of an inch. Integer by design.
    @Binding var sixteenths: Double
    let targeted: Bool
    var accent: Color = SP.accent
    var denominator: Int64 = 16
    var range: ClosedRange<Double> = 0...(35 * 12 * 16)      // zero to the longest real tape
    /// How much one crown detent moves, in sixteenths.
    var stepSixteenths: Double = 1
    /// Applied after the accessibility modifiers so a test can read the crown-driven value.
    var identifier: String? = nil

    private var value: FeetInch {
        FeetInch(inches: Rational(Int64(sixteenths.rounded()), 16))
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(targeted ? accent : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(SP.textSecondary)
                    .minimumScaleFactor(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value.formatted(toDenominator: denominator))
                        .font(.system(.headline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(SP.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if targeted {
                        Image(systemName: "digitalcrown.arrow.clockwise.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accent)
                    }
                }
                .monospacedDigit()
            }
            .padding(.trailing, 9)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: SP.hit)
        .background(SP.surface, in: .rect(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? accent.opacity(0.5) : SP.hairline, lineWidth: 1)
        )
        .focusable(targeted)
        .digitalCrownRotation($sixteenths,
                              from: range.lowerBound, through: range.upperBound,
                              by: stepSixteenths,
                              sensitivity: stepSixteenths >= 16 ? .low : .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value.formatted(toDenominator: denominator)))
        .accessibilityIdentifier(identifier ?? "crownField")
        .accessibilityAdjustableAction { direction in
            let step = stepSixteenths
            switch direction {
            case .increment: sixteenths = min(sixteenths + step, range.upperBound)
            case .decrement: sixteenths = max(sixteenths - step, range.lowerBound)
            default: break
            }
        }
    }
}

/// A plain crown-driven number, for the tools that are not lengths (pitch, gage, angle).
struct WatchNumberField: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    var unit: String = ""
    let step: Double
    let range: ClosedRange<Double>
    let targeted: Bool
    var accent: Color = SP.accent
    var places: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(targeted ? accent : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(SP.textSecondary)
                    .minimumScaleFactor(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.f(value, places))
                        .font(.system(.headline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(SP.textPrimary)
                    if !unit.isEmpty {
                        Text(unit).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(SP.textTertiary)
                    }
                    Spacer(minLength: 2)
                    if targeted {
                        Image(systemName: "digitalcrown.arrow.clockwise.fill")
                            .font(.system(size: 10)).foregroundStyle(accent)
                    }
                }
                .monospacedDigit()
            }
            .padding(.trailing, 9)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: SP.hit)
        .background(SP.surface, in: .rect(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? accent.opacity(0.5) : SP.hairline, lineWidth: 1)
        )
        .focusable(targeted)
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(Fmt.f(value, places)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }
}

/// How far one crown detent moves the value.
///
/// The crown alone is not enough: at 1/16" a detent, walking from 3" to 12' is hundreds of turns.
/// These are the same tiers the phone reaches by sliding a finger off the blade, made explicit
/// because a wrist has no second axis to slide along.
enum CrownScale: String, CaseIterable, Identifiable {
    case sixteenth, inch, foot

    var id: String { rawValue }

    /// Detent size in sixteenths of an inch.
    var sixteenths: Double {
        switch self {
        case .sixteenth: return 1
        case .inch:      return 16
        case .foot:      return 192
        }
    }

    /// Authored in final case — never uppercased, which would corrupt the notation.
    var label: String {
        switch self {
        case .sixteenth: return "1/16\""
        case .inch:      return "1\""
        case .foot:      return "1'"
        }
    }
}

/// The scale picker: three chips, thumb-sized, above the crown field they govern.
///
/// `onPick` exists because these chips are `Button`s, and on watchOS a Button is focusable — so
/// tapping one takes Digital Crown focus away from the field. The field then stops responding to
/// the crown, the entry silently keeps its old value, and Add/Sub go on applying that stale
/// amount. The caller uses this to hand focus straight back.
struct CrownScalePicker: View {
    @Binding var scale: CrownScale
    var accent: Color = SP.accent
    var onPick: () -> Void = {}

    var body: some View {
        HStack(spacing: 3) {
            ForEach(CrownScale.allCases) { s in
                let on = s == scale
                Button { scale = s; onPick() } label: {
                    Text(s.label)
                        .font(.system(size: 12, design: .monospaced).weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? SP.onAccent : SP.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 30)
                        .background(on ? accent : SP.surface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("crownScale.\(s.rawValue)")
                .accessibilityLabel(Text(s.label))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Crown step"))
    }
}
