import SwiftUI

// Library — the home screen on every platform. The archive is the centre
// of gravity; capture is just one of several ways in.
struct LibraryView: View {
    @State private var selection = Set<Document.ID>()
    @State private var selecting = false
    @State private var kindFilter: DocumentKind?   // nil = all; kind is a tier-one filter
    let documents: [Document]   // sample data lives in SampleData.swift — EXAMPLES ONLY

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                ForEach(documents) { doc in
                    DocumentTile(document: doc, selected: selection.contains(doc.id))
                        .onTapGesture { if selecting { toggle(doc.id) } }
                }
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Structural-kind filter — layout shape, never content meaning.
                Menu {
                    Picker("Kind", selection: $kindFilter) {
                        Text("All").tag(DocumentKind?.none)
                        ForEach(DocumentKind.allCases, id: \.self) { kind in
                            Label(kind.rawValue.capitalized, systemImage: kind.symbolName)
                                .tag(DocumentKind?.some(kind))
                        }
                    }
                } label: {
                    Label("Kind", systemImage: kindFilter?.symbolName ?? "square.grid.2x2")
                }
                .buttonStyle(.glass)
                Button(selecting ? "Done" : "Select") { selecting.toggle() }
                    .buttonStyle(.glass)
                Button { /* Bring In menu: Camera / Import Files / Watch a Folder */ } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selection.isEmpty { bulkBar }   // works on iPhone too — not Mac-only
        }
    }

    private var bulkBar: some View {
        GlassEffectContainer {
            HStack(spacing: 22) {
                Text("\(selection.count) selected").font(.subheadline.weight(.semibold))
                Button("Export") {}
                Button("Move") {}
                Button("Delete", role: .destructive) {}
            }
            .padding(.horizontal, 22).frame(height: 52)
            .glassEffect(in: .capsule)
        }
        .padding(.bottom, 18)
    }

    private func toggle(_ id: Document.ID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

// Tile: paper thumbnail + title + meta; flag and not-downloaded states travel with it.
struct DocumentTile: View {
    let document: Document
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ThumbnailView(document: document)  // paper reads as paper — never glass
                .frame(height: 104)
                .overlay(alignment: .topTrailing) {
                    if !document.isDownloaded {
                        Label("Tap to download", systemImage: "icloud.and.arrow.down")
                            .labelStyle(.iconOnly).padding(8)
                    }
                }
            Text(document.title).font(.headline).lineLimit(1)
            // Meta line leads with the structural kind (tier one, first-class).
            HStack(spacing: 4) {
                Image(systemName: document.kind.symbolName).font(.caption2)
                Text(document.kind.rawValue.capitalized)
                Text("·")
                Text(document.meta)
            }
            .font(.footnote).foregroundStyle(.secondary)
            if document.unresolvedReviewCount > 0 {
                Label("Review · \(document.unresolvedReviewCount) items", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GS.flagText)
                    .accessibilityLabel("\(document.unresolvedReviewCount) items need review")
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: GS.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: GS.tileRadius)
            .strokeBorder(selected ? GS.tint : .clear, lineWidth: 1.5))
    }
}
