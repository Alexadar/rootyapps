import SwiftUI
import EphemerisKit

/// The export sheet.
///
/// ⚠️ **States what will happen before it happens.** The count and the date range are shown first,
/// and the share button is below them — so a user who expected forty events and is told four can
/// stop. An export that silently produced the wrong window would look identical to one that worked.
///
/// ⚠️ **Nothing uploads.** The file is written to the app's temporary directory and handed to the
/// system share sheet or save panel. There is no network call here and no account.
struct ExportSheet: View {
    let payload: ExportPayload

    init(payload: ExportPayload) {
        self.payload = payload
        // Start on a format this payload actually offers — defaulting to CSV for a chart would
        // present a format the picker then refuses to show.
        _format = State(initialValue: payload.availableFormats.first ?? .json)
    }

    @State private var format: ExportPayload.Format
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section("What will be exported") {
                    LabeledContent("Events") {
                        Text(payload.count, format: .number)
                            .monospacedDigit()
                            .accessibilityIdentifier("export.count")
                    }
                    LabeledContent("Range") {
                        Text(rangeText)
                            .font(.callout)
                            .accessibilityIdentifier("export.range")
                    }
                    if payload.isEmpty {
                        // An empty export is not an error, but writing an empty file without
                        // saying so is how someone emails a colleague a header row.
                        Text("Nothing falls in this range — the file would contain only its header.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("export.empty")
                    }
                }

                Section("Format") {
                    // A chart offers JSON only, so the control disappears rather than presenting
                    // a CSV that would be a flattened lookalike of the synced document.
                    if payload.availableFormats.count > 1 {
                        Picker("Format", selection: $format) {
                            ForEach(payload.availableFormats) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("export.format")
                    }
                    Text(payload.fileName(format))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("export.filename")
                }

                Section {
                    shareControl
                } footer: {
                    Text("Written to a temporary file and handed to your share sheet. Nothing is uploaded.")
                        .font(.footnote)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    private var rangeText: String {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        return "\(f.string(from: payload.range.start)) – \(f.string(from: payload.range.end))"
    }

    /// Writing eagerly would leave a temp file behind for a sheet the user only opened to read the
    /// count, so the file is produced when the control is built and any failure is surfaced rather
    /// than swallowed.
    @ViewBuilder private var shareControl: some View {
        if let url = try? payload.writeTemporary(format) {
            ShareLink(item: url) {
                Label("Export \(Text(format.label))", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier(payload.subject.identifier)

            // The event CSV carries stable numeric `code`s, which are unreadable without the table
            // that names them. Offering the file and withholding its key would hand someone a
            // spreadsheet of integers.
            if case .events = payload.content, let legend = try? payload.writeLegend(format) {
                ShareLink(item: legend) {
                    Label("Export code legend", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("export.legend")
            }
        } else {
            Text("Could not write the file.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("export.writeFailed")
        }
    }
}

/// The ⤴ toolbar button that opens it — one per exportable surface, never a submenu.
struct ExportToolbar: ViewModifier {
    let payload: () -> ExportPayload
    @State private var showing = false

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showing = true } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Export")
                    .accessibilityIdentifier("toolbar.export")
            }
        }
        .sheet(isPresented: $showing) { ExportSheet(payload: payload()) }
    }
}

extension View {
    /// `payload` is a closure so the events are resolved when the sheet opens, not when the
    /// toolbar is built — otherwise scrubbing the date would export a stale window.
    func exportToolbar(_ payload: @escaping () -> ExportPayload) -> some View {
        modifier(ExportToolbar(payload: payload))
    }
}
