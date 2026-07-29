import SwiftUI

/// Par's own keypad. Four columns, its own legends, a labelled Solve verb —
/// deliberately not the layout of any physical unit.
public struct Keypad: View {
    public enum Key: Hashable {
        case digit(Int), decimal, sign, backspace, clearEntry, solve
    }

    private let solveTargetName: String
    private let columns: Int
    private let onKey: (Key) -> Void

    /// `columns` is 4 normally and 3 in a compact width (Split View, Slide Over).
    public init(solveTargetName: String, columns: Int = 4, onKey: @escaping (Key) -> Void) {
        self.solveTargetName = solveTargetName
        self.columns = columns
        self.onKey = onKey
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Par.Metrics.keyGap) {
            // The digit block. SwiftUI's Grid can span columns but not rows, so the tall Solve key
            // lives in its own trailing column rather than as a row-spanning cell.
            Grid(horizontalSpacing: Par.Metrics.keyGap, verticalSpacing: Par.Metrics.keyGap) {
                ForEach(digitRows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keyView(key)
                        }
                    }
                }
            }
            // The action column exists in both widths. Only Solve moves: it takes the bottom of the
            // column where there is room for it, and spans the keypad where there is not.
            VStack(spacing: Par.Metrics.keyGap) {
                keyView(.backspace)
                keyView(.clearEntry)
                if columns == 4 {
                    solveKey.frame(minHeight: Par.Metrics.minHitTarget * 2 + Par.Metrics.keyGap)
                } else {
                    keyView(.sign).frame(maxHeight: .infinity)
                }
            }
            .frame(width: columns == 4 ? 84 : 72)
        }
        // Size to the keys. Without this the block absorbs whatever height is going spare and hands
        // it all to the one flexible child — on a 13" iPad that turned Solve into a bar twice the
        // height of the digits beside it.
        .fixedSize(horizontal: false, vertical: true)
        .safeAreaInset(edge: .bottom, spacing: Par.Metrics.keyGap) {
            if columns == 3 { solveKey } else { EmptyView() }
        }
        .padding(8)
        .background(Par.Palette.surfaceRecessed)
    }

    /// The digit block only — the action keys are laid out around it.
    private var digitRows: [[Key]] {
        [[.digit(7), .digit(8), .digit(9)],
         [.digit(4), .digit(5), .digit(6)],
         [.digit(1), .digit(2), .digit(3)],
         [.digit(0), .decimal, .sign]]
    }

    @ViewBuilder
    private func keyView(_ key: Key) -> some View {
        if case .solve = key {
            solveKey
        } else {
            Button { onKey(key) } label: {
                Text(legend(key))
                    .font(.title2)
                    .foregroundStyle(Par.Palette.label)
                    .frame(maxWidth: .infinity, minHeight: Par.Metrics.minHitTarget + 6)
                    .background(
                        RoundedRectangle(cornerRadius: Par.Metrics.keyRadius, style: .continuous)
                            .fill(Par.Palette.surfaceRaised)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keypad.\(identifier(key))")
            .accessibilityLabel(spokenLabel(key))
        }
    }

    private var solveKey: some View {
        Button { onKey(.solve) } label: {
            VStack(spacing: 2) {
                Text("Solve").font(.headline)
                Text(solveTargetName).font(.caption).opacity(0.8)
            }
            .foregroundStyle(Par.Palette.onAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: Par.Metrics.minHitTarget + 6)
            .background(
                RoundedRectangle(cornerRadius: Par.Metrics.keyRadius, style: .continuous)
                    .fill(Par.Palette.accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keypad.solve")
        .accessibilityLabel("Solve for \(solveTargetName)")
    }

    private func legend(_ key: Key) -> String {
        switch key {
        case .digit(let d): return String(d)
        case .decimal: return "."
        case .sign: return "±"
        case .backspace: return "⌫"
        case .clearEntry: return "CE"
        case .solve: return "Solve"
        }
    }

    private func identifier(_ key: Key) -> String {
        switch key {
        case .digit(let d): return "digit.\(d)"
        case .decimal: return "decimal"
        case .sign: return "sign"
        case .backspace: return "backspace"
        case .clearEntry: return "clearEntry"
        case .solve: return "solve"
        }
    }

    private func spokenLabel(_ key: Key) -> String {
        switch key {
        case .digit(let d): return String(d)
        case .decimal: return "decimal point"
        case .sign: return "change sign"
        case .backspace: return "delete last digit"
        case .clearEntry: return "clear entry"
        case .solve: return "Solve for \(solveTargetName)"
        }
    }
}
