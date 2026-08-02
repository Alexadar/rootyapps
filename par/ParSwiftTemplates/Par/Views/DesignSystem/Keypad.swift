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
        Grid(horizontalSpacing: 7, verticalSpacing: 7) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        keyView(key)
                    }
                }
            }
            if columns == 3 {
                GridRow {
                    solveKey.gridCellColumns(3)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
    }

    private var rows: [[Key]] {
        columns == 4
            ? [[.digit(7), .digit(8), .digit(9), .backspace],
               [.digit(4), .digit(5), .digit(6), .clearEntry],
               [.digit(1), .digit(2), .digit(3), .solve],
               [.digit(0), .decimal, .sign]]
            : [[.digit(7), .digit(8), .digit(9)],
               [.digit(4), .digit(5), .digit(6)],
               [.digit(1), .digit(2), .digit(3)],
               [.digit(0), .decimal, .backspace]]
    }

    @ViewBuilder
    private func keyView(_ key: Key) -> some View {
        if case .solve = key {
            solveKey.gridCellRows(2)
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
