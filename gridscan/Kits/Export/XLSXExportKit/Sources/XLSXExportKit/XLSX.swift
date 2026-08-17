import Foundation

/// Minimal .xlsx (ECMA-376 SpreadsheetML) writer: one workbook, N worksheets, every cell an
/// inline string (no sharedStrings, no styles). Pure, stateless, deterministic — identical
/// input produces identical bytes (fixed ZIP timestamps).
/// Oracle = ECMA-376 Part 1 §18 (SpreadsheetML) + Microsoft's documented worksheet-name and
/// A1-reference rules; structure verified in tests by re-reading the produced container.
public enum XLSX {

    public struct Sheet: Sendable, Equatable {
        public var name: String
        public var rows: [[String]]
        public init(name: String, rows: [[String]]) {
            self.name = name
            self.rows = rows
        }
    }

    /// Build the complete .xlsx file. Sheet names are sanitized to Excel's rules and
    /// de-duplicated in order. At least one sheet is required (Excel rejects zero-sheet
    /// workbooks); an empty input produces one empty "Sheet".
    public static func data(sheets rawSheets: [Sheet]) -> Data {
        let sheets = rawSheets.isEmpty ? [Sheet(name: "Sheet", rows: [])] : rawSheets
        var usedNames: [String] = []
        var entries: [Zip.Entry] = []

        var contentTypes = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            """
        var workbookSheets = ""
        var workbookRels = ""

        for (i, sheet) in sheets.enumerated() {
            let n = i + 1
            let name = sanitizedSheetName(sheet.name, existing: usedNames)
            usedNames.append(name)
            contentTypes += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            workbookSheets += "<sheet name=\"\(xmlEscape(name))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
            workbookRels += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
            entries.append(Zip.Entry(name: "xl/worksheets/sheet\(n).xml",
                                     data: Data(worksheetXML(sheet.rows).utf8)))
        }
        contentTypes += "</Types>"

        let rels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
            </Relationships>
            """
        let workbook = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <sheets>\(workbookSheets)</sheets></workbook>
            """
        let workbookRelsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(workbookRels)</Relationships>
            """

        var all: [Zip.Entry] = [
            Zip.Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            Zip.Entry(name: "_rels/.rels", data: Data(rels.utf8)),
            Zip.Entry(name: "xl/workbook.xml", data: Data(workbook.utf8)),
            Zip.Entry(name: "xl/_rels/workbook.xml.rels", data: Data(workbookRelsXML.utf8)),
        ]
        all.append(contentsOf: entries)
        return Zip.archive(all)
    }

    /// Excel worksheet-name rules: strip \ / ? * [ ] :, no leading/trailing apostrophe,
    /// max 31 characters, non-empty, unique within the workbook (suffix " 2", " 3", …).
    public static func sanitizedSheetName(_ raw: String, existing: [String]) -> String {
        var s = raw.filter { !"\\/?*[]:".contains($0) }
        while s.hasPrefix("'") { s.removeFirst() }
        while s.hasSuffix("'") { s.removeLast() }
        s = String(s.prefix(31))
        if s.trimmingCharacters(in: .whitespaces).isEmpty { s = "Sheet" }
        guard existing.contains(s) else { return s }
        var i = 2
        while true {
            let suffix = " \(i)"
            let candidate = String(s.prefix(31 - suffix.count)) + suffix
            if !existing.contains(candidate) { return candidate }
            i += 1
        }
    }

    /// Bijective base-26 column reference: 0 → "A", 25 → "Z", 26 → "AA", 16383 → "XFD".
    public static func columnReference(_ index: Int) -> String {
        var i = index
        var out = ""
        while i >= 0 {
            out = String(UnicodeScalar(UInt8(65 + i % 26))) + out
            i = i / 26 - 1
        }
        return out
    }

    /// A1-style cell reference for zero-based (row, column).
    public static func cellReference(row: Int, column: Int) -> String {
        columnReference(column) + String(row + 1)
    }

    static func worksheetXML(_ rows: [[String]]) -> String {
        var body = ""
        for (r, row) in rows.enumerated() {
            body += "<row r=\"\(r + 1)\">"
            for (c, cell) in row.enumerated() where !cell.isEmpty {
                let preserve = cell.first?.isWhitespace == true || cell.last?.isWhitespace == true
                let space = preserve ? " xml:space=\"preserve\"" : ""
                body += "<c r=\"\(cellReference(row: r, column: c))\" t=\"inlineStr\">"
                    + "<is><t\(space)>\(xmlEscape(cell))</t></is></c>"
            }
            body += "</row>"
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <sheetData>\(body)</sheetData></worksheet>
            """
    }

    /// XML 1.0 escaping for text and attribute content. Control characters that are illegal
    /// in XML 1.0 (everything below 0x20 except TAB/LF/CR) are dropped — they cannot be
    /// represented and would corrupt the part.
    static func xmlEscape(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case let c where c.value < 0x20 && c != "\t" && c != "\n" && c != "\r": continue
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}
