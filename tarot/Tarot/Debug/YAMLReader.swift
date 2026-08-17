import Foundation

/// A deliberately small YAML reader for filming scenarios.
///
/// Tarot has no third-party dependencies — two local Kits and nothing else — and a Debug-only
/// capture harness is not the thing to spend that on. This reads the subset the scenario
/// schema actually uses and **refuses everything else with a line number**, so a real YAML
/// pasted in from elsewhere fails loudly instead of half-parsing into a take that looks
/// almost right.
///
/// Supported:  `key: value` · nested maps by 2-space indent · `- scalar` · `- |` block
///             scalars · `|` and `|-` block scalars · "double" and 'single' quotes ·
///             `#` comments when `#` opens the line
/// Refused:    flow collections `[]`/`{}` · anchors `&` · aliases `*` · tags `!` · folded
///             `>` · multi-document `---` · tabs · odd indentation · duplicate keys ·
///             unterminated quotes
enum YAMLReader {

    indirect enum Node: Equatable {
        case scalar(String)
        case list([Node])
        case map([String: Node])
    }

    static func parse(_ text: String) throws -> [String: Node] {
        var lines: [Line] = []
        for (offset, raw) in text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n").enumerated() {
            lines.append(Line(number: offset + 1, raw: raw))
        }
        var index = 0
        let node = try parseBlock(lines, &index, indent: 0)
        guard case .map(let map) = node else {
            throw ScenarioError(line: 1, message: "a scenario must be a map of keys")
        }
        return map
    }

    private struct Line {
        let number: Int
        let raw: String
        var indent: Int { raw.prefix { $0 == " " }.count }
        var content: String { raw.trimmingCharacters(in: .whitespaces) }
        var isSkippable: Bool { content.isEmpty || content.hasPrefix("#") }
    }

    /// One block at a given indent: either a sequence (every line starts `- `) or a map.
    private static func parseBlock(_ lines: [Line], _ index: inout Int, indent: Int) throws -> Node {
        var map: [String: Node] = [:]
        var list: [Node] = []
        var sawMapping = false

        while index < lines.count {
            let line = lines[index]
            if line.isSkippable { index += 1; continue }
            if line.indent < indent { break }
            guard line.indent == indent else {
                throw ScenarioError(line: line.number,
                                    message: "indent \(line.indent) where \(indent) was expected — "
                                           + "this reader wants exactly two spaces per level")
            }
            try reject(line)

            if line.content.hasPrefix("- ") || line.content == "-" {
                let item = String(line.content.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                index += 1
                if item == "|" || item == "|-" {
                    list.append(.scalar(try blockScalar(lines, &index, parentIndent: indent,
                                                        chomp: item == "|-")))
                } else if item.isEmpty {
                    list.append(try parseBlock(lines, &index, indent: indent + 2))
                } else {
                    list.append(.scalar(try scalar(item, line: line.number)))
                }
                continue
            }

            guard let colon = line.content.firstIndex(of: ":") else {
                throw ScenarioError(line: line.number, message: "expected 'key: value'")
            }
            let key = String(line.content[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                throw ScenarioError(line: line.number, message: "'\(key)' is not a plain key")
            }
            guard map[key] == nil else {
                throw ScenarioError(line: line.number, message: "duplicate key '\(key)'")
            }
            sawMapping = true
            let rest = String(line.content[line.content.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            index += 1

            if rest == "|" || rest == "|-" {
                map[key] = .scalar(try blockScalar(lines, &index, parentIndent: indent,
                                                   chomp: rest == "|-"))
            } else if rest.isEmpty {
                map[key] = try parseBlock(lines, &index, indent: indent + 2)
            } else {
                map[key] = .scalar(try scalar(rest, line: line.number))
            }
        }

        if !list.isEmpty {
            guard !sawMapping else {
                throw ScenarioError(line: lines[max(index - 1, 0)].number,
                                    message: "a block is a list or a map, never both")
            }
            return .list(list)
        }
        return .map(map)
    }

    /// A `|` block: raw lines until the indent drops. Nothing inside is a comment or a key.
    private static func blockScalar(_ lines: [Line], _ index: inout Int,
                                    parentIndent: Int, chomp: Bool) throws -> String {
        let bodyIndent = parentIndent + 2
        var collected: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.content.isEmpty { collected.append(""); index += 1; continue }
            if line.indent < bodyIndent { break }
            if line.raw.contains("\t") {
                throw ScenarioError(line: line.number, message: "tab in a block scalar")
            }
            collected.append(String(line.raw.dropFirst(bodyIndent)))
            index += 1
        }
        while collected.last?.isEmpty == true { collected.removeLast() }
        let body = collected.joined(separator: "\n")
        return chomp ? body : body + "\n"
    }

    private static func scalar(_ token: String, line: Int) throws -> String {
        if token.hasPrefix("\"") {
            guard token.count >= 2, token.hasSuffix("\"") else {
                throw ScenarioError(line: line, message: "unterminated double quote")
            }
            return String(token.dropFirst().dropLast())
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if token.hasPrefix("'") {
            guard token.count >= 2, token.hasSuffix("'") else {
                throw ScenarioError(line: line, message: "unterminated single quote")
            }
            return String(token.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return token
    }

    /// Everything this reader does not implement, refused by name — a silent misread is far
    /// worse than a failed load, because it only shows up in the footage.
    private static func reject(_ line: Line) throws {
        if line.raw.contains("\t") {
            throw ScenarioError(line: line.number, message: "tabs are not YAML indentation")
        }
        let c = line.content
        if c.hasPrefix("---") || c.hasPrefix("...") {
            throw ScenarioError(line: line.number, message: "multi-document YAML is not supported")
        }
        for (marker, name) in [("&", "anchors"), ("*", "aliases"), ("!", "tags")]
        where c.hasPrefix(marker) || c.contains(": \(marker)") {
            throw ScenarioError(line: line.number, message: "\(name) are not supported")
        }
        if c.hasSuffix(": >") || c.hasSuffix(": >-") {
            throw ScenarioError(line: line.number, message: "folded scalars are not supported; use |")
        }
        // Flow collections only where a value would be — a bracket inside prose is fine.
        if let colon = c.firstIndex(of: ":") {
            let value = c[c.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") || value.hasPrefix("{") {
                throw ScenarioError(line: line.number,
                                    message: "flow collections are not supported; use a '-' list")
            }
        }
    }
}
