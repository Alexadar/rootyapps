import SwiftUI
import UniformTypeIdentifiers
import DocumentModelKit

// The document surface IS the review surface: grid + the page region every value was
// read from, side-by-side on iPad/Mac, stacked on iPhone. No arithmetic anywhere —
// quality means the structure is complete and well-formed.
struct DocumentView: View {
    let documentID: UUID
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var stored: StoredDocument?
    @State private var selectedCell: CellAddress?
    @State private var exportKind: ExportKind?
    @State private var showJoinSplit = false

    var body: some View {
        Group {
            if let stored {
                content(stored)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(stored?.summary.title ?? "")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $showJoinSplit) {
            if let stored {
                JoinSplitView(stored: stored) { await refresh() }
                    .environmentObject(env)
            }
        }
        .fileExporter(isPresented: exportPresented,
                      document: exportDocument,
                      contentType: exportKind == .xlsxFile
                          ? UTType(filenameExtension: "xlsx") ?? .data
                          : .commaSeparatedText,
                      defaultFilename: exportDocument?.payload.suggestedName) { result in
            if case .success(let url) = result, let stored, let kind = exportKind {
                Task {
                    await env.exportService.recordExport(of: stored, kind: kind,
                                                         destination: url.lastPathComponent)
                }
            }
            exportKind = nil
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private func content(_ stored: StoredDocument) -> some View {
        let wide = isWide
        let grid = gridColumn(stored)
        let source = SourcePageView(stored: stored, selectedCell: selectedCell)
        Group {
            if wide {
                HStack(spacing: 0) {
                    grid.frame(maxWidth: .infinity)
                    Divider()
                    source.frame(width: 320)
                }
            } else {
                VStack(spacing: 0) {
                    grid.frame(maxHeight: .infinity)
                    if selectedCell != nil {
                        Divider()
                        source.frame(height: 220)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let flag = currentAttentionFlag(stored) {
                InlineFixBar(flag: flag) { newValue in
                    await fix(flag, with: newValue)
                } onDismiss: {
                    Task {
                        try? await env.store.resolveFlag(id: flag.id, dismiss: true)
                        await refresh()
                    }
                }
            }
        }
    }

    private func gridColumn(_ stored: StoredDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(stored.document.pages) { page in
                    if stored.document.pages.count > 1 {
                        Text("Page \(page.index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    ForEach(page.tables) { table in
                        DataGridView(documentID: documentID, pageIndex: page.index,
                                     table: table, flags: stored.flags,
                                     selectedCell: $selectedCell)
                            .padding(.horizontal, 12)
                    }
                    if !page.looseText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(page.looseText) { span in
                                Text(span.text)
                                    .font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .background(GS.surface, in: .rect(cornerRadius: GS.tileRadius))
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let stored, stored.summary.unresolvedReviewCount > 0 {
                Label("Review \u{00B7} \(stored.summary.unresolvedReviewCount)",
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(GS.flagText)
                    .accessibilityIdentifier("doc.reviewBadge")
            }
            if (stored?.document.pages.count ?? 0) > 1 {
                Button { showJoinSplit = true } label: {
                    Label("Join & Split", systemImage: "square.split.1x2")
                }
                .accessibilityIdentifier("doc.joinSplit")
            }
            Menu {
                ForEach(ExportKind.allCases) { kind in
                    Button(kind.displayName) { exportKind = kind }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("doc.export")
            .disabled((stored?.document.allTables.isEmpty) ?? true)
        }
    }

    // MARK: export plumbing

    private var exportPresented: Binding<Bool> {
        Binding(get: { exportKind != nil }, set: { if !$0 { exportKind = nil } })
    }

    private var exportDocument: ExportFileDocument? {
        guard let stored, let kind = exportKind else { return nil }
        return ExportFileDocument(payload: env.exportService.payload(for: stored, kind: kind))
    }

    // MARK: state

    private var isWide: Bool {
#if os(macOS)
        true
#else
        hSize == .regular
#endif
    }

    private func currentAttentionFlag(_ stored: StoredDocument) -> ReviewFlag? {
        stored.flags.first { $0.status == .open }
    }

    private func fix(_ flag: ReviewFlag, with newValue: String) async {
        switch flag.address {
        case .cell(let address):
            try? await env.store.apply(Correction(documentID: documentID,
                                                  address: address, newText: newValue))
        case .span:
            try? await env.store.resolveFlag(id: flag.id, dismiss: false)
        }
        await refresh()
    }

    private func refresh() async {
        stored = try? await env.store.storedDocument(id: documentID)
    }
}

/// Wraps export bytes for fileExporter.
struct ExportFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = []
    static let writableContentTypes: [UTType] = [.commaSeparatedText, .data]

    let payload: ExportPayload

    init(payload: ExportPayload) { self.payload = payload }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: payload.data)
    }
}

/// Every value traces to the page region it was read from. Fixture documents have no
/// page render; the reduced state says so instead of pretending.
struct SourcePageView: View {
    let stored: StoredDocument
    let selectedCell: CellAddress?
    @State private var image: CGImage?
    @State private var loadedPage: Int = -1

    private var highlight: BBox? {
        guard let a = selectedCell else { return nil }
        return stored.document.cell(at: a)?.prov.first?.bbox
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image {
                GeometryReader { geo in
                    let fit = fittedRect(imageSize: CGSize(width: image.width,
                                                           height: image.height),
                                         in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .offset(x: fit.minX, y: fit.minY)
                        if let b = highlight {
                            Rectangle()
                                .strokeBorder(GS.tint, lineWidth: 2)
                                .background(GS.tint.opacity(0.12))
                                .frame(width: fit.width * b.width,
                                       height: fit.height * b.height)
                                .offset(x: fit.minX + fit.width * b.x,
                                        y: fit.minY + fit.height * b.y)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No page image", systemImage: "doc.text.image")
                } description: {
                    Text(selectedCell == nil
                         ? "Select a value to see where it was read from."
                         : "This document has no stored page render.")
                }
            }
        }
        .padding(8)
        .task(id: selectedCell?.pageIndex) { await load() }
    }

    private func load() async {
        let page = selectedCell?.pageIndex ?? 0
        guard page != loadedPage else { return }
        loadedPage = page
        if let url = PageImageStore.pageURL(documentID: stored.summary.id, index: page) {
            image = ImportService.loadCGImage(url)
        } else {
            image = nil
        }
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// The inline fix bar: shows what was read, takes the correction. Corrections stick;
/// state clears wherever the document appears.
struct InlineFixBar: View {
    let flag: ReviewFlag
    let onFix: (String) async -> Void
    let onDismiss: () -> Void
    @State private var value = ""

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(flag.reason.spokenDescription,
                          systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GS.flagText)
                    if let original = flag.originalText {
                        Text(original)
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("review.fix.original")
                    }
                }
                TextField("Corrected value", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("review.fix.field")
                Button("Fix") {
                    let v = value
                    Task { await onFix(v) }
                }
                .buttonStyle(.glassProminent)
                .disabled(value.isEmpty)
                .accessibilityIdentifier("review.fix.commit")
                Button("Keep as read", action: onDismiss)
                    .accessibilityIdentifier("review.fix.dismiss")
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: GS.sheetRadius))
        }
        .padding()
    }
}
