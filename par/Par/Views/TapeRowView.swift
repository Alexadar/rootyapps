import SwiftUI


/// One solved problem, on one line.
public struct TapeRowView: View {
    @Binding private var row: TapeRow
    private let isEditing: Bool

    public init(row: Binding<TapeRow>, isEditing: Bool) {
        self._row = row
        self.isEditing = isEditing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isEditing ? 9 : 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    labelView
                    Text(inputSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(Par.Palette.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(resultName).font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
                    Text(resultValue)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Par.Palette.label)
                        .accessibilityIdentifier("tape.row.result.\(row.id.uuidString)")
                }
            }

            if isEditing { editor }
        }
        .padding(.vertical, 4)
        .background(isEditing ? Par.Palette.accentTint : .clear)
        .overlay(alignment: .leading) {
            if isEditing { Rectangle().fill(Par.Palette.accent).frame(width: 2.5) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tape.row.\(row.id.uuidString)")
    }

    @ViewBuilder
    private var labelView: some View {
        if row.label.isEmpty {
            Text("no label").font(.subheadline.italic()).foregroundStyle(Par.Palette.labelTertiary)
        } else {
            Text(row.label).font(.subheadline.weight(.semibold)).foregroundStyle(Par.Palette.label)
                .lineLimit(isEditing ? nil : 1)
        }
    }

    /// Editing a row re-solves that row only.
    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Label this solve", text: $row.label)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Par.Palette.label)
                .accessibilityIdentifier("tape.row.label.\(row.id.uuidString)")

            if case .damaged(let damaged) = row.inputs {
                FailureNotice(
                    title: "This line can’t be read back",
                    detail: "\(damaged.reason) The rest of the tape is intact. Par will not guess a value, and it will not delete your line.",
                    technical: damaged.rawSummary,
                    identifier: "tape.row.damaged.\(row.id.uuidString)",
                    isWarning: true
                )
            } else {
                Text("Renaming a line changes only this line. The inputs are kept exactly as solved, and the result is re-derived from them every time the tape is opened.")
                    .font(.caption)
                    .foregroundStyle(Par.Palette.labelSecondary)
            }
        }
    }

    // MARK: - Presentation. Re-derived, never cached.
    //
    // Every row type resolves through the same engine the export and the printed sheet use, so a
    // line cannot read one way on screen and another on paper.

    private var inputSummary: String { TapeExport.summary(of: row) }

    private var solved: TapeSolver.Result { TapeSolver.result(for: row.inputs) }

    private var resultName: String { solved.name }

    private var resultValue: String { solved.formatted }
}
