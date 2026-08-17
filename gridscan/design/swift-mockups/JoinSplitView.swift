import SwiftUI

// The two hard structural cases. Neither is hidden background behaviour:
// when the app makes a structural decision the user sees it and can overrule it.

// a) One table across many pages — the join is an object with Split/Rejoin.
struct MultiPageJoinView: View {
    @State private var table: JoinedTable
    init(table: JoinedTable) { _table = State(initialValue: table) }

    var body: some View {
        VStack(spacing: 0) {
            PageStrip(pages: table.pages, seams: table.seams) // pinned; grid never unloads while paging
            List {
                ForEach(table.segments) { segment in
                    ForEach(segment.rows) { GridRowView(row: $0) }
                    if let seam = segment.trailingSeam {
                        SeamRow(seam: seam) { table.split(at: seam) }   // "Page 3 → 4 · joined" [Split here]
                    }
                    if let dropped = segment.droppedHeader {
                        DroppedHeaderRow(header: dropped) { table.reveal(dropped) } // shown, not hidden
                    }
                }
            }
        }
        // Splitting makes two tables; both offer Rejoin. Nothing joins silently.
    }
}

// b) Many documents in one file — proposed cuts the user drags, adds, removes.
struct DocumentSplitView: View {
    @State private var proposal: SplitProposal

    init(proposal: SplitProposal) { _proposal = State(initialValue: proposal) }

    var body: some View {
        VStack(spacing: 0) {
            CutFilmstrip(pages: proposal.pages, cuts: $proposal.cuts)
                // tap between pages to add a cut · drag a cut to move it
            List(proposal.segments) { segment in
                SegmentRow(segment: segment) { proposal.mergeWithPrevious(segment) }
            }
        }
        .navigationTitle("\(proposal.segments.count) documents proposed")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Keep as one document") { proposal.clearCuts() }.buttonStyle(.glass)
                Button("Split into \(proposal.segments.count)") { proposal.commit() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
