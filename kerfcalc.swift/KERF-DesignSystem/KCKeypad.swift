import SwiftUI

// The Spec calculator's hard-key pad — the CM-Pro-style muscle memory, glove-sized.
// This file provides the *key vocabulary* (`KeyFace` + `CalcKey`) and a ready-made
// XL layout (`SpecKeypad`). Wire the actions to the existing CalcEngine — the button
// faces and geometry are all here.

/// Seven key roles. Two "weights" carry the identity: light paper keys for digits,
/// graphite blocks for the function/nav keys, and one signal key for "=".
enum KeyFace {
    case digit      // white, big ink numeral
    case op         // warm chip, ink glyph (÷ × − +)
    case equals     // signal fill, ink glyph (the one hero key)
    case dim        // white + signal underline (Feet / Inch / ⁄) — dimension entry
    case function   // graphite block (Rise / Run / Diag / Pitch) — solves in place
    case nav        // graphite block + signal caption (Rafter / Stair / Area / Vol) — opens a formula
    case edit       // white, muted (C / ⌫)
}

/// One keypad key. Height defaults to a glove-friendly 60pt; function/nav rows
/// pass a slightly shorter height so a full CM-Pro layout fits in portrait.
struct CalcKey: View {
    let label: String
    var sub: String? = nil
    var face: KeyFace = .digit
    var height: CGFloat = 60
    let action: () -> Void

    @State private var pressed = false

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
    }
}

/// Snappy press-scale used by every key.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .animation(.snappy(duration: 0.10), value: configuration.isPressed)
    }
}

/// The full glove-XL CM-Pro layout. Pass one handler that receives a `KeyID`;
/// route those into the existing CalcEngine. Dimension + function keys sit above
/// the numeric block, exactly as on the hardware.
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
            row { // dimension + edit
                CalcKey(label: "Feet", face: .dim) { tap(.feet) }
                CalcKey(label: "Inch", face: .dim) { tap(.inch) }
                CalcKey(label: "⁄",    face: .dim) { tap(.frac) }
                CalcKey(label: "⌫",    face: .edit) { tap(.backspace) }
            }
            row { // function keys — solve in place
                CalcKey(label: "Rise",  face: .function, height: funcH) { tap(.rise) }
                CalcKey(label: "Run",   face: .function, height: funcH) { tap(.run) }
                CalcKey(label: "Diag",  face: .function, height: funcH) { tap(.diag) }
                CalcKey(label: "Pitch", face: .function, height: funcH) { tap(.pitch) }
            }
            row { // nav keys — hand off to the big formulas
                CalcKey(label: "Rafter", sub: "OPEN ↗", face: .nav, height: funcH) { tap(.rafter) }
                CalcKey(label: "Stair",  sub: "OPEN ↗", face: .nav, height: funcH) { tap(.stair) }
                CalcKey(label: "Area",   sub: "OPEN ↗", face: .nav, height: funcH) { tap(.area) }
                CalcKey(label: "Vol",    sub: "OPEN ↗", face: .nav, height: funcH) { tap(.vol) }
            }
            row { digit(7); digit(8); digit(9); CalcKey(label: "÷", face: .op) { tap(.div) } }
            row { digit(4); digit(5); digit(6); CalcKey(label: "×", face: .op) { tap(.mul) } }
            row { digit(1); digit(2); digit(3); CalcKey(label: "−", face: .op) { tap(.sub) } }
            row {
                CalcKey(label: "C", face: .edit) { tap(.clear) }
                digit(0)
                CalcKey(label: "=", face: .equals) { tap(.equals) }
                CalcKey(label: "+", face: .op) { tap(.add) }
            }
        }
    }

    private func digit(_ n: Int) -> some View { CalcKey(label: "\(n)", face: .digit) { tap(.digit(n)) } }
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: gap) { content() }
    }
}
