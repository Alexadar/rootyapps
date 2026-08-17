import Foundation
import Yams

/// Decodes `output_story/dialogs/*.yaml` into a `StoryGraph`.
///
/// The schema, as it actually exists on disk — a two-element sequence, not a flat list of dialogs:
///
/// ```yaml
/// - guidelines:
///   - Analyze the crystal's data layers for precise coordinates
///   - 'Options of phase_3_option_2:'
///   - Give cat to eat it, maybe it will be beneficial
/// - story_dialogs:
///   - character_id: 2
///     character_name: Big Pink Cat
///     character_text: Interesting. Very interesting.
///     id: 0
///     options:
///     - option_text: Let the cat eat the crystal
///     final_words:
///       option_1: "The astronaut returned to Earth..."
/// ```
///
/// `guidelines` is the author's outline — the prompt the dialogue was expanded from. It is parsed
/// and kept, because it is the specification for the fifteen leaves nobody has written yet, but it
/// is never displayed.
public enum StoryLoader {

    public enum LoadError: Error, CustomStringConvertible {
        case directoryUnreadable(URL)
        case malformed(file: String, reason: String)

        public var description: String {
            switch self {
            case .directoryUnreadable(let url):
                return "cannot list \(url.path)"
            case .malformed(let file, let reason):
                return "\(file): \(reason)"
            }
        }
    }

    /// Load every `dialog_*.yaml` in a directory.
    ///
    /// Errors are **thrown, never printed and swallowed**. The previous loader logged
    /// "Warning: Could not list files in summary_parts folder" and returned an empty model, which
    /// is how a missing folder became a blank screen at runtime instead of a build failure.
    public static func load(directory: URL) throws -> StoryGraph {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            throw LoadError.directoryUnreadable(directory)
        }
        var nodes: [String: StoryNode] = [:]
        for url in entries where url.pathExtension == "yaml"
            && url.lastPathComponent.hasPrefix("dialog_") {
            let id = url.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            nodes[id] = try parse(id: id, yaml: text)
        }
        guard !nodes.isEmpty else {
            throw LoadError.directoryUnreadable(directory)
        }
        return StoryGraph(nodes: nodes)
    }

    /// Parse one node's YAML.
    static func parse(id: String, yaml text: String) throws -> StoryNode {
        let any = try Yams.load(yaml: text)
        guard let top = any as? [Any] else {
            throw LoadError.malformed(file: id, reason: "top level is not a sequence")
        }

        var guidelines: [String] = []
        var lines: [StoryNode.Line] = []
        var options: [String] = []
        var finalWords: [String: String] = [:]

        for element in top {
            guard let map = element as? [String: Any] else { continue }

            if let g = map["guidelines"] as? [Any] {
                guidelines = g.map { String(describing: $0) }
            }

            guard let dialogs = map["story_dialogs"] as? [Any] else { continue }
            for entry in dialogs {
                guard let d = entry as? [String: Any] else { continue }

                if let fw = d["final_words"] as? [String: Any] {
                    for (k, v) in fw { finalWords[k] = String(describing: v) }
                }

                var lineOptions: [String] = []
                if let opts = d["options"] as? [Any] {
                    for o in opts {
                        if let om = o as? [String: Any], let text = om["option_text"] {
                            lineOptions.append(String(describing: text))
                        }
                    }
                }
                if !lineOptions.isEmpty { options = lineOptions }

                // A `final_words`-only entry carries no dialogue and is not a line.
                guard let textValue = d["character_text"] else { continue }
                lines.append(StoryNode.Line(
                    id: (d["id"] as? Int) ?? lines.count,
                    characterID: (d["character_id"] as? Int) ?? 0,
                    characterName: (d["character_name"] as? String) ?? "",
                    text: String(describing: textValue),
                    options: lineOptions))
            }
        }

        return StoryNode(id: id, guidelines: guidelines, lines: lines,
                         options: options, finalWords: finalWords)
    }

    /// The bundled story directory. Returns nil rather than trapping, so a caller can report a
    /// missing resource as a build problem instead of crashing a player's app.
    public static func bundledDirectory(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "dialogs", withExtension: nil, subdirectory: "output_story")
            ?? bundle.resourceURL?.appendingPathComponent("output_story/dialogs")
    }
}
