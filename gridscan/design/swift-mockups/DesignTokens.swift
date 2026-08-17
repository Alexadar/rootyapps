import SwiftUI

// GridScan — design tokens. HTML px in the board map 1:1 to pt here.
// NOTE: All sample columns/rows in these mockups (e.g. "Sample ID", "Depth",
// "pH") are EXAMPLE content only. Columns come from the scanned document at
// runtime; the product defines NO columns of its own.
//
// Structural kind is FIRST-CLASS (tier one): every document has one.
// Kinds describe layout SHAPE, never content meaning.
enum DocumentKind: String, CaseIterable {
    case table   // rows and columns
    case form    // repeated labelled fields
    case report  // flowing text with occasional fields

    var symbolName: String {
        switch self {
        case .table: return "tablecells"
        case .form: return "list.bullet.rectangle"
        case .report: return "doc.text"
        }
    }
}
enum GS {
    // Colors (system-adaptive where possible; literals match the spec board)
    static let tint = Color.accentColor            // #007AFF / #0A84FF
    static let corrected = Color(red: 0.345, green: 0.337, blue: 0.839) // #5856D6
    static let flag = Color.orange                  // #FF9500 / #FF9F0A
    static let flagText = Color(red: 0.788, green: 0.204, blue: 0.0)    // #C93400

    // Metrics
    static let hitTarget: CGFloat = 44
    static let gridRowHeight: CGFloat = 36
    static let tileRadius: CGFloat = 12
    static let sheetRadius: CGFloat = 16
    static let capsuleRadius: CGFloat = 22
}

// Provenance of a structured value. OCR confidence is real; per-field
// extraction confidence does NOT exist — never design a badge for it.
enum Provenance: Equatable {
    case extracted
    case corrected(was: String)      // human-touched; renders in GS.corrected + pencil
    case flagged(reason: FlagReason) // needs attention; glyph + underline, never color alone
    case missingRequired
}

enum FlagReason: Equatable {
    case failedFormatRule(String)   // e.g. a date column that didn't parse
    case lowOCRConfidence           // on the underlying text — a legitimate signal
}
