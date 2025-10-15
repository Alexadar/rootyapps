//
//  YAMLParser.swift
//  bigpinkcat.swift Shared
//
//  Simple YAML parser for game data
//

import Foundation

class YAMLParser {

    // Parse YAML file and decode to a Codable type
    static func parse<T: Decodable>(_ filename: String, from bundle: Bundle = .main) throws -> T {
        guard let url = bundle.url(forResource: filename, withExtension: "yaml") else {
            throw YAMLError.fileNotFound(filename)
        }

        let yamlString = try String(contentsOf: url, encoding: .utf8)
        return try parseString(yamlString)
    }

    // Parse YAML string and convert to JSON, then decode
    static func parseString<T: Decodable>(_ yamlString: String) throws -> T {
        // Convert YAML to JSON-like dictionary
        let jsonData = try yamlToJSON(yamlString)

        // Decode using JSONDecoder
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: jsonData)
    }

    // Convert simple YAML format to JSON data
    private static func yamlToJSON(_ yaml: String) throws -> Data {
        // This is a simplified YAML parser for the specific format used in this game
        // It handles basic YAML structures: dictionaries, arrays, and strings

        var result: Any?
        let lines = yaml.components(separatedBy: .newlines)
        var stack: [(indent: Int, value: Any)] = []
        var currentIndent = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let indent = line.prefix(while: { $0 == " " }).count

            // Handle array items
            if trimmed.hasPrefix("- ") {
                let content = String(trimmed.dropFirst(2))

                if content.contains(":") {
                    // Dictionary item in array
                    let dict = parseDictLine(content)
                    // TODO: Handle nested structures
                } else {
                    // Simple array item
                    // TODO: Add to array
                }
            }
            // Handle dictionary keys
            else if trimmed.contains(":") {
                let components = trimmed.components(separatedBy: ": ")
                if components.count >= 2 {
                    let key = components[0]
                    let value = components[1...].joined(separator: ": ")
                    // TODO: Build dictionary structure
                }
            }
        }

        // For now, use a simpler approach with property list serialization
        // This is a placeholder - in production, use a proper YAML library like Yams

        // Instead, let's create a manual parsing function for our specific YAML structure
        return try manualParseYAML(yaml)
    }

    // Manual YAML parsing for the game's specific format
    private static func manualParseYAML(_ yaml: String) throws -> Data {
        var jsonDict: [String: Any] = [:]
        var rootArray: [[String: Any]] = []  // For root-level arrays
        var rootIsArray = false  // Track if the root level is an array
        var currentDict: [String: Any] = [:]

        let lines = yaml.components(separatedBy: .newlines)

        // First, detect if this is a root-level array (starts with - at beginning)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                rootIsArray = line.hasPrefix("- ")
                break
            }
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                i += 1
                continue
            }

            let indent = line.prefix(while: { $0 == " " }).count

            if rootIsArray {
                // Root-level array parsing
                if line.hasPrefix("- ") {
                    // Save previous dict and start new one
                    if !currentDict.isEmpty {
                        rootArray.append(currentDict)
                        currentDict = [:]
                    }

                    // Parse the content after "- "
                    let content = String(line.dropFirst(2))
                    if let colonIndex = content.firstIndex(of: ":") {
                        let key = String(content[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let valueStart = content.index(after: colonIndex)
                        let value = content[valueStart...].trimmingCharacters(in: .whitespaces)
                        currentDict[key] = parseValue(value)
                    }
                } else if line.hasPrefix("  ") && !line.hasPrefix("  - ") {
                    // Continuation of dict (indented line, not nested array)
                    if let colonIndex = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let valueStart = trimmed.index(after: colonIndex)
                        let value = trimmed[valueStart...].trimmingCharacters(in: .whitespaces)

                        if value.isEmpty || value == "[]" {
                            // This is a key for a nested array or object
                            if value == "[]" {
                                currentDict[key] = []
                            } else {
                                // Look ahead to parse nested array
                                var nestedArray: [[String: Any]] = []
                                var j = i + 1
                                while j < lines.count {
                                    let nextLine = lines[j]
                                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                                    let nextIndent = nextLine.prefix(while: { $0 == " " }).count

                                    if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") {
                                        j += 1
                                        continue
                                    }

                                    // Check if this is a nested array item (indented more than current level)
                                    if nextIndent > indent && nextLine.hasPrefix("  - ") {
                                        let itemContent = String(nextLine.dropFirst(4))  // Remove "  - "
                                        var itemDict: [String: Any] = [:]

                                        if let colonIndex = itemContent.firstIndex(of: ":") {
                                            let itemKey = String(itemContent[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                                            let itemValueStart = itemContent.index(after: colonIndex)
                                            let itemValue = itemContent[itemValueStart...].trimmingCharacters(in: .whitespaces)
                                            itemDict[itemKey] = parseValue(itemValue)
                                            nestedArray.append(itemDict)
                                        }
                                        j += 1
                                    } else if nextIndent <= indent {
                                        // End of nested array
                                        break
                                    } else {
                                        j += 1
                                    }
                                }
                                currentDict[key] = nestedArray
                                i = j - 1  // Skip processed lines
                            }
                        } else {
                            currentDict[key] = parseValue(value)
                        }
                    }
                }
            } else {
                // Dictionary parsing
                if let colonIndex = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let valueStart = trimmed.index(after: colonIndex)
                    let value = trimmed[valueStart...].trimmingCharacters(in: .whitespaces)

                    if value.isEmpty || value == "[]" {
                        if value == "[]" {
                            jsonDict[key] = []
                        } else {
                            // Parse nested content (accept "- " items even if their indent equals the parent key)
                            var nestedArray: [Any] = []
                            var j = i + 1
                            while j < lines.count {
                                let nextLine = lines[j]
                                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                                let nextIndent = nextLine.prefix(while: { $0 == " " }).count

                                if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") {
                                    j += 1
                                    continue
                                }

                                // Accept nested array items that start with "- " regardless of indent
                                if nextTrimmed.hasPrefix("- ") {
                                    let itemContent = String(nextTrimmed.dropFirst(2))

                                    if itemContent.contains(":") {
                                        var itemDict = parseDictLine(itemContent)

                                        // Collect additional indented lines that belong to this item (e.g. "  id: 1")
                                        var lastTextKey: String? = {
                                            if let colonIndex = itemContent.firstIndex(of: ":") {
                                                return String(itemContent[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                                            }
                                            return nil
                                        }()
                                        var k = j + 1
                                        while k < lines.count {
                                            let continuedLine = lines[k]
                                            let continuedTrimmed = continuedLine.trimmingCharacters(in: .whitespaces)
                                            let continuedIndent = continuedLine.prefix(while: { $0 == " " }).count

                                            if continuedTrimmed.isEmpty || continuedTrimmed.hasPrefix("#") {
                                                k += 1
                                                continue
                                            }

                                            // Stop if we returned to parent or sibling level
                                            if continuedIndent <= nextIndent {
                                                break
                                            }

                                            if let colonIndex = continuedTrimmed.firstIndex(of: ":") {
                                                let cKey = String(continuedTrimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                                                let valueStart = continuedTrimmed.index(after: colonIndex)
                                                let cValue = continuedTrimmed[valueStart...].trimmingCharacters(in: .whitespaces)
                                                itemDict[cKey] = parseValue(cValue)
                                                lastTextKey = cKey
                                            } else {
                                                // Treat as a continuation of the last text key (multiline string)
                                                if let key = lastTextKey {
                                                    let prev = (itemDict[key] as? String) ?? ""
                                                    let appended = prev.isEmpty ? continuedTrimmed : prev + " " + continuedTrimmed
                                                    itemDict[key] = appended
                                                }
                                            }

                                            k += 1
                                        }

                                        nestedArray.append(itemDict)
                                        j = k
                                    } else {
                                        // Simple value item (treat as a multiline string, not a dict)
                                        var collected = itemContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                        var k = j + 1
                                        while k < lines.count {
                                            let continuedLine = lines[k]
                                            let continuedTrimmed = continuedLine.trimmingCharacters(in: .whitespaces)
                                            let continuedIndent = continuedLine.prefix(while: { $0 == " " }).count

                                            if continuedTrimmed.isEmpty || continuedTrimmed.hasPrefix("#") {
                                                k += 1
                                                continue
                                            }

                                            // If we returned to the parent or sibling level, stop collecting
                                            if continuedIndent <= nextIndent || continuedTrimmed.hasPrefix("- ") {
                                                break
                                            }

                                            // Append the continued line to the collected multiline string
                                            collected += "\n" + continuedTrimmed
                                            k += 1
                                        }

                                        nestedArray.append(collected)
                                        j = k
                                    }
                                } else if nextIndent <= indent {
                                    // End of nested array
                                    break
                                } else {
                                    j += 1
                                }
                            }
                            jsonDict[key] = nestedArray
                            i = j - 1
                        }
                    } else {
                        jsonDict[key] = parseValue(value)
                    }
                }
            }

            i += 1
        }

        // Save final data
        if rootIsArray {
            if !currentDict.isEmpty {
                rootArray.append(currentDict)
            }
            return try JSONSerialization.data(withJSONObject: rootArray, options: [])
        } else {
            return try JSONSerialization.data(withJSONObject: jsonDict, options: [])
        }
    }

    private static func parseValue(_ value: String) -> Any {
        // Try to parse as Int
        if let intValue = Int(value) {
            return intValue
        }

        // Try to parse as Double
        if let doubleValue = Double(value) {
            return doubleValue
        }

        // Try to parse as Bool
        if value.lowercased() == "true" {
            return true
        }
        if value.lowercased() == "false" {
            return false
        }

        // Try to parse as array
        if value.hasPrefix("[") && value.hasSuffix("]") {
            let content = value.dropFirst().dropLast()
            let items = content.components(separatedBy: ", ")
            return items.map { parseValue($0) }
        }

        // Default to string
        return value
    }

    private static func parseDictLine(_ line: String) -> [String: Any] {
        var dict: [String: Any] = [:]
        let components = line.components(separatedBy: ", ")

        for component in components {
            if let colonIndex = component.firstIndex(of: ":") {
                let key = String(component[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStart = component.index(after: colonIndex)
                let value = component[valueStart...].trimmingCharacters(in: .whitespaces)
                dict[key] = parseValue(value)
            }
        }

        return dict
    }
}

enum YAMLError: Error {
    case fileNotFound(String)
    case parseError(String)
}
