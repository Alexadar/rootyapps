import Testing
import Foundation
@testable import CSVExportKit

/// Oracle = RFC 4180 §2 (https://www.rfc-editor.org/rfc/rfc4180), worked byte-exact examples.
@Suite struct CSVTests {

    @Test func plainFieldsUnquoted() {
        #expect(CSV.encode([["a", "b", "c"]]) == "a,b,c\r\n")
    }

    @Test func spacesArePartOfTheFieldAndNotQuoted() {
        // RFC 4180: "Spaces are considered part of a field and should not be ignored."
        #expect(CSV.encode([[" a ", "b b"]]) == " a ,b b\r\n")
    }

    @Test func delimiterInFieldForcesQuotes() {
        #expect(CSV.encode([["a,b", "c"]]) == "\"a,b\",c\r\n")
    }

    @Test func embeddedQuotesAreDoubledAndQuoted() {
        #expect(CSV.encode([["say \"hi\""]]) == "\"say \"\"hi\"\"\"\r\n")
    }

    @Test func embeddedLineBreaksAreQuoted() {
        #expect(CSV.encode([["line1\nline2"]]) == "\"line1\nline2\"\r\n")
        #expect(CSV.encode([["a\r\nb"]]) == "\"a\r\nb\"\r\n")
    }

    @Test func multipleRecordsEachEndWithCRLF() {
        #expect(CSV.encode([["a"], ["b"]]) == "a\r\nb\r\n")
        #expect(CSV.encode([]) == "")
    }

    @Test func emptyFieldsSurvive() {
        #expect(CSV.encode([["", "", "x"]]) == ",,x\r\n")
    }

    @Test func semicolonDelimiterOption() {
        let opts = CSV.Options(delimiter: ";")
        // Comma no longer needs quoting; semicolon now does.
        #expect(CSV.encode([["a,b", "c;d"]], options: opts) == "a,b;\"c;d\"\r\n")
    }

    @Test func bomBytesExactlyOnceAtStart() {
        let d = CSV.data([["x"]], options: CSV.Options(includeBOM: true))
        #expect(Array(d.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: d.dropFirst(3), as: UTF8.self) == "x\r\n")
        let plain = CSV.data([["x"]])
        #expect(Array(plain.prefix(3)) != [0xEF, 0xBB, 0xBF])
    }

    @Test func unicodePassesThrough() {
        #expect(CSV.encode([["Übersicht", "画面", "🙂"]]) == "Übersicht,画面,🙂\r\n")
    }
}
