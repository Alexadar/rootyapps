import Foundation

/// RFC 4180 CSV writer. Pure, stateless.
/// Oracle = RFC 4180 §2 (https://www.rfc-editor.org/rfc/rfc4180): fields containing the
/// delimiter, a double quote, CR or LF are enclosed in double quotes; embedded double quotes
/// are doubled; records end with CRLF. Nothing else is quoted (spaces are field content).
public enum CSV {

    public struct Options: Sendable, Equatable {
        /// Field delimiter. "," per RFC; ";" for locales whose Excel expects it.
        public var delimiter: Character
        /// Record terminator. CRLF per RFC (and what Excel expects).
        public var lineEnding: String
        /// Prepend a UTF-8 BOM (EF BB BF) so Excel detects UTF-8. `data` output only.
        public var includeBOM: Bool

        public init(delimiter: Character = ",", lineEnding: String = "\r\n",
                    includeBOM: Bool = false) {
            self.delimiter = delimiter
            self.lineEnding = lineEnding
            self.includeBOM = includeBOM
        }
    }

    /// Encode rows to CSV text. Every record, including the last, ends with `lineEnding`.
    public static func encode(_ rows: [[String]], options: Options = Options()) -> String {
        rows.map { row in
            row.map { field($0, options: options) }
                .joined(separator: String(options.delimiter)) + options.lineEnding
        }.joined()
    }

    /// UTF-8 bytes, with BOM when `options.includeBOM`.
    public static func data(_ rows: [[String]], options: Options = Options()) -> Data {
        var out = Data()
        if options.includeBOM { out.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        out.append(Data(encode(rows, options: options).utf8))
        return out
    }

    static func field(_ raw: String, options: Options) -> String {
        // Scan unicode scalars, not Characters: "\r\n" is ONE grapheme cluster, so a
        // Character-level contains("\r") misses CRLF and ships an unquoted line break.
        let mustQuote = raw.contains(options.delimiter)
            || raw.unicodeScalars.contains { $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard mustQuote else { return raw }
        return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
