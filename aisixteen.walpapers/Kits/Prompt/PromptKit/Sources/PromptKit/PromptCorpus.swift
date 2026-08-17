import Foundation

/// The corpus behind *Surprise me*, read from a resource rather than compiled in.
///
/// ### Why a file, and why one per checkpoint
///
/// Prompts are content. They get rewritten far more often than the code that draws them, and
/// wording a wallpaper should not mean opening a Swift file and reading a diff full of escaped
/// quotes. More importantly, **prompts are tuned to weights**: what reads well on one checkpoint
/// reads flat on another, so the corpus is named for the model it was written against —
/// `sd15cn_sampleprompts.yaml`. Replacing the checkpoint is then a visible prompt for whoever
/// replaces it to revisit the wording, instead of silently inheriting someone else's phrasing.
public struct PromptCorpus: Sendable, Equatable {

    public var curated: [String]
    public var palettes: [SurpriseMe.Palette]

    public init(curated: [String], palettes: [SurpriseMe.Palette]) {
        self.curated = curated
        self.palettes = palettes
    }

    public static func resourceName(forModel modelID: String) -> String {
        "\(modelID)_sampleprompts"
    }

    /// The corpus for a model, falling back to the house one.
    ///
    /// A checkpoint that ships without its own prompts gets `sd15cn`'s rather than an empty corpus:
    /// prompts written for a different SD 1.5 fine-tune are imperfect, and a *Surprise me* that
    /// does nothing when tapped is broken. The fallback is a compromise; a dead control is a bug.
    public static func load(forModel modelID: String = "sd15cn") throws -> PromptCorpus {
        try load(forModel: modelID, in: .module)
    }

    /// The bundle is a parameter so tests can point at a fixture, and so an app that ships its
    /// corpus outside this package can hand over its own.
    public static func load(forModel modelID: String, in bundle: Bundle) throws -> PromptCorpus {
        if let url = bundle.url(forResource: resourceName(forModel: modelID), withExtension: "yaml") {
            return try load(contentsOf: url)
        }
        guard modelID != "sd15cn",
              let fallback = bundle.url(forResource: resourceName(forModel: "sd15cn"),
                                        withExtension: "yaml") else {
            throw CorpusError.missingResource(resourceName(forModel: modelID))
        }
        return try load(contentsOf: fallback)
    }

    public static func load(contentsOf url: URL) throws -> PromptCorpus {
        try parse(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    public enum CorpusError: Error, Equatable, CustomStringConvertible {
        case missingResource(String)
        case malformed(line: Int, reason: String)
        case empty(String)

        public var description: String {
            switch self {
            case .missingResource(let name): return "no prompt corpus named \(name).yaml"
            case .malformed(let line, let reason): return "prompt corpus line \(line): \(reason)"
            case .empty(let what): return "prompt corpus has no \(what)"
            }
        }
    }

    // MARK: The reader

    /// A **restricted** YAML reader — deliberately not a general one.
    ///
    /// PromptKit has no dependencies and is meant to stay that way, and the shape here is entirely
    /// under this project's control: two top-level keys, a list of strings, and a list of maps whose
    /// values are lists of strings. That is small enough to read exactly.
    ///
    /// The danger with a hand-written parser is that it *silently* mis-reads and yields a smaller
    /// corpus than the file contains — a quarter of the prompts vanish and nothing reports it. So
    /// every unrecognised construct throws with a line number, and the tests assert the loaded
    /// counts against the file. Loud beats clever.
    static func parse(_ text: String) throws -> PromptCorpus {
        var curated: [String] = []
        var palettes: [SurpriseMe.Palette] = []

        var name: String?
        var axes: [String: [String]] = [:]
        var section: String?       // "curated" or "palettes"
        var axis: String?          // subjects | lights | treatments

        func flushPalette() throws {
            guard let name else { return }
            for key in ["subjects", "lights", "treatments"] where (axes[key] ?? []).isEmpty {
                throw CorpusError.empty("\(key) in palette “\(name)”")
            }
            palettes.append(SurpriseMe.Palette(name: name,
                                               subjects: axes["subjects"] ?? [],
                                               lights: axes["lights"] ?? [],
                                               treatments: axes["treatments"] ?? []))
        }

        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = index + 1
            let stripped = raw.drop(while: { $0 == " " })
            if stripped.isEmpty || stripped.hasPrefix("#") { continue }
            let indent = raw.count - stripped.count
            let content = String(stripped)

            switch indent {
            case 0:
                guard content.hasSuffix(":") else {
                    throw CorpusError.malformed(line: line, reason: "expected a top-level key")
                }
                try flushPalette()
                name = nil; axes = [:]; axis = nil
                let key = String(content.dropLast())
                guard key == "curated" || key == "palettes" else {
                    throw CorpusError.malformed(line: line, reason: "unknown key “\(key)”")
                }
                section = key

            case 2:
                guard let section else {
                    throw CorpusError.malformed(line: line, reason: "value before any key")
                }
                if section == "curated" {
                    curated.append(try scalar(after: "- ", in: content, line: line))
                } else {
                    guard content.hasPrefix("- name: ") else {
                        throw CorpusError.malformed(line: line, reason: "a palette must start with “- name:”")
                    }
                    try flushPalette()
                    name = unquoted(String(content.dropFirst("- name: ".count)))
                    axes = [:]; axis = nil
                }

            case 4:
                guard name != nil, content.hasSuffix(":") else {
                    throw CorpusError.malformed(line: line, reason: "expected an axis key")
                }
                let key = String(content.dropLast())
                guard ["subjects", "lights", "treatments"].contains(key) else {
                    throw CorpusError.malformed(line: line, reason: "unknown axis “\(key)”")
                }
                axis = key
                axes[key] = []

            case 6:
                guard let axis else {
                    throw CorpusError.malformed(line: line, reason: "list item outside an axis")
                }
                axes[axis, default: []].append(try scalar(after: "- ", in: content, line: line))

            default:
                throw CorpusError.malformed(line: line, reason: "unexpected indent of \(indent)")
            }
        }
        try flushPalette()

        guard !curated.isEmpty else { throw CorpusError.empty("curated prompts") }
        guard !palettes.isEmpty else { throw CorpusError.empty("palettes") }
        return PromptCorpus(curated: curated, palettes: palettes)
    }

    private static func scalar(after marker: String, in content: String, line: Int) throws -> String {
        guard content.hasPrefix(marker) else {
            throw CorpusError.malformed(line: line, reason: "expected a list item")
        }
        let value = unquoted(String(content.dropFirst(marker.count)))
        guard !value.isEmpty else {
            throw CorpusError.malformed(line: line, reason: "empty list item")
        }
        return value
    }

    /// Quotes are optional in the file and stripped here. Nothing in the corpus needs escaping —
    /// prompts are plain prose — so a value containing a quote character is a mistake worth seeing
    /// rather than a case worth supporting.
    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }
}
