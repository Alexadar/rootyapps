import SwiftUI
import DocumentModelKit

// The structured-data grid. SCHEMA-AGNOSTIC BY DESIGN: columns are whatever the
// document contained — the product defines none of its own. The first row renders in
// header style because it IS the as-read first row, nothing more. Data is OPAQUE,
// never glass. Cell states derive from the flag sidecar — no confidence field exists.
struct DataGridView: View {
    let documentID: UUID
    let pageIndex: Int
    let table: DocumentModelKit.Table
    let flags: [ReviewFlag]
    @Binding var selectedCell: CellAddress?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            accessibilityRowList
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                grid
            }
            .background(GS.surface, in: .rect(cornerRadius: GS.tileRadius))
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<table.rowCount, id: \.self) { r in
                GridRow {
                    flagGutterDot(row: r)
                    ForEach(0..<table.columnCount, id: \.self) { c in
                        cellView(row: r, column: c)
                    }
                }
                .frame(minHeight: GS.gridRowHeight)
            }
        }
        .padding(.vertical, 6)
    }

    /// AX reflow: stacked field list per row — the grid never clips at accessibility
    /// type sizes. Field captions come from the as-read first row.
    private var accessibilityRowList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(1..<max(table.rowCount, 1), id: \.self) { r in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<table.columnCount, id: \.self) { c in
                        let header = table.rowCount > 0 ? table.rows[0][c].text : ""
                        VStack(alignment: .leading, spacing: 1) {
                            if !header.isEmpty {
                                Text(header.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            cellView(row: r, column: c)
                        }
                    }
                }
                .padding(10)
                .background(GS.surface, in: .rect(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func flagGutterDot(row: Int) -> some View {
        let rowFlagged = (0..<table.columnCount).contains { c in
            state(row: row, column: c).isFlagged
        }
        ZStack {
            Color.clear.frame(width: 30)
            if rowFlagged {
                Circle().fill(GS.flag).frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private func cellView(row r: Int, column c: Int) -> some View {
        let cell = table.rows[r][c]
        let address = CellAddress(documentID: documentID, pageIndex: pageIndex,
                                  tableID: table.id, row: r, column: c)
        let isSelected = selectedCell == address
        HStack(spacing: 5) {
            switch state(row: r, column: c) {
            case .plain:
                Text(cell.text)
                    .font(r == 0 ? .caption.weight(.semibold) : .callout)
                    .foregroundStyle(r == 0 ? .secondary : .primary)
            case .corrected(let was):
                Image(systemName: "pencil").font(.caption).foregroundStyle(GS.corrected)
                Text(cell.text)
                    .font(.callout.weight(.medium)).foregroundStyle(GS.corrected)
                    .accessibilityLabel("\(cell.text), corrected by you, was \(was)")
            case .flagged(let reason):
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(GS.flag)
                Text(cell.text)
                    .font(.callout)
                    .underline(color: GS.flag)   // glyph + underline — never color alone
                    .accessibilityLabel("\(cell.text), \(reason.spokenDescription)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 60, alignment: .leading)
        .background(isSelected ? GS.tint.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedCell = address }   // syncs the source-region highlight
        .accessibilityIdentifier("grid.cell.\(r).\(c)")
    }

    private func state(row r: Int, column c: Int) -> CellState {
        let match = flags.first {
            guard case .cell(let a) = $0.address else { return false }
            return a.tableID == table.id && a.row == r && a.column == c
        }
        guard let match else { return .plain }
        switch match.status {
        case .open: return .flagged(reason: match.reason)
        case .resolvedByCorrection:
            if let was = strippedOriginal(match.originalText) {
                return .corrected(was: was)
            }
            return .plain
        case .dismissed: return .plain
        }
    }

    /// originalText is stored presentation-ready ("Read as “x”"); recover the raw value.
    private func strippedOriginal(_ s: String?) -> String? {
        guard var s else { return nil }
        if s.hasPrefix("Read as ") { s.removeFirst("Read as ".count) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "\u{201C}\u{201D}"))
    }
}
