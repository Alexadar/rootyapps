import Testing
import Foundation
@testable import XLSXExportKit

/// Oracles:
///  • CRC-32 standard check value: crc32("123456789") = 0xCBF43926 (ITU-T V.42 / PKWARE).
///  • ZIP structure: PKWARE APPNOTE.TXT — the produced container is re-read by an
///    independent minimal reader below (EOCD → central directory → local headers).
///  • Column references: Excel's documented bijective base-26 (A, Z, AA, ZZ, AAA; the sheet
///    maximum is column 16384 = "XFD").
///  • Worksheet-name rules: Microsoft's documented limits (31 chars, no \ / ? * [ ] :).
@Suite struct XLSXTests {

    @Test func crc32StandardCheckValue() {
        #expect(Zip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(Zip.crc32(Data()) == 0)
    }

    @Test func columnReferenceOracle() {
        #expect(XLSX.columnReference(0) == "A")
        #expect(XLSX.columnReference(25) == "Z")
        #expect(XLSX.columnReference(26) == "AA")
        #expect(XLSX.columnReference(51) == "AZ")
        #expect(XLSX.columnReference(52) == "BA")
        #expect(XLSX.columnReference(701) == "ZZ")
        #expect(XLSX.columnReference(702) == "AAA")
        #expect(XLSX.columnReference(16383) == "XFD")   // Excel's last column
        #expect(XLSX.cellReference(row: 1, column: 1) == "B2")
    }

    @Test func sheetNameRules() {
        #expect(XLSX.sanitizedSheetName("Page 1", existing: []) == "Page 1")
        #expect(XLSX.sanitizedSheetName("a\\b/c?d*e[f]g:h", existing: []) == "abcdefgh")
        #expect(XLSX.sanitizedSheetName("'quoted'", existing: []) == "quoted")
        #expect(XLSX.sanitizedSheetName(String(repeating: "x", count: 40), existing: []).count == 31)
        #expect(XLSX.sanitizedSheetName("", existing: []) == "Sheet")
        #expect(XLSX.sanitizedSheetName("[]:", existing: []) == "Sheet")
        #expect(XLSX.sanitizedSheetName("Data", existing: ["Data"]) == "Data 2")
        #expect(XLSX.sanitizedSheetName("Data", existing: ["Data", "Data 2"]) == "Data 3")
        // Truncation + suffix still ≤ 31 and unique.
        let long = String(repeating: "y", count: 31)
        let dup = XLSX.sanitizedSheetName(long, existing: [long])
        #expect(dup.count <= 31 && dup.hasSuffix(" 2"))
    }

    @Test func xmlEscaping() {
        #expect(XLSX.xmlEscape("a<b&c>\"d\"") == "a&lt;b&amp;c&gt;&quot;d&quot;")
        #expect(XLSX.xmlEscape("tab\tlf\n") == "tab\tlf\n")
        #expect(XLSX.xmlEscape("bell\u{07}gone") == "bellgone")   // illegal in XML 1.0 → dropped
    }

    @Test func containerRoundTripsThroughIndependentReader() throws {
        let file = XLSX.data(sheets: [
            XLSX.Sheet(name: "Data", rows: [["Name", "Qty"], ["bolt", "12"], ["", "x"]]),
            XLSX.Sheet(name: "Notes", rows: [["hello & <world>"]]),
        ])
        let entries = try MiniZip.read(file)
        #expect(entries.map(\.name) == [
            "[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml",
        ])
        // Stored CRCs must match independently recomputed CRCs of the extracted bytes.
        for e in entries {
            #expect(Zip.crc32(e.data) == e.storedCRC, "CRC mismatch in \(e.name)")
        }
        let sheet1 = String(decoding: entries[4].data, as: UTF8.self)
        #expect(sheet1.contains(#"<c r="A1" t="inlineStr"><is><t>Name</t></is></c>"#))
        #expect(sheet1.contains(#"<c r="B2" t="inlineStr"><is><t>12</t></is></c>"#))
        // Empty cell A3 is omitted; B3 present.
        #expect(!sheet1.contains(#"r="A3""#))
        #expect(sheet1.contains(#"<c r="B3" t="inlineStr"><is><t>x</t></is></c>"#))
        let sheet2 = String(decoding: entries[5].data, as: UTF8.self)
        #expect(sheet2.contains("hello &amp; &lt;world&gt;"))
        let workbook = String(decoding: entries[2].data, as: UTF8.self)
        #expect(workbook.contains(#"<sheet name="Data" sheetId="1" r:id="rId1"/>"#))
        #expect(workbook.contains(#"<sheet name="Notes" sheetId="2" r:id="rId2"/>"#))
        let types = String(decoding: entries[0].data, as: UTF8.self)
        #expect(types.contains("/xl/worksheets/sheet2.xml"))
    }

    @Test func outputIsDeterministic() {
        let sheets = [XLSX.Sheet(name: "S", rows: [["a", "b"]])]
        #expect(XLSX.data(sheets: sheets) == XLSX.data(sheets: sheets))
    }

    @Test func zeroSheetsProducesOneEmptySheet() throws {
        let entries = try MiniZip.read(XLSX.data(sheets: []))
        #expect(entries.contains { $0.name == "xl/worksheets/sheet1.xml" })
    }

    @Test func whitespacePreservedCellsAreMarked() {
        let xml = XLSX.worksheetXML([[" padded "]])
        #expect(xml.contains(#"<t xml:space="preserve"> padded </t>"#))
    }
}

/// Independent minimal ZIP reader (STORED entries) used only to verify the writer.
/// Parses EOCD → central directory → local headers, per PKWARE APPNOTE.TXT.
enum MiniZip {
    struct Entry { let name: String; let data: Data; let storedCRC: UInt32 }
    struct ReadError: Error { let reason: String }

    static func read(_ file: Data) throws -> [Entry] {
        let b = [UInt8](file)
        guard b.count >= 22 else { throw ReadError(reason: "too small") }
        // No archive comment is written, so EOCD is exactly the last 22 bytes.
        let eocd = b.count - 22
        guard u32(b, eocd) == 0x0605_4b50 else { throw ReadError(reason: "no EOCD") }
        let count = Int(u16(b, eocd + 10))
        var pos = Int(u32(b, eocd + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard u32(b, pos) == 0x0201_4b50 else { throw ReadError(reason: "bad central sig") }
            let crc = u32(b, pos + 16)
            let csize = Int(u32(b, pos + 20))
            let nameLen = Int(u16(b, pos + 28))
            let extraLen = Int(u16(b, pos + 30))
            let commentLen = Int(u16(b, pos + 32))
            let localOffset = Int(u32(b, pos + 42))
            let name = String(decoding: b[(pos + 46)..<(pos + 46 + nameLen)], as: UTF8.self)
            // Local header: skip its own name/extra to reach the data.
            guard u32(b, localOffset) == 0x0403_4b50 else { throw ReadError(reason: "bad local sig") }
            guard u16(b, localOffset + 8) == 0 else { throw ReadError(reason: "not stored") }
            let lNameLen = Int(u16(b, localOffset + 26))
            let lExtraLen = Int(u16(b, localOffset + 28))
            let dataStart = localOffset + 30 + lNameLen + lExtraLen
            entries.append(Entry(name: name,
                                 data: Data(b[dataStart..<(dataStart + csize)]),
                                 storedCRC: crc))
            pos += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
