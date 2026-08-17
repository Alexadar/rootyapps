import SwiftUI
import UnitsKit

/// The shape every tool screen shares: a scrolling column of inputs and results, the elevation
/// chip and unit toggle in the toolbar, and the copy/export affordances the Mac needs.
///
/// Psychrometrics does not use this — its chart earns a layout of its own — but the other five
/// tools are all "some fields, then some numbers", and writing that five times would guarantee
/// five slightly different paddings.
struct ToolScaffold<Content: View>: View {

    let tool: Tool
    @Binding var showElevationSheet: Bool
    @ViewBuilder let content: () -> Content

    @Environment(AppSettings.self) private var settings
    @State private var rows: [ResultGrid.Row] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.s3) {
                content()
            }
            .padding(DS.s4)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(DS.breeze)
        .navigationTitle(tool.title)
        .onPreferenceChange(ResultRowsKey.self) { rows = $0 }
        .toolbar {
            ToolHeader(showElevationSheet: $showElevationSheet)
            ToolbarItem(placement: .secondaryAction) {
                ExportControls(tool: tool, rows: rows)
            }
        }
        .sheet(isPresented: $showElevationSheet) { ElevationSheet() }
        .onAppear { settings.noteOpened(tool) }
    }
}

/// Input fields, packed as many per row as will fit at a readable width.
///
/// An adaptive grid rather than `ViewThatFits(HStack, VStack)`. That pair is all-or-nothing: three
/// fields either sit in one row or become three stacked rows, and on a phone the stacked form
/// pushed the results of the mixing tool completely below the fold. Adaptive columns give the
/// answer that was actually wanted — two across on a phone, three on an iPad — from one rule.
struct FieldPair<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.s3, alignment: .top)],
                  alignment: .leading, spacing: DS.s3) {
            content()
        }
    }
}

/// A grid of computed values.
///
/// ## Identifiers go on the tiles, never on this grid
///
/// An `accessibilityIdentifier` on a container **overwrites every child's** (uitests.md §3, Trap 1),
/// so an earlier version of this view — which named the grid `"<tool>Results"` — made all of its
/// results unaddressable at once. Each tile is named instead: `<tool>.<slug>`, with the first
/// emphasised row also answering to `<tool>.hero` so a numeric check has one stable anchor per
/// tool.
struct ResultGrid: View {

    struct Row: Identifiable, Equatable {
        let title: String
        let value: Double
        let quantity: Quantity
        var emphasised = false
        var id: String { title }

        /// `Wet bulb` → `wetBulb`, for use in an accessibility identifier.
        var slug: String {
            let parts = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard let first = parts.first else { return "value" }
            return ([first.lowercased()] + parts.dropFirst().map(\.capitalized)).joined()
        }
    }

    let tool: Tool
    let rows: [Row]

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The row a numeric check should read: the first emphasised one, else the first.
    private var heroID: Row.ID? {
        (rows.first(where: \.emphasised) ?? rows.first)?.id
    }

    /// Results in a **non-lazy** grid.
    ///
    /// `LazyVGrid` never creates the rows that are off-screen, so they are absent from the
    /// accessibility tree entirely — not merely unhittable. On a phone the mixing tool's results
    /// sit below six input fields, and every assertion against them failed with "never appeared"
    /// while the app was perfectly correct. It is also an accessibility bug in its own right: a
    /// VoiceOver user swiping through the screen would not reach a result until it happened to be
    /// scrolled into view.
    ///
    /// There are at most nine tiles, so laziness was buying nothing to begin with.
    var body: some View {
        Grid(horizontalSpacing: DS.s2, verticalSpacing: DS.s2) {
            ForEach(Array(rows.chunked(into: columnCount).enumerated()), id: \.offset) { _, pair in
                GridRow {
                    ForEach(pair) { row in
                        tile(row)
                    }
                    // Keep the last row's single tile at column width rather than letting it
                    // stretch across both columns.
                    if pair.count < columnCount {
                        ForEach(0..<(columnCount - pair.count), id: \.self) { _ in
                            Color.clear.frame(height: 1)
                        }
                    }
                }
            }
        }
        // Publish upward so the toolbar's copy and export controls have something to work with,
        // without every tool having to hand its numbers to its own chrome.
        .preference(key: ResultRowsKey.self, value: rows)
    }

    /// Past XL a number and its label cannot both fit beside a neighbour, so the results become a
    /// single column rather than shrinking the type the user asked to enlarge.
    private var columnCount: Int { typeSize >= .accessibility1 ? 1 : 2 }

    private func tile(_ row: Row) -> some View {
        ResultTile(label: LocalizedStringKey(row.title),
                   spokenLabel: row.title,
                   value: Fmt.value(si: row.value, row.quantity, settings.unitSystem),
                   unit: row.quantity.symbol(settings.unitSystem),
                   spoken: Fmt.spoken(si: row.value, row.quantity, settings.unitSystem),
                   emphasised: row.emphasised)
            .accessibilityIdentifier("\(tool.rawValue).\(row.id == heroID ? "hero" : row.slug)")
    }
}

extension Array {
    /// Split into chunks of `size`, for laying rows out in a `Grid`.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}

/// Any Kit error, said plainly.
struct ErrorBanner: View {
    let error: Error

    var body: some View {
        StatusBanner(kind: .error, title: title, detail: detail)
            .accessibilityIdentifier("tool.error")
    }

    private var title: String {
        if let psychro = error as? PsychroErrorReadable { return psychro.readableTitle }
        return "That does not describe anything"
    }

    private var detail: String {
        if let psychro = error as? PsychroErrorReadable { return psychro.readableDetail }
        return String(describing: error)
    }
}

/// So `ErrorBanner` can prefer a Kit's own wording without importing every Kit.
protocol PsychroErrorReadable {
    var readableTitle: String { get }
    var readableDetail: String { get }
}
