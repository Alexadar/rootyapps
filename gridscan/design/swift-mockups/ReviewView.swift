import SwiftUI

// Review pass — the quality surface. No arithmetic checking anywhere:
// quality means the structure is complete and well-formed.
struct ReviewView: View {
    @State private var model: ReviewModel
    @State private var selectedCell: CellAddress?

    init(document: Document) { _model = State(initialValue: ReviewModel(document: document)) }

    var body: some View {
        HSplitOrVStack { // side-by-side on iPad/Mac, stacked on iPhone — same structure
            DataGridView(table: model.table, selectedCell: $selectedCell)
            SourcePageView(page: model.pageFor(selectedCell), highlight: model.regionFor(selectedCell))
                // every value traces to the page region it was read from
        }
        .safeAreaInset(edge: .bottom) {
            if let item = model.currentAttentionItem {
                InlineFixBar(item: item) { fixed in
                    model.apply(fixed)   // corrections stick; state clears wherever the doc appears
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if model.remainingCount > 0 {
                    Label("Review · \(model.remainingCount) items", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(GS.flagText)
                }
            }
        }
        // Repeated same-source corrections teach the layout — visibly, never silently:
        .overlay(alignment: .bottom) {
            if let learned = model.newlyLearnedLayout {
                LearnedLayoutBanner(source: learned.sourceName) // "View" -> list with per-mapping Remove
            }
        }
    }
}

struct InlineFixBar: View {
    let item: AttentionItem
    let onFix: (String) -> Void
    @State private var value = ""

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(item.title, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(GS.flagText)
                    Text(item.detail) // e.g. Read as “l4 Mar 2O26” · from page 2, row 12
                        .font(.footnote).foregroundStyle(.secondary)
                }
                TextField("Value", text: $value).textFieldStyle(.roundedBorder)
                Button("Fix") { onFix(value) }.buttonStyle(.glassProminent)
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: GS.sheetRadius))
        }
        .padding()
    }
}
