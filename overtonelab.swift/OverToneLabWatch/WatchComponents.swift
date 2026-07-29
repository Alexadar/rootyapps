import SwiftUI

// The watch component set, ported from DesignSystem/OTLWatch.example.swift.
// Same tokens and section accents as phone/Mac — only the layout rules differ.

/// Stacked label-over-value. `hero` renders the one big honest number.
///
/// Label sits ABOVE its value, never beside it: a side-by-side row breaks the moment the label
/// is a German compound (`Nachhallzeit`, `Schroeder-Frequenz`), whereas a stack just gets taller
/// and the number never moves or shrinks.
struct StackedReadout: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var accent: Color = OTL.textPrimary
    var hero: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OTL.textSecondary)
                .minimumScaleFactor(0.85)          // shrink before truncating a localized label
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(hero ? .largeTitle : .headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(hero ? accent : OTL.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(OTL.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
    }
}

/// A tappable card that becomes the Digital Crown's target (accent ring).
/// Two-tier acceleration only — fine detent and fast spin, no third speed.
struct CrownField: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    var unit: String = ""
    let step: Double
    let range: ClosedRange<Double>
    let targeted: Bool
    let accent: Color
    var fraction: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OTL.textSecondary)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // Fmt follows the chosen language, exactly as on phone — display and entry agree.
                Text(Fmt.f(value, fraction))
                    .font(.system(.headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(OTL.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(OTL.textTertiary)
                }
                Spacer(minLength: 2)
                if targeted {
                    Image(systemName: "digitalcrown.arrow.clockwise.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(accent)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)                       // hit target
        .background(OTL.surface, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? accent.opacity(0.5) : OTL.hairline, lineWidth: 1)
        )
        .focusable(targeted)
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? Fmt.f(value, fraction) : "\(Fmt.f(value, fraction)) \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }
}

/// Tap tempo — the one input the wrist does better than the phone.
/// Four taps lock BPM to the mean of the last eight intervals, rounded to ±0.5 BPM.
@MainActor
final class TapTempo: ObservableObject {
    @Published private(set) var bpm: Double = 120
    @Published private(set) var taps: Int = 0
    private var stamps: [Date] = []

    func tap() {
        let now = Date()
        // A gap longer than two seconds means a new count-in, not a slow tempo.
        if let last = stamps.last, now.timeIntervalSince(last) > 2 { stamps.removeAll() }
        stamps.append(now)
        if stamps.count > 9 { stamps.removeFirst(stamps.count - 9) }
        taps = stamps.count
        guard stamps.count >= 4 else { return }          // need four taps to lock
        let intervals = zip(stamps.dropFirst(), stamps).map { $0.timeIntervalSince($1) }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return }
        bpm = min(max((60 / mean * 2).rounded() / 2, 30), 300)
    }
}
