import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// The tape is a first-class surface, not a history drawer.
///
/// A list of rows, never a text blob. Each row: optional label, inputs collapsed
/// to one line, result as the emphasised number in its own column. Rows are
/// independent solves — there is no running total, and cross-line arithmetic is
/// explicitly out of scope.
public struct TapeView: View {
    @Binding private var document: TapeDocument
    @State private var editingRowID: TapeRow.ID?
    @State private var share: ShareItem?
    /// Non-nil when the tape is presented modally (iPhone). Beside the calculator on iPad there is
    /// nothing to dismiss, so no button appears.
    private let onClose: (() -> Void)?

    public init(document: Binding<TapeDocument>, onClose: (() -> Void)? = nil) {
        self._document = document
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if document.rows.isEmpty {
                emptyState
            } else {
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
            }

            footer
        }
        .background(Par.Palette.base)
        .sheet(item: $share) { item in
            ExportSheet(item: item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(Par.Palette.labelQuaternary)
            Text("Nothing on the tape yet")
                .font(.headline)
                .foregroundStyle(Par.Palette.labelSecondary)
            Text("Solve anything and the answer lands here — labelled, editable, and saved with this document.")
                .font(.subheadline)
                .foregroundStyle(Par.Palette.labelTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tape.empty")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(document.title).font(.title3.weight(.semibold)).foregroundStyle(Par.Palette.label)
                Text("\(document.rows.count) solves · appends automatically")
                    .font(.caption).foregroundStyle(Par.Palette.labelSecondary)
            }
            Spacer()
            if let onClose {
                Button("Done", action: onClose)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Par.Palette.accent)
                    .accessibilityIdentifier("tape.done")
            }
        }
        .padding(.horizontal, Par.Metrics.gutter)
        .padding(.vertical, 12)
    }

    /// Print and export are visible affordances, not buried in a share sheet. This is the single
    /// most explicit unmet ask in the category — _"I would give much to have a calculator from which
    /// I could print the tape."_ Both routes render from `TapeExport`, which resolves every line
    /// through `TapeSolver`, so the paper and the screen cannot disagree.
    private var footer: some View {
        HStack(spacing: 8) {
            Button("Print tape") { printTape() }
                .accessibilityIdentifier("tape.print")
            Button("Text") { share = ShareItem(text: TapeExport.plainText(document),
                                               suggestedName: fileName(extension: "txt")) }
                .accessibilityIdentifier("tape.exportText")
            Button("CSV") { share = ShareItem(text: TapeExport.csv(document),
                                              suggestedName: fileName(extension: "csv")) }
                .accessibilityIdentifier("tape.exportCSV")
        }
        .disabled(document.rows.isEmpty)
        .buttonStyle(SecondaryButtonStyle())
        .padding(.horizontal, Par.Metrics.gutter)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Par.Palette.separator).frame(height: 0.5) }
    }

    private func fileName(extension ext: String) -> String {
        let base = document.title.isEmpty ? "Tape" : document.title
        return base.replacingOccurrences(of: "/", with: "-") + "." + ext
    }

    /// System print, so the sheet a professional hands to a client comes out of the same code path
    /// the screen renders from. The platform handling lives in `PlainTextPrinter` because the
    /// amortization schedule prints the same way, and because the iPad presentation is a trap.
    private func printTape() {
        PlainTextPrinter.print(TapeExport.plainText(document), jobName: document.title)
    }
}

/// A text export on its way to the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
    let suggestedName: String

    /// Written to a temporary file so the share sheet offers "Save to Files" and mail attachment
    /// rather than only pasteboard text.
    var fileURL: URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

struct ExportSheet: View {
    let item: ShareItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(item.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(Par.Palette.label)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Par.Metrics.gutter)
            }
            .background(Par.Palette.base)
            .navigationTitle(item.suggestedName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let url = item.fileURL {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("tape.share")
                    }
                }
            }
        }
        .parAppearance()
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
