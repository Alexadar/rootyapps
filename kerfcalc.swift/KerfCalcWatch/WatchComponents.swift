import SwiftUI

// KerfCalcWatch — the wrist component set, built to kerfcalc's OWN design system.
//
// ## This was rebuilt. What it used to be, and why that was wrong
//
// The first version was the shared house watch pattern (the same `WatchComponents` /
// `WatchRootView` / `WatchTools` trio, the same `CrownField` and `WatchToolScreen`, a near-black
// canvas) that `truecourse.swift/TrueCourseWatch` and `overtonelab.swift/OverToneLabWatch` use. Those
// are dark-identity apps, so it fits them. **kerfcalc is not.**
//
// `KERF-DesignSystem/DESIGN_GUIDELINES.md` §1 is explicit: *"A light field instrument. Most calc apps
// are dark keypads; KERF inverts that for sunlight readability."* A concrete "paper" body `#EDE9E0`,
// matte white cards, and **one** dark instrument — the graphite panel that holds the hero number. The
// old wrist build made the *whole screen* that instrument, which inverted the app's entire identity
// and made the watch read as a different product.
//
// Note that §8 of the design system covers "iPhone · iPad · Mac" only: there is no watch section, so
// there was never a kerfcalc rule saying dark. The justification came from another app's watch doc.
// Wrong source.
//
// ## So: the same tokens as the phone, on the wrist
//
// | Role | Token | Same as phone? |
// |---|---|---|
// | body | `KC.background` `#EDE9E0` | yes |
// | cards, fields | `KC.surface` white + `KC.hairline` | yes |
// | ink | `KC.textPrimary` / `Secondary` / `Tertiary` | yes |
// | the ONE dark instrument | `KC.instrument` `#16171B`, hero in `KC.signal` | yes |
// | trade accent | `Tool.accent` | yes |
//
// ## The one thing the watch must add: an ambient state
//
// A paper-white rectangle at full brightness in the always-on state is both a battery cost and a
// night-vision problem, and that is the real argument the dark build was reaching for. It does not
// require a permanently dark app — it requires an ambient *state*. `@Environment(\.isLuminanceReduced)`
// swaps the paper for black, drops card fills and hairlines, and steps the hero back. Lit: KERF. Wrist
// down: dark. Both correct, neither at the other's expense.

// MARK: - Watch number formatting

/// kerfcalc has no shared `Fmt`/`LanguageStore` helper (that's an overtonelab thing); keep a tiny
/// fixed-places formatter local to the watch. Digits are always rendered `.monospacedDigit()`.
enum WFmt {
    static func f(_ value: Double, _ places: Int) -> String { String(format: "%.\(places)f", value) }
}

// MARK: - KC tokens on the wrist

enum KCW {
    // Lit state — the phone's palette, unchanged.
    static let paper     = KC.background        // #EDE9E0 concrete body
    static let card      = KC.surface           // #FFFFFF matte card
    static let hairline  = KC.hairline          // black 6%
    static let ink       = KC.textPrimary       // #16171B
    static let inkSoft   = KC.textSecondary     // #6E6F75 labels
    static let inkFaint  = KC.textTertiary      // #A7A296 units
    static let instrument = KC.instrument       // #16171B — the ONE dark surface, holds the hero
    static let onInstrument = KC.onInstrument   // #F3F2EC
    static let instrumentDim = KC.instrumentDim // #7C7D83 caption on graphite
    static let signal    = KC.signal            // #E8FB4A the hero number

    /// Ambient (always-on). Not a faded copy of the lit theme — a different one.
    static let ambientCanvas = Color.black
    static let ambientInk    = Color(rgbHex: 0x9A9BA2)

    /// Metrics. Rows 40 pt; anything consequential 44 pt (44 pt rows fit two tools on a 40 mm screen).
    static let row: CGFloat = 40
    static let hit: CGFloat = 44
    static let rCard: CGFloat = 12               // tighter than the phone's 20 — 20 looks like a pill at 162 pt
    static let gap: CGFloat = 6
}

// MARK: - Hero — the one dark instrument per screen

/// The single graphite panel holding the screen's answer, in `signal`.
///
/// This is `DESIGN_GUIDELINES.md` §5's `HeroReadout` at wrist scale, and §9's rule — *"exactly one
/// `HeroReadout` per screen; the hero colour is `signal` on graphite"* — holds here too. The number
/// never appears as tinted text on a light card.
struct WatchHero: View {
    let label: String
    let value: String
    var unit: String = ""
    var identifier: String? = nil

    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(KCW.instrumentDim)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(KCW.signal.opacity(dimmed ? 0.75 : 1))
                    .minimumScaleFactor(0.5).lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, design: .monospaced).weight(.semibold))
                        .foregroundStyle(KCW.instrumentDim)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KCW.instrument, in: .rect(cornerRadius: KCW.rCard))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "result.hero")
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
    }
}

// MARK: - Secondary result row — label ↔ mono value on a white card

/// `DESIGN_GUIDELINES.md` §5's `ResultRow`: label ↔ monospaced value, `emphasis` tinting a *secondary*
/// loud line in the trade accent. Never the hero.
struct WatchRow: View {
    let label: String
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var accent: Color = KC.textPrimary
    var identifier: String? = nil

    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(dimmed ? KCW.ambientInk : KCW.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 3)
            Text(value)
                .font(.system(size: 13, design: .monospaced).weight(.semibold))
                .foregroundStyle(dimmed ? KCW.ambientInk
                                        : (emphasis ? accent : KCW.ink))
                .monospacedDigit().lineLimit(1).fixedSize()
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(dimmed ? KCW.ambientInk : KCW.inkFaint)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(dimmed ? .clear : KCW.card, in: .rect(cornerRadius: KCW.rCard))
        .overlay(RoundedRectangle(cornerRadius: KCW.rCard)
            .strokeBorder(dimmed ? .clear : KCW.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "result")
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
    }
}

/// A phone input this screen does not expose, pinned at the phone's default and shown, not hidden.
struct WatchPinnedRow: View {
    let label: String
    let value: String
    let identifier: String

    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 7))
            Text(label).font(.system(size: 10, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 3)
            Text(value).font(.system(size: 10, design: .monospaced).weight(.semibold))
                .monospacedDigit().lineLimit(1).fixedSize()
        }
        .foregroundStyle(dimmed ? KCW.ambientInk : KCW.inkFaint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - CrownFocus — the focus-reclaim signal

/// On watchOS `.digitalCrownRotation` only receives events while its view holds focus, and every
/// Button/Toggle/Picker is focusable by default. So tapping any control beside a crown field
/// silently moves focus off the field and the crown goes dead — nothing crashes, no layout
/// changes, the value just stops responding (and whatever consumes it keeps re-applying the last
/// value). Nothing in a build or a unit test can see this; it needs a wrist — or
/// `XCUIDevice.rotateDigitalCrown`, which is what `KerfCalcWatchUITests/CrownFocusChecks` uses.
/// Every Button / Toggle / Picker on a crown-driven screen calls `reclaim()` in its action.
@MainActor
final class CrownFocus: ObservableObject {
    @Published private(set) var token = 0
    func reclaim() { token &+= 1 }
}

// MARK: - CrownField — a white input card that becomes the crown's target

/// Glove-first input, the wrist counterpart of `DESIGN_GUIDELINES.md` §5's `StepperRow`: a white card,
/// hairline border, and the trade accent marking which field the crown drives. ≥ 44 pt (§3).
struct CrownField: View {
    let label: String
    @Binding var value: Double
    var unit: String = ""
    let step: Double
    let range: ClosedRange<Double>
    let targeted: Bool
    let accent: Color
    var places: Int = 0
    /// Test handle, e.g. `input.concrete.length`. House convention: `tool.<name>` / `input.<name>` /
    /// `result.<name>`, and **value-independent** — an identifier containing the value changes as the
    /// crown turns, which is how three of them silently broke elsewhere.
    var identifier: String? = nil

    @EnvironmentObject private var crownFocus: CrownFocus
    @FocusState private var focused: Bool
    /// Always-on is a DISTINCT state, not a faded one.
    @Environment(\.isLuminanceReduced) private var dimmed

    private var text: String { WFmt.f(value, places) }

    var body: some View {
        HStack(spacing: 7) {
            // A filled accent rail, not a 1 pt ring: at 162 pt a border does not say "the crown drives
            // THIS one" clearly enough to trust while wearing gloves.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(targeted ? accent : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(dimmed ? KCW.ambientInk : KCW.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text)
                        .font(.system(.headline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(dimmed ? KCW.ambientInk : KCW.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(dimmed ? KCW.ambientInk : KCW.inkFaint)
                    }
                    Spacer(minLength: 2)
                    if targeted && !dimmed {
                        Image(systemName: "digitalcrown.arrow.clockwise.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(accent)
                    }
                }
                .monospacedDigit()
            }
            .padding(.trailing, 8).padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: KCW.hit)
        // Ambient: fills and hairlines go entirely — a large lit area is what the state exists to avoid.
        .background(dimmed ? .clear : KCW.card, in: .rect(cornerRadius: KCW.rCard))
        .overlay(RoundedRectangle(cornerRadius: KCW.rCard)
            .strokeBorder(targeted ? accent.opacity(0.55)
                                   : (dimmed ? .clear : KCW.hairline), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: KCW.rCard, style: .continuous))
        // `!dimmed`: with the wrist down a sleeve must not scrub a value you cannot see, then have the
        // next action commit it — the same class of silent wrong number as the focus theft above.
        .focusable(targeted && !dimmed)
        .focused($focused)
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        // .focusable() alone never KEEPS focus. Claim it on appear, re-claim when this card becomes
        // the target, and re-claim after any sibling control (Button/Toggle/Picker) stole it.
        .onAppear { focused = targeted && !dimmed }
        .onChange(of: targeted) { _, isTarget in focused = isTarget && !dimmed }
        .onChange(of: crownFocus.token) { _, _ in if targeted && !dimmed { focused = true } }
        // Take focus back when the wrist comes up, or the crown stays dead after every ambient dip.
        .onChange(of: dimmed) { _, isDim in focused = targeted && !isDim }
        // `.combine` FIRST, then the identifier.
        //
        // Without it this card is not an accessibility element at all, so SwiftUI pushes the identifier
        // down onto every child: `app.debugDescription` showed `input.estimate.area` published THREE
        // times — once on the label, once on the value, once on the unit. `firstMatch` then returns an
        // arbitrary 12 pt fragment, a tap aimed at "the field" lands on a caption instead of the card,
        // and VoiceOver reads the field as three disconnected pieces. One element, named once.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "input")
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(unit.isEmpty ? text : "\(text) \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }
}

// MARK: - Picker chrome

extension View {
    /// Standard sizing for the wheel pickers on the tool screens.
    ///
    /// A watchOS `Picker` sizes its wheel from the inherited font, so a `.caption2` collapsed them to a
    /// ~22 pt sliver — half Apple's 44 pt minimum, in an app used with gloves on a moving wrist.
    func watchPicker(tint: Color, identifier: String? = nil) -> some View {
        self.font(.system(.body, design: .monospaced))
            .frame(minHeight: KCW.hit)
            .tint(tint)
            .labelsHidden()
            .accessibilityIdentifier(identifier ?? "input.picker")
    }
}

// MARK: - Shared screen chrome

/// A tool screen: the concrete paper body, the tool's title, its trade accent as the tint.
struct WatchToolScreen<Content: View>: View {
    let tool: Tool
    @ViewBuilder var content: Content

    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        ScrollView {
            VStack(spacing: KCW.gap) { content }
                .padding(.horizontal, 5)
                .padding(.bottom, 8)
        }
        .navigationTitle(tool.title)
        // One `.tint(tool.accent)` at screen level, exactly as the phone does it (§2), so the accent
        // flows to the pickers without every call site repeating it.
        .tint(tool.accent)
        .containerBackground(dimmed ? KCW.ambientCanvas : KCW.paper, for: .navigation)
    }
}
