import SwiftUI
import DimensionKit

// MARK: - Surfaces

public extension View {
    /// A card laid on the board: one hairline, no shadow stack, generous inner padding.
    func spCard(_ radius: CGFloat = SP.rCard) -> some View {
        self.padding(SP.s4)
            .background(SP.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SP.hairline, lineWidth: 1)
            )
    }

    /// A card that carries a section's colour as a top rule — the catalog tile and tool header.
    func spCard(_ radius: CGFloat = SP.rCard, rule: Color) -> some View {
        self.spCard(radius)
            .overlay(alignment: .top) {
                Rectangle().fill(rule).frame(height: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius,
                                                      topTrailingRadius: radius))
            }
    }
}

/// The plaque: the one number the whole screen is for.
///
/// Fraction first and alone on its line. The decimal is a whisper underneath, never the headline —
/// defect ④: *"Normal carpentrs do not use decimals we use fractions."*
struct Readout: View {
    let value: String
    var decimal: String = ""
    var error: String? = nil
    var identifier: String = "calc.readout"

    var body: some View {
        VStack(alignment: .trailing, spacing: SP.s1) {
            if let error {
                Text(L.loc(error))
                    .font(SPType.label.weight(.semibold))
                    .foregroundStyle(SP.accent)
                    .accessibilityIdentifier("calc.error")
            }
            Text(value)
                .font(SPType.readout)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(SP.textPrimary)
                .accessibilityIdentifier(identifier)
            if !decimal.isEmpty {
                Text(decimal)
                    .font(SPType.footnote.monospacedDigit())
                    .foregroundStyle(SP.textTertiary)
                    .accessibilityIdentifier("calc.decimal")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, SP.s2)
        .spCard()
        // `.contain`, NOT `.combine`. Combining fuses the three lines into ONE element, and macOS
        // then synthesises its identifier by joining the children's — the readout surfaced as
        // `calc.readout-calc.decimal` and `app.staticTexts["calc.readout"]` did not exist at all.
        // iOS happened to keep the children addressable, so the whole class of failure was
        // invisible until the macOS suite ran. `.contain` keeps each line its own element on both
        // platforms, which is also what a VoiceOver user wants here: the fraction is the answer,
        // the decimal is a separate, skippable aside.
        .accessibilityElement(children: .contain)
    }
}

/// A labelled result. Emphasised results take the accent and the hero size.
///
/// The label sits above its value on every platform, not beside it: a long localized label then
/// makes the row taller instead of squeezing the number.
struct ResultRow: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SPType.label)
                .foregroundStyle(SP.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: SP.s1) {
                Text(value)
                    .font(emphasis ? SPType.value : SPType.valueSm)
                    .foregroundStyle(emphasis ? SP.accent : SP.textPrimary)
                    .textSelection(.enabled)
                if !unit.isEmpty {
                    Text(unit)
                        .font(SPType.footnote)
                        .foregroundStyle(SP.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "result")
    }
}

/// A dimension input that speaks feet-inch-fractions. Accepts everything `FeetInch.parse` does.
///
/// Typed, not spun, and numerator-first. Three separate reviewers call the incumbent's
/// denominator-first scroll wheel backwards.
struct DimensionField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var placeholder: String = "12' 6-1/2\""
    var identifier: String? = nil

    private var parsed: FeetInch? { FeetInch.parse(text) }
    private var invalid: Bool { !text.isEmpty && parsed == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s1) {
            Text(label)
                .font(SPType.label)
                .foregroundStyle(SP.textSecondary)
            TextField(placeholder, text: $text)
                .font(SPType.valueSm)
                .textFieldStyle(.plain)
                .padding(.horizontal, SP.s3)
                .frame(minHeight: SP.hit)
                .background(SP.surfaceSunk, in: RoundedRectangle(cornerRadius: SP.rChip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SP.rChip, style: .continuous)
                        .strokeBorder(invalid ? SP.accent : SP.hairline, lineWidth: invalid ? 1.5 : 1)
                )
                .accessibilityIdentifier(identifier ?? "input")
#if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
#endif
            // Colour is never the only signal.
            if invalid {
                Text("Not a measurement")
                    .font(SPType.footnote)
                    .foregroundStyle(SP.accent)
            }
        }
    }
}

/// A plain number input with an explicit range — the Kit guards illegal domains, this prevents
/// illegal entry.
struct NumberField: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double> = 0...1_000_000
    var identifier: String? = nil

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s1) {
            Text(label)
                .font(SPType.label)
                .foregroundStyle(SP.textSecondary)
            HStack(spacing: SP.s2) {
                TextField("0", text: $text)
                    .font(SPType.valueSm)
                    .textFieldStyle(.plain)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .onChange(of: text) { _, new in
                        if let v = Double(new.replacingOccurrences(of: ",", with: ".")) {
                            value = min(max(v, range.lowerBound), range.upperBound)
                        }
                    }
                    .accessibilityIdentifier(identifier ?? "number")
                if !unit.isEmpty {
                    Text(unit).font(SPType.footnote).foregroundStyle(SP.textTertiary)
                }
            }
            .padding(.horizontal, SP.s3)
            .frame(minHeight: SP.hit)
            .background(SP.surfaceSunk, in: RoundedRectangle(cornerRadius: SP.rChip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.rChip, style: .continuous)
                    .strokeBorder(SP.hairline, lineWidth: 1)
            )
        }
        .onAppear { if text.isEmpty { text = Fmt.trim(value) } }
    }
}

/// The denominator selector — 1/2 through 1/64, as keel-red chips rather than a system segment,
/// because precision is a first-class decision here and should look like one.
struct DenominatorPicker: View {
    @Binding var denominator: Int64
    static let options: [Int64] = [2, 4, 8, 16, 32, 64]

    var body: some View {
        HStack(spacing: SP.s1) {
            ForEach(Self.options, id: \.self) { d in
                let on = d == denominator
                Button { denominator = d } label: {
                    Text("1/\(String(d))")
                        .font(SPType.mark.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? SP.onAccent : SP.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .background(on ? SP.accent : SP.surfaceSunk,
                                    in: RoundedRectangle(cornerRadius: SP.rChip - 2, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("denominator.\(String(d))")
            }
        }
        // Deliberately NO identifier on the row.
        //
        // `.accessibilityIdentifier` on a container OVERWRITES the identifiers of the elements
        // inside it. With one here, all six chips reported as `denominator` and nothing could
        // address an individual chip — not a UI test, not any automation. Verified by dumping the
        // live hierarchy: six buttons, one identifier between them. The chips carry their own.
    }
}

/// A key cap.
///
/// `.tagged` is the feet / inch / fraction group. It is tinted, never dimmed: those keys are live at
/// every moment of every calculation, which is the incumbent's twelve-year defect.
struct KeyStyle: ButtonStyle {
    enum Kind { case plain, tagged, accent }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color = switch kind {
        case .plain:  SP.surface
        case .tagged: SP.accentSoft
        case .accent: SP.accent
        }
        let fg: Color = switch kind {
        case .plain:  SP.textPrimary
        case .tagged: SP.accent
        case .accent: SP.onAccent
        }
        return configuration.label
            .font(SPType.key)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(bg, in: RoundedRectangle(cornerRadius: SP.rKey, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SP.rKey, style: .continuous)
                    .strokeBorder(kind == .accent ? .clear : SP.hairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A section eyebrow: the colour rule plus a name, authored in final case.
struct SectionEyebrow: View {
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: SP.s2) {
            Capsule().fill(accent).frame(width: 3, height: 12)
            Text(L.loc(title))
                .font(SPType.eyebrow)
                .foregroundStyle(SP.textSecondary)
        }
    }
}

// MARK: - A prose block that is addressable on every platform

public extension View {
    /// Name a card of explanatory prose — a caution, a caveat, a provenance note — so a test can
    /// assert it actually reached the screen.
    ///
    /// ## Why this is platform-conditional
    ///
    /// The two platforms disagree about which accessibility shape survives, and this was measured,
    /// not assumed — each combination was run on both:
    ///
    /// | container shape | iOS | macOS |
    /// |---|---|---|
    /// | identifier only, no `accessibilityElement` | found | **not published at all** |
    /// | `.combine` + identifier | **dropped once scrolled off-screen** | found |
    /// | `.contain` + identifier | found, on-screen or not | **not published** |
    /// | identifier on the inner `Text` | **dropped off-screen** | found |
    ///
    /// These cards sit below the fold on a phone, which is what makes the iOS column differ from
    /// the intuition: iOS keeps an off-screen *container* in the tree but discards off-screen
    /// leaves, so anything that collapses the card into a single leaf-like element disappears
    /// exactly when the card is scrolled away. macOS publishes no container unless it is combined.
    ///
    /// So there is no single spelling that works on both, and the difference is encapsulated here
    /// rather than copied into every caveat card.
    func spProse(_ identifier: String) -> some View {
#if os(macOS)
        self.accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
#else
        self.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
#endif
    }
}
