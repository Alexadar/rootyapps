import SwiftUI
import UniformTypeIdentifiers
import DocumentModelKit

// Library — the archive is the centre of gravity; capture is one of several ways in.
struct LibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var summaries: [DocumentSummary] = []
    @State private var kindFilter: DocumentKind?
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var openDocumentID: UUID?
    @State private var importing = false

    private var filtered: [DocumentSummary] {
        kindFilter.map { k in summaries.filter { $0.kind == k } } ?? summaries
    }

    var body: some View {
        ScrollView {
            if summaries.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)],
                          spacing: 16) {
                    ForEach(filtered) { doc in
                        tile(doc)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Library")
        .navigationDestination(item: $openDocumentID) { id in
            DocumentView(documentID: id)
        }
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selection.isEmpty { bulkBar }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: FileImportValidator.acceptedTypes,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importing = true
            Task {
                await env.importService.importFiles(urls: urls)
                importing = false
            }
        }
#if os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraScanView { pages in
                guard !pages.isEmpty else { return }
                importing = true
                Task {
                    await env.importService.importScan(pages: pages)
                    importing = false
                }
            }
            .ignoresSafeArea()
        }
#endif
        .overlay(alignment: .bottom) {
            if importing {
                Label("Reading document\u{2026}", systemImage: "doc.viewfinder")
                    .padding(12)
                    .glassEffect(in: .capsule)
                    .padding(.bottom, 70)
            }
        }
        .task { await refresh(); await observe() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Kind", selection: $kindFilter) {
                    Text("All").tag(DocumentKind?.none)
                    ForEach(DocumentKind.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName)
                            .tag(DocumentKind?.some(kind))
                    }
                }
            } label: {
                Label("Kind", systemImage: kindFilter?.symbolName ?? "square.grid.2x2")
            }
            .accessibilityIdentifier("library.kindFilter")

            Button(selecting ? "Done" : "Select") {
                selecting.toggle()
                if !selecting { selection.removeAll() }
            }
            .accessibilityIdentifier("library.select")

            Menu {
#if os(iOS)
                if CameraScanView.isSupported {
                    Button { showCamera = true } label: {
                        Label("Scan with Camera", systemImage: "doc.viewfinder")
                    }
                }
#endif
                Button { showFileImporter = true } label: {
                    Label("Import Files\u{2026}", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("library.bringIn")
        }
    }

    private func tile(_ doc: DocumentSummary) -> some View {
        Button {
            if selecting {
                if selection.contains(doc.id) { selection.remove(doc.id) }
                else { selection.insert(doc.id) }
            } else {
                openDocumentID = doc.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                ThumbnailView(documentID: doc.id)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                Text(doc.title)
                    .font(.headline).lineLimit(1)
                    .accessibilityIdentifier("library.tile.title.\(doc.id.uuidString)")
                HStack(spacing: 4) {
                    Image(systemName: doc.kind.symbolName).font(.caption2)
                    Text(doc.kind.displayName)
                    Text("\u{00B7}")
                    Text(meta(doc))
                }
                .font(.footnote).foregroundStyle(.secondary)
                if doc.unresolvedReviewCount > 0 {
                    Label("Review \u{00B7} \(doc.unresolvedReviewCount) item(s)",
                          systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GS.flagText)
                        .accessibilityIdentifier("library.tile.review.\(doc.id.uuidString)")
                }
            }
            .padding(14)
            .background(GS.surface, in: .rect(cornerRadius: GS.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: GS.tileRadius)
                .strokeBorder(selection.contains(doc.id) ? GS.tint : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var bulkBar: some View {
        GlassEffectContainer {
            HStack(spacing: 22) {
                Text("\(selection.count) selected")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("library.bulk.count")
                Button("Delete", role: .destructive) {
                    let ids = Array(selection)
                    selection.removeAll()
                    selecting = false
                    Task {
                        try? await env.store.delete(ids: ids)
                        await env.indexer.remove(ids: ids)
                    }
                }
                .accessibilityIdentifier("library.bulk.delete")
            }
            .padding(.horizontal, 22).frame(height: 52)
            .glassEffect(in: .capsule)
        }
        .padding(.bottom, 18)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "books.vertical")
        } description: {
            Text("Bring in a document to start: scan with the camera or import a PDF "
                 + "or photo. Everything stays on this device.")
        } actions: {
            Button("Import Files\u{2026}") { showFileImporter = true }
                .buttonStyle(.glassProminent)
        }
        .padding(.top, 80)
    }

    private func meta(_ doc: DocumentSummary) -> String {
        var parts: [String] = []
        if let d = doc.date {
            parts.append(d.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("\(doc.pageCount) page(s)")
        if doc.tableCount > 0 { parts.append("\(doc.tableCount) table(s)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func refresh() async {
        summaries = (try? await env.store.summaries()) ?? []
        resolveDeepLink()
    }

    private func observe() async {
        for await _ in await env.store.changes() {
            summaries = (try? await env.store.summaries()) ?? []
            // Async imports (GRIDSCAN_IMPORT hook) land after first render; keep
            // resolving the doc deep link until its target exists.
            resolveDeepLink()
        }
    }

    private func resolveDeepLink() {
        guard openDocumentID == nil,
              let slug = LaunchOverride.value("GRIDSCAN_DOC") else { return }
        openDocumentID = summaries.first {
            $0.title.localizedCaseInsensitiveContains(slug)
        }?.id
    }
}

/// Paper reads as paper — never glass. Falls back to a kind glyph when no render exists
/// (fixture documents have no page images).
struct ThumbnailView: View {
    let documentID: UUID
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.9))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .task {
            if let url = PageImageStore.thumbnailURL(documentID: documentID, index: 0) {
                image = ImportService.loadCGImage(url)
            }
        }
    }
}
