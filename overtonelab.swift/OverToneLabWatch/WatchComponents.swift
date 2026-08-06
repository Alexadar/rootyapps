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
    /// Names the combined element. `.combine` normally destroys the children's identifiers and
    /// macOS synthesises a joined one, so the result has to be named explicitly — which is exactly
    /// the second correct shape from the accessibility traps, and what makes this readout
    /// addressable from a test instead of anonymous.
    var id: String? = nil

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
        .accessibilityIdentifier(id ?? "")
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
    }
}

/// Signal that the crown's focus has to be taken back.
///
/// On watchOS `.digitalCrownRotation` only receives events while its view holds focus, and every
/// Button and Toggle is focusable by default. So tapping "Tap tempo" — or any control beside a
/// field — silently moves focus off the field and the crown goes dead: nothing crashes, no layout
/// changes, the number just stops responding.
///
/// **The primary cure is `.focusable(false)` on the buttons**, not this. Handing focus back was
/// tried first and measurably does not work: a Button's action runs *before* SwiftUI moves focus to
/// it, so the reclaim is overwritten — bouncing through `false` and deferring a tenth of a second
/// both still failed. This stays as a second line for controls that must remain focusable (the
/// Bernoulli toggle keeps working through it), and because it costs nothing.
///
/// The regression lives in `overtonelabWatchUITests/CrownFocusChecks.swift`, not in a comment asking
/// someone to remember: `XCUIDevice.rotateDigitalCrown(delta:)` drives the crown from a test, so
/// scrub → tap the thief → scrub again is scriptable. Before this class existed the second scrub
/// changed nothing.
@MainActor
final class CrownFocus: ObservableObject {
    @Published private(set) var token = 0
    func reclaim() { token &+= 1 }
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
    /// Set when this value arrived from a phone measurement. Renders the same three signals the phone
    /// uses — glyph, dotted underline, the word *Measured* — because a value should not change meaning
    /// when it changes wrist. **The first crown detent clears it**: the moment the user turns the
    /// crown, the number is theirs.
    var measuredSource: String? = nil

    @EnvironmentObject private var crownFocus: CrownFocus
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if measuredSource != nil {
                    Image(systemName: "waveform")            // 1 — shape
                        .font(.system(size: 8))
                        .foregroundStyle(OTL.textSecondary)
                        .accessibilityHidden(true)
                }
                Group {
                    if measuredSource != nil {
                        Text("\(Text(label)) · \(Text("Measured"))")   // 2 — words
                    } else {
                        Text(label)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OTL.textSecondary)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            }
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
        .overlay(alignment: .bottom) {
            if measuredSource != nil {              // 3 — texture, same as the phone
                DottedRule()
                    .stroke(style: .init(lineWidth: 2, dash: [2, 3]))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(height: 2)
            }
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
        .focused($focused)
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        // .focusable() alone is not enough: it makes focus *possible*, never keeps it. Focus has
        // to be claimed on appear, re-claimed when this card becomes the target, and re-claimed
        // after any sibling control took it.
        .onAppear { focused = targeted }
        .onChange(of: targeted) { _, isTarget in focused = isTarget }
        // Reclaiming has to happen AFTER the tap's own focus move, not during it. A button's action
        // runs *before* SwiftUI hands focus to that button, so assigning `focused = true` inside the
        // action is immediately overwritten — which is why the first version of this fix looked
        // right, compiled, shipped, and left the crown just as dead. The regression test
        // (CrownFocusChecks) is what caught it. Bouncing through false forces a real state
        // transition, since assigning the value it already holds is a no-op.
        .onChange(of: crownFocus.token) { _, _ in
            guard targeted else { return }
            focused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text({
            let base = unit.isEmpty ? Fmt.f(value, fraction) : "\(Fmt.f(value, fraction)) \(unit)"
            return measuredSource == nil ? base : "\(base), measured"
        }()))
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
