import SwiftUI

/// The tape is a first-class surface, not a history drawer.
///
/// A list of rows, never a text blob. Each row: optional label, inputs collapsed
/// to one line, result as the emphasised number in its own column. Rows are
/// independent solves — there is no running total, and cross-line arithmetic is
/// explicitly out of scope.
public struct TapeView: View {
    @Binding private var document: TapeDocument
    @State private var editingRowID: TapeRow.ID?

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach($document.rows) { $row in
                    TapeRowView(row: $row, isEditing: editingRowID == row.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Par.Palette.separator)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // A row is editable in place. Nothing else on the
                            // tape moves.
                            editingRowID = editingRowID == row.id ? nil : row.id
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            footer
        }
        .background(Par.Palette.base)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(document.title).font(.title3.weight(.semibold)).foregroundStyle(Par.Palette.label)
                Text("\(document.rows.count) solves · appends automatically")
                    .font(.caption).foregroundStyle(Par.Palette.labelSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Par.Metrics.gutter)
        .padding(.vertical, 12)
        .accessibilityIdentifier("tape.header")
    }

    /// Print and export are visible affordances, not buried in a share sheet.
    private var footer: some View {
        HStack(spacing: 8) {
            Button("Print tape") {}
                .accessibilityIdentifier("tape.print")
            Button("Text") {}
                .accessibilityIdentifier("tape.exportText")
            Button("CSV") {}
                .accessibilityIdentifier("tape.exportCSV")
        }
        .buttonStyle(SecondaryButtonStyle())
        .padding(.horizontal, Par.Metrics.gutter)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Par.Palette.separator).frame(height: 0.5) }
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(Par.Palette.label)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Par.Metrics.minHitTarget - 8)
            .background(
                RoundedRectangle(cornerRadius: Par.Metrics.controlRadius, style: .continuous)
                    .fill(Par.Palette.surfaceRaised.opacity(configuration.isPressed ? 0.9 : 0.55))
            )
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Par.Palette.onAccent)
            .padding(.horizontal, 14)
            .frame(minHeight: Par.Metrics.minHitTarget - 8)
            .background(
                RoundedRectangle(cornerRadius: Par.Metrics.controlRadius, style: .continuous)
                    .fill(Par.Palette.accent.opacity(configuration.isPressed ? 0.85 : 1))
            )
    }
}

#Preview("Tape") {
    TapeView(document: .constant(TapeDocument(
        title: "Refi comparison — Alvarez",
        rows: [
            TapeRow(label: "123 Oak St — 30yr", inputs: .tvm(TVMInputs(
                periods: 360, annualRatePct: 6.25, presentValue: 420_000,
                payment: 0, futureValue: 0, solveFor: "payment"))),
            TapeRow(label: "123 Oak St — 15yr", inputs: .tvm(TVMInputs(
                periods: 180, annualRatePct: 5.75, presentValue: 420_000,
                payment: 0, futureValue: 0, solveFor: "payment"))),
            TapeRow(label: "", inputs: .damaged(DamagedLine(
                toolName: "Amort",
                reason: "periods must be finite and ≥ 0",
                rawSummary: "Amort · n −12 · i 6.25 · PV 420,000")))
        ]
    )))
    .parAppearance()
}
