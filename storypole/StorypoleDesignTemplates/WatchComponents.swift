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
        .accessibilityValue(Text(unit.isEmpty ? value : "(value) (unit)"))
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
    var coarse: Bool = false

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
                              by: coarse ? 16 : 1,               // 1" fast spin, 1/16" fine detent
                              sensitivity: coarse ? .low : .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value.formatted(toDenominator: denominator)))
        .accessibilityAdjustableAction { direction in
            let step: Double = coarse ? 16 : 1
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
