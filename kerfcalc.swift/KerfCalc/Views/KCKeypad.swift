import SwiftUI

// The Spec calculator's hard-key pad — CM-Pro-style muscle memory, glove-sized.
// Provides the key vocabulary (`KeyFace` + `CalcKey`) and the XL layout (`SpecKeypad`).

enum KeyFace {
    case digit      // white, big ink numeral
    case op         // warm chip, ink glyph (÷ × − +)
    case equals     // signal fill, ink glyph (the one hero key)
    case dim        // white + signal underline (Feet / Inch / ⁄)
    case function   // graphite block (Rise / Run / Diag / Pitch) — solves in place
    case nav        // graphite block + signal caption (Rafter / Stair / Area / Vol) — opens a formula
    case edit       // white, muted (C / ⌫)
}

struct CalcKey: View {
    let label: String
    var sub: String? = nil
    var face: KeyFace = .digit
    var height: CGFloat = 60
    /// Test handle. Defaults to the label, but every key in `SpecKeypad` passes an explicit
    /// `key.<name>` — several labels are glyphs a test cannot type reliably (`−` is U+2212 MINUS
    /// SIGN, not a hyphen; `⁄` is U+2044 FRACTION SLASH; `⌫` is U+232B).
    var identifier: String? = nil
    let action: () -> Void

    private var bg: Color {
        switch face {
        case .digit, .dim, .edit: return KC.surface
        case .op:                 return KC.chipFill
        case .equals:             return KC.signal
        case .function, .nav:     return Color(rgbHex: 0x1E1F24)
        }
    }
    private var fg: Color {
        switch face {
        case .digit:          return KC.textPrimary
        case .op:             return Color(rgbHex: 0x2A2B30)
        case .equals:         return KC.onAccent
        case .dim:            return KC.textPrimary
        case .edit:           return KC.textSecondary
        case .function, .nav: return KC.onInstrument
        }
    }
    private var labelSize: CGFloat {
        switch face {
        case .digit:          return 27
        case .op:             return 25
        case .equals:         return 28
        case .dim:            return 18
        case .edit:           return 20
        case .function, .nav: return 16
        }
    }
    private var labelWeight: Font.Weight { face == .equals ? .heavy : (face == .digit ? .bold : .semibold) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: labelSize, weight: labelWeight, design: .rounded))
                    .foregroundStyle(fg)
                if let sub {
                    Text(sub)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(KC.signal)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(bg, in: .rect(cornerRadius: KC.rKey))
            .overlay {
                switch face {
                case .digit, .edit:
                    RoundedRectangle(cornerRadius: KC.rKey).strokeBorder(KC.hairline, lineWidth: 1)
                case .op:
                    RoundedRectangle(cornerRadius: KC.rKey).strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                case .dim:
                    RoundedRectangle(cornerRadius: KC.rKey).strokeBorder(KC.hairline, lineWidth: 1)
                        .overlay(alignment: .bottom) { KC.signal.frame(height: 3).clipShape(.rect(bottomLeadingRadius: KC.rKey, bottomTrailingRadius: KC.rKey)) }
                default:
                    EmptyView()
                }
            }
            .shadow(color: .black.opacity(face == .digit || face == .equals ? 0.05 : 0), radius: 1, y: 1)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(identifier ?? label)
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .brightness(configuration.isPressed ? 0.09 : 0)
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: KC.rKey)
                        .strokeBorder(KC.signal.opacity(0.9), lineWidth: 2.5)
                }
            }
            .animation(.snappy(duration: 0.11), value: configuration.isPressed)
    }
}

/// The full glove-XL CM-Pro layout. Pass one handler that receives a `KeyID`;
/// route those into the existing CalcEngine.
struct SpecKeypad: View {
    enum KeyID: Hashable {
        case feet, inch, frac, backspace
        case rise, run, diag, pitch
        case rafter, stair, area, vol
        case digit(Int), div, mul, sub, add
        case clear, equals
    }
    var tap: (KeyID) -> Void

    private let gap: CGFloat = 8
    private var funcH: CGFloat { 50 }

    var body: some View {
        VStack(spacing: gap) {
            row {
                key(.feet, "Feet", face: .dim)
                key(.inch, "Inch", face: .dim)
                key(.frac, "⁄",    face: .dim)
                key(.backspace, "⌫", face: .edit)
            }
            row {
                key(.rise,  "Rise",  face: .function, height: funcH)
                key(.run,   "Run",   face: .function, height: funcH)
                key(.diag,  "Diag",  face: .function, height: funcH)
                key(.pitch, "Pitch", face: .function, height: funcH)
            }
            row {
                key(.rafter, "Rafter", sub: "OPEN ↗", face: .nav, height: funcH)
                key(.stair,  "Stair",  sub: "OPEN ↗", face: .nav, height: funcH)
                key(.area,   "Area",   sub: "OPEN ↗", face: .nav, height: funcH)
                key(.vol,    "Vol",    sub: "OPEN ↗", face: .nav, height: funcH)
            }
            row { digit(7); digit(8); digit(9); key(.div, "÷", face: .op) }
            row { digit(4); digit(5); digit(6); key(.mul, "×", face: .op) }
            row { digit(1); digit(2); digit(3); key(.sub, "−", face: .op) }
            row {
                key(.clear, "C", face: .edit)
                digit(0)
                key(.equals, "=", face: .equals)
                key(.add, "+", face: .op)
            }
        }
    }

    /// Build a key from its `KeyID`, so the accessibility identifier is derived from the model and
    /// cannot drift from it: add a key here and it is addressable by a test for free.
    private func key(_ id: KeyID, _ label: String, sub: String? = nil,
                     face: KeyFace = .digit, height: CGFloat = 60) -> some View {
        CalcKey(label: label, sub: sub, face: face, height: height,
                identifier: "key." + SpecKeypad.name(id)) { tap(id) }
    }

    /// `KeyID` → identifier suffix. Internal (not private) so a model test can pin the whole table:
    /// a silently renamed id turns every keypad test into a "missing element" failure at once.
    static func name(_ id: KeyID) -> String {
        switch id {
        case .feet:      return "feet"
        case .inch:      return "inch"
        case .frac:      return "fraction"
        case .backspace: return "backspace"
        case .rise:      return "rise"
        case .run:       return "run"
        case .diag:      return "diag"
        case .pitch:     return "pitch"
        case .rafter:    return "rafter"
        case .stair:     return "stair"
        case .area:      return "area"
        case .vol:       return "vol"
        case .digit(let n): return "digit\(n)"
        case .div:       return "op.div"
        case .mul:       return "op.mul"
        case .sub:       return "op.sub"
        case .add:       return "op.add"
        case .clear:     return "clear"
        case .equals:    return "equals"
        }
    }

    private func digit(_ n: Int) -> some View { key(.digit(n), "\(n)", face: .digit) }
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: gap) { content() }
    }
}
