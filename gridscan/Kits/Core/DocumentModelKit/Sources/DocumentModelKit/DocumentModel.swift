import Foundation

/// GridScan tier-one data model: a document database over ABSTRACT tabular data.
/// document → pages → tables (rows × columns of TEXT cells) → loose text spans,
/// plus title, date, structural kind. No commerce semantics anywhere in this Kit
/// (totals/vendors/amounts belong to a deferred sub-option and are not modeled here).
///
/// Pure, stateless value types. Codable — and the encoded field names ARE a public
/// contract (frozen by a golden-JSON test): anything serialized outward reuses them.
///
/// Citation addressability (tier-one obligation): every cell and every loose-text span
/// is addressable below the page and resolves back to page + bbox + coord_origin, so v2
/// passage retrieval can cite without re-modelling. Loose text is an ORDERED array —
/// reading order is free at model time and unreconstructable afterwards.

/// Structural kind of a scanned document. Describes layout shape, never content meaning.
public enum DocumentKind: String, Sendable, Codable, CaseIterable, Equatable {
    case table
    case form
    case report
}

/// Coordinate origin of a bounding box. PDF space is bottom-left; rendered images are
/// top-left. The mismatch mirrors layouts vertically without erroring, so every bbox
/// carries its origin explicitly. Raw values are frozen (storage format).
public enum CoordOrigin: String, Sendable, Codable, Equatable {
    case topLeft = "top-left"
    case bottomLeft = "bottom-left"
}

/// A bounding box in normalized page space, tagged with its coordinate origin.
public struct BBox: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var origin: CoordOrigin

    public init(x: Double, y: Double, width: Double, height: Double, origin: CoordOrigin) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.origin = origin
    }
}

/// Where a piece of text came from on the page. Self-contained (carries its page index)
/// so a copied-out chunk stays resolvable.
public struct Provenance: Sendable, Codable, Equatable {
    public var pageIndex: Int
    public var bbox: BBox

    public init(pageIndex: Int, bbox: BBox) {
        self.pageIndex = pageIndex
        self.bbox = bbox
    }
}

/// One table cell: text plus provenance. `prov` is an ARRAY — a cell may merge several
/// source regions (e.g. two OCR runs joined into one cell).
public struct Cell: Sendable, Codable, Equatable {
    public var text: String
    public var prov: [Provenance]

    public init(_ text: String, prov: [Provenance] = []) {
        self.text = text
        self.prov = prov
    }
}

/// One loose (non-tabular) text span, individually addressable for citation.
public struct TextSpan: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var prov: [Provenance]

    public init(id: UUID = UUID(), _ text: String, prov: [Provenance] = []) {
        self.id = id
        self.text = text
        self.prov = prov
    }
}

/// One table: a rectangular grid of cells. Invariant: every row has the same number of
/// columns (`columnCount`). Build via `init(normalizing:)` to guarantee it.
public struct Table: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public private(set) var rows: [[Cell]]

    public var rowCount: Int { rows.count }
    public var columnCount: Int { rows.first?.count ?? 0 }

    /// Text-only view of the grid — the export surface (CSV/XLSX take [[String]]).
    public var textRows: [[String]] { rows.map { $0.map(\.text) } }

    /// Pads ragged input rows with empty cells to the widest row. Never drops data.
    public init(id: UUID = UUID(), normalizing rawRows: [[Cell]]) {
        self.id = id
        let width = rawRows.map(\.count).max() ?? 0
        self.rows = rawRows.map { row in
            row + Array(repeating: Cell(""), count: width - row.count)
        }
    }

    /// Convenience for provenance-free construction (tests, manual entry).
    public init(id: UUID = UUID(), normalizing rawRows: [[String]]) {
        self.init(id: id, normalizing: rawRows.map { $0.map { Cell($0) } })
    }

    /// Rows/columns at the OUTER edges whose cells are all text-empty are removed;
    /// interior empty cells and interior empty rows/columns are preserved (they carry
    /// structure). Emptiness is judged on text only.
    public func trimmedEmptyEdges() -> Table {
        var r = rows
        func rowEmpty(_ row: [Cell]) -> Bool { row.allSatisfy { $0.text.isEmpty } }
        while let last = r.last, rowEmpty(last) { r.removeLast() }
        while let first = r.first, rowEmpty(first) { r.removeFirst() }
        if !r.isEmpty {
            func colEmpty(_ c: Int) -> Bool { r.allSatisfy { $0[c].text.isEmpty } }
            var lo = 0, hi = r[0].count
            while lo < hi, colEmpty(hi - 1) { hi -= 1 }
            while lo < hi, colEmpty(lo) { lo += 1 }
            r = r.map { Array($0[lo..<hi]) }
        }
        return Table(id: id, normalizing: r)
    }
}

/// One page of a document: zero or more tables plus loose text spans, both in reading
/// order (array order IS reading order — do not sort or set-ify).
public struct Page: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var index: Int
    public var tables: [Table]
    public var looseText: [TextSpan]

    public init(id: UUID = UUID(), index: Int, tables: [Table] = [],
                looseText: [TextSpan] = []) {
        self.id = id
        self.index = index
        self.tables = tables
        self.looseText = looseText
    }
}

/// Address of one cell, stable across Codable round-trips: positional within an
/// identified table. Resolves via `ScanDocument.cell(at:)`.
public struct CellAddress: Sendable, Codable, Equatable, Hashable {
    public var documentID: UUID
    public var pageIndex: Int
    public var tableID: UUID
    public var row: Int
    public var column: Int

    public init(documentID: UUID, pageIndex: Int, tableID: UUID, row: Int, column: Int) {
        self.documentID = documentID
        self.pageIndex = pageIndex
        self.tableID = tableID
        self.row = row
        self.column = column
    }
}

/// Address of one loose-text span. Resolves via `ScanDocument.span(at:)`.
public struct SpanAddress: Sendable, Codable, Equatable, Hashable {
    public var documentID: UUID
    public var pageIndex: Int
    public var spanID: UUID

    public init(documentID: UUID, pageIndex: Int, spanID: UUID) {
        self.documentID = documentID
        self.pageIndex = pageIndex
        self.spanID = spanID
    }
}

/// A scanned document. `date` is the document's own date if known (user-set or scan
/// metadata), not a processing timestamp.
public struct ScanDocument: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var date: Date?
    public var kind: DocumentKind
    public var pages: [Page]

    public init(id: UUID = UUID(), title: String, date: Date? = nil,
                kind: DocumentKind, pages: [Page] = []) {
        self.id = id
        self.title = title
        self.date = date
        self.kind = kind
        self.pages = pages
    }

    /// All tables across pages, in page order — the export surface.
    public var allTables: [Table] { pages.flatMap(\.tables) }

    /// Everything textual, in reading order — the (v2) chunking/search surface.
    public var allText: [String] {
        pages.flatMap { page in
            page.tables.flatMap { $0.textRows.flatMap { $0 } }
                + page.looseText.map(\.text)
        }.filter { !$0.isEmpty }
    }

    /// Resolve a citation address to its cell. Nil if the address does not belong to
    /// this document or no longer exists.
    public func cell(at a: CellAddress) -> Cell? {
        guard a.documentID == id,
              let page = pages.first(where: { $0.index == a.pageIndex }),
              let table = page.tables.first(where: { $0.id == a.tableID }),
              table.rows.indices.contains(a.row),
              table.rows[a.row].indices.contains(a.column)
        else { return nil }
        return table.rows[a.row][a.column]
    }

    /// Resolve a citation address to its loose-text span. Nil if absent.
    public func span(at a: SpanAddress) -> TextSpan? {
        guard a.documentID == id,
              let page = pages.first(where: { $0.index == a.pageIndex })
        else { return nil }
        return page.looseText.first { $0.id == a.spanID }
    }
}
