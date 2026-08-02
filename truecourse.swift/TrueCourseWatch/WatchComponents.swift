import SwiftUI

// TrueCourseWatch — the wrist component set. Follows DESIGN_GUIDELINES.md:
//  • matte near-black `tc.background` (#090C10) canvas, no gradient behind digits
//  • SF-Mono tabular figures everywhere; ONE off-white hero readout per sub-screen — the digits
//    stay max-contrast (`tc.textPrimary`, never pure white); the section accent lives in the
//    label / focus ring / segment fill, NEVER behind the number
//  • section accent = the tool's CalcGroup accent (`tc.accent(tool)`); ≥44pt hit targets
//  • theme-aware via `@Environment(\.tc)` (Dark today; Night is a one-line swap later)
// The crown-focus mechanism is truecourse's port of the shared CrownField/CrownFocus reference.

// MARK: - CrownFocus — the focus-reclaim signal

/// On watchOS `.digitalCrownRotation` only receives events while its view holds focus, and every
/// Button/Toggle/Picker is focusable by default — so tapping any control beside a crown field
/// silently kills the crown. Every such control calls `reclaim()` in its action to hand focus back.
@MainActor
final class CrownFocus: ObservableObject {
    @Published private(set) var token = 0
    func reclaim() { token &+= 1 }
}

// MARK: - CrownField — a tappable input card that becomes the Digital Crown's target

struct CrownField: View {
    @Environment(\.tc) private var tc
    let label: String
    @Binding var value: Double
    var unit: String = ""
    let step: Double
    let range: ClosedRange<Double>
    let targeted: Bool
    let accent: Color
    var places: Int = 0

    @EnvironmentObject private var crownFocus: CrownFocus
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(0.8)
                .foregroundStyle(tc.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.f(value, places))
                    .font(.system(.title3, design: .monospaced).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tc.textPrimary)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 9, design: .monospaced)).foregroundStyle(tc.textTertiary)
                }
                Spacer(minLength: 2)
                if targeted {
                    Image(systemName: "digitalcrown.arrow.clockwise.fill")
                        .font(.system(size: 9)).foregroundStyle(accent)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)   // glove target
        .background(tc.surfaceRaised, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(targeted ? accent : tc.hairline, lineWidth: targeted ? 1.5 : 1))   // accent focus ring
        .focusable(targeted)
        .focused($focused)
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium, isContinuous: false,
                              isHapticFeedbackEnabled: true)
        // .focusable() alone never KEEPS focus — claim on appear, on becoming the target, and after
        // any sibling control stole it.
        .onAppear { focused = targeted }
        .onChange(of: targeted) { _, t in focused = t }
        .onChange(of: crownFocus.token) { _, _ in if targeted { focused = true } }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? Fmt.f(value, places) : "\(Fmt.f(value, places)) \(unit)"))
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }
}

// MARK: - HeroReadout — the one big honest number (off-white; accent only in the label)

struct HeroReadout: View {
    @Environment(\.tc) private var tc
    let label: String
    let value: String
    var unit: String = ""
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1.0)
                .foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(tc.textPrimary)          // digits stay max-contrast (guideline)
                    .minimumScaleFactor(0.5).lineLimit(1)
                if !unit.isEmpty {
                    Text(unit).font(.system(.footnote, design: .monospaced)).foregroundStyle(tc.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
    }
}

// MARK: - WatchStat — a compact secondary readout tile

struct WatchStat: View {
    @Environment(\.tc) private var tc
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(tc.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.semibold)).monospacedDigit()
                .foregroundStyle(tc.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(tc.surfaceRaised, in: .rect(cornerRadius: 11))
    }
}

// MARK: - WatchSegmented — sub-screen pills (accent-filled selection); reclaims the crown on switch

struct WatchSegmented: View {
    @Environment(\.tc) private var tc
    let titles: [String]
    @Binding var selection: Int
    let accent: Color
    var onSwitch: () -> Void = {}

    var body: some View {
        HStack(spacing: 3) {
            ForEach(titles.indices, id: \.self) { i in
                let sel = i == selection
                Text(titles[i])
                    .font(.system(size: 11, design: .monospaced).weight(.semibold))
                    .foregroundStyle(sel ? tc.onAccent : tc.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background { if sel { RoundedRectangle(cornerRadius: 8).fill(accent) } }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = i; onSwitch() }
                    .accessibilityIdentifier("seg.\(i)")
                    .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(tc.surface, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tc.hairline, lineWidth: 1))
    }
}

// MARK: - WatchToolTile — catalog row (accent glyph + name + subtitle)

struct WatchToolTile: View {
    @Environment(\.tc) private var tc
    let tool: Tool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tc.accent(tool)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title).font(.system(.body).weight(.semibold)).foregroundStyle(tc.textPrimary)
                Text(tool.subtitle).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tc.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - WatchToolScreen — the matte canvas + title wrapper

struct WatchToolScreen<Content: View>: View {
    @Environment(\.tc) private var tc
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 7) { content }
                .padding(.horizontal, 6).padding(.bottom, 8)
        }
        .navigationTitle(title)
        .containerBackground(tc.background, for: .navigation)
    }
}
