import SwiftUI

// The structured-data grid. SCHEMA-AGNOSTIC BY DESIGN:
// columns are whatever the document contained — the grid never defines them.
// Sample headers in previews ("Sample ID", "Depth", "pH") are EXAMPLES ONLY
// and must not appear in the product unless a real document contains them.
struct DataGridView: View {
    let table: ExtractedTable
    @Binding var selectedCell: CellAddress?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // AX reflow: stacked field list per row — the grid never clips.
            AccessibilityRowList(table: table, selectedCell: $selectedCell)
        } else {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Color.clear.frame(width: 34) // flag gutter
                    ForEach(table.columns) { col in
                        Text(col.nameAsRead.uppercased())   // header as read, verbatim
                            .font(.caption2.weight(.semibold)).kerning(0.6)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                    }
                }
                ForEach(table.rows) { row in
                    GridRow {
                        FlagGutterDot(row: row)
                        ForEach(row.cells) { cell in
                            CellView(cell: cell, isSelected: selectedCell == cell.address)
                                .onTapGesture { selectedCell = cell.address } // syncs source-region highlight
                        }
                    }
                    .frame(minHeight: GS.gridRowHeight)
                }
            }
            .background(Color(.secondarySystemGroupedBackground)) // data is OPAQUE, never glass
        }
    }
}

struct CellView: View {
    let cell: ExtractedCell
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            switch cell.provenance {
            case .extracted:
                Text(cell.value)
            case .corrected(let was):
                Image(systemName: "pencil").font(.caption).foregroundStyle(GS.corrected)
                Text(cell.value).foregroundStyle(GS.corrected).fontWeight(.medium)
                    .accessibilityLabel("\(cell.value), corrected by you, was \(was)")
            case .flagged(let reason):
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(GS.flag)
                Text(cell.value).underline(color: GS.flag)   // glyph + underline — never color alone
                    .accessibilityLabel("\(cell.value), \(reason.spokenDescription)")
            case .missingRequired:
                Text("—").foregroundStyle(.tertiary)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(GS.flag, style: .init(lineWidth: 1, dash: [4])))
                    .accessibilityLabel("missing required field")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isSelected ? GS.tint.opacity(0.06) : .clear)
    }
}

extension FlagReason {
    var spokenDescription: String {
        switch self {
        case .failedFormatRule(let rule): return "failed format rule: \(rule)"
        case .lowOCRConfidence: return "low confidence text, verify against the page"
        }
    }
}
