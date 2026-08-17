import SwiftUI
import DocumentModelKit

// The two hard structural cases. Neither is hidden background behaviour: the app never
// joins or splits silently — it proposes, the user decides, and every decision is
// reversible and audited.
struct JoinSplitView: View {
    let stored: StoredDocument
    let onChange: () async -> Void
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var cuts: Set<Int> = []      // cut AFTER page index n

    var body: some View {
        NavigationStack {
            List {
                joinSection
                splitBackSection
                documentSplitSection
            }
            .navigationTitle("Join & Split")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: a) one table across many pages — the join is explicit

    private var seams: [(page: Int, columns: Int)] {
        var out: [(Int, Int)] = []
        let pages = stored.document.pages
        for i in 0..<max(pages.count - 1, 0) {
            guard let last = pages[i].tables.last,
                  let next = pages[i + 1].tables.first,
                  last.columnCount == next.columnCount, last.columnCount > 0
            else { continue }
            out.append((i, last.columnCount))
        }
        return out
    }

    @ViewBuilder
    private var joinSection: some View {
        if !seams.isEmpty {
            Section("Tables continuing across pages") {
                ForEach(seams, id: \.page) { seam in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Page \(seam.page + 1) \u{2192} \(seam.page + 2)")
                                .font(.subheadline.weight(.semibold))
                            Text("Same \(seam.columns) columns on both pages")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Join") { join(at: seam.page) }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("joinsplit.join.\(seam.page)")
                    }
                }
            }
        }
    }

    private func join(at pageIndex: Int) {
        var doc = stored.document
        guard doc.pages.indices.contains(pageIndex + 1),
              var lower = doc.pages[pageIndex].tables.popLast(),
              !doc.pages[pageIndex + 1].tables.isEmpty else { return }
        let upper = doc.pages[pageIndex + 1].tables.removeFirst()
        // Rows keep their original per-page provenance — that is what makes the join
        // reversible and every value still traceable to its own page.
        lower = Table(id: lower.id, normalizing: lower.rows + upper.rows)
        doc.pages[pageIndex].tables.append(lower)
        commit(doc, title: "Joined a table across pages \(pageIndex + 1)\u{2013}\(pageIndex + 2)",
               lines: ["\(lower.rowCount) rows \u{00B7} \(lower.columnCount) columns"])
    }

    // MARK: joined tables — split back at the page boundary

    private var joinedTables: [(pageIndex: Int, table: DocumentModelKit.Table)] {
        stored.document.pages.flatMap { page in
            page.tables.compactMap { table in
                pageIndexes(of: table).count > 1 ? (page.index, table) : nil
            }
        }
    }

    @ViewBuilder
    private var splitBackSection: some View {
        if !joinedTables.isEmpty {
            Section("Joined tables") {
                ForEach(joinedTables, id: \.table.id) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Table on page \(entry.pageIndex + 1)")
                                .font(.subheadline.weight(.semibold))
                            Text("Rows from pages "
                                 + pageIndexes(of: entry.table).sorted()
                                     .map { String($0 + 1) }.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Split here") { splitBack(entry.table) }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private func pageIndexes(of table: DocumentModelKit.Table) -> Set<Int> {
        Set(table.rows.flatMap { $0 }.flatMap(\.prov).map(\.pageIndex))
    }

    private func splitBack(_ table: DocumentModelKit.Table) {
        var doc = stored.document
        for (p, page) in doc.pages.enumerated() {
            guard let t = page.tables.firstIndex(where: { $0.id == table.id }) else { continue }
            var byPage: [Int: [[Cell]]] = [:]
            for row in table.rows {
                let rowPage = row.flatMap(\.prov).first?.pageIndex ?? page.index
                byPage[rowPage, default: []].append(row)
            }
            doc.pages[p].tables.remove(at: t)
            for (targetPage, rows) in byPage.sorted(by: { $0.key < $1.key }) {
                let rebuilt = Table(normalizing: rows)
                if let target = doc.pages.firstIndex(where: { $0.index == targetPage }) {
                    doc.pages[target].tables.append(rebuilt)
                } else {
                    doc.pages[p].tables.insert(rebuilt, at: t)
                }
            }
        }
        commit(doc, title: "Split a joined table back to its pages", lines: [])
    }

    // MARK: b) many documents in one file — manual page-boundary cuts

    private var segments: [[Int]] {
        let count = stored.document.pages.count
        var out: [[Int]] = [[]]
        for i in 0..<count {
            out[out.count - 1].append(i)
            if cuts.contains(i), i < count - 1 { out.append([]) }
        }
        return out
    }

    @ViewBuilder
    private var documentSplitSection: some View {
        if stored.document.pages.count > 1 {
            Section("Split into separate documents") {
                ForEach(0..<stored.document.pages.count - 1, id: \.self) { boundary in
                    Toggle(isOn: Binding(
                        get: { cuts.contains(boundary) },
                        set: { on in if on { cuts.insert(boundary) } else { cuts.remove(boundary) } }
                    )) {
                        Text("Cut after page \(boundary + 1)")
                    }
                    .accessibilityIdentifier("joinsplit.cut.\(boundary)")
                }
                if !cuts.isEmpty {
                    Button("Split into \(segments.count) documents") { splitDocument() }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("joinsplit.commit")
                }
                Button("Keep as one document") { cuts.removeAll() }
                    .disabled(cuts.isEmpty)
            }
        }
    }

    private func splitDocument() {
        let source = stored
        let parts = segments
        Task {
            for (n, pageIndices) in parts.enumerated() {
                let newID = UUID()
                let pages: [Page] = pageIndices.enumerated().map { newIndex, oldIndex in
                    remap(source.document.pages[oldIndex], to: newIndex)
                }
                let doc = ScanDocument(id: newID,
                                       title: "\(source.summary.title) \u{2014} part \(n + 1)",
                                       date: source.document.date,
                                       kind: source.document.kind,
                                       pages: pages)
                PageImageStore.copyPages(from: source.summary.id,
                                         pageIndices: pageIndices, to: newID)
                _ = try? await env.store.create(doc, flags: [], source: .file, detailLines: [
                    "Split from \u{201C}\(source.summary.title)\u{201D} "
                    + "(pages \(pageIndices.map { String($0 + 1) }.joined(separator: ", ")))",
                ])
            }
            try? await env.store.delete(ids: [source.summary.id])
            await onChange()
            dismiss()
        }
    }

    /// Re-index a page (and every provenance record inside it) for its new position.
    private func remap(_ page: Page, to newIndex: Int) -> Page {
        func remapProv(_ prov: [Provenance]) -> [Provenance] {
            prov.map { Provenance(pageIndex: newIndex, bbox: $0.bbox) }
        }
        let tables = page.tables.map { table in
            DocumentModelKit.Table(id: table.id, normalizing: table.rows.map { row in
                row.map { Cell($0.text, prov: remapProv($0.prov)) }
            })
        }
        let loose = page.looseText.map {
            TextSpan(id: $0.id, $0.text, prov: remapProv($0.prov))
        }
        return Page(id: page.id, index: newIndex, tables: tables, looseText: loose)
    }

    private func commit(_ doc: ScanDocument, title: String, lines: [String]) {
        Task {
            try? await env.store.update(doc, auditTitle: title, detailLines: lines)
            await onChange()
            dismiss()
        }
    }
}
