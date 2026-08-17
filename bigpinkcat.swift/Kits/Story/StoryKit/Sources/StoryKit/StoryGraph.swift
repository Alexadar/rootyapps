import Foundation
import Yams

/// The story tree, decoded from the YAML that actually exists on disk.
///
/// Pure, stateless apart from the decode. Node ids are the file stems — `dialog_1`, `dialog_1_1`,
/// `dialog_1_1_1` — and the tree structure is carried in the name: a node's *n*-th option leads to
/// `<id>_<n>`. That convention is what the 2025 loader missed.
public struct StoryNode: Sendable, Equatable {
    /// File stem, e.g. `dialog_1_1_1`.
    public let id: String
    /// The author's outline for the scene. Retained but never shown: it is the prompt the dialogue
    /// was expanded from, and it contains the option list in prose form.
    public let guidelines: [String]
    public let lines: [Line]
    /// The four choices offered at the end of the scene, in order.
    public let options: [String]
    /// Ending prose, keyed `option_1`…`option_4`. Present only on terminal nodes.
    public let finalWords: [String: String]

    public var isTerminal: Bool { !finalWords.isEmpty }
    /// A node with guidelines but no dialogue: seeded by the author, never expanded.
    public var isStub: Bool { lines.isEmpty && !guidelines.isEmpty }

    /// The id this node's `index`-th option leads to. One-based, matching the YAML's `option_1`.
    public func childID(forOption index: Int) -> String { "\(id)_\(index)" }

    public struct Line: Sendable, Equatable {
        public let id: Int
        public let characterID: Int
        public let characterName: String
        public let text: String
        /// Options attached to this line, if it is the branch point.
        public let options: [String]
    }
}

/// The decoded story, plus the honest account of what is missing from it.
public struct StoryGraph: Sendable {
    public let nodes: [String: StoryNode]
    public let rootID: String

    public init(nodes: [String: StoryNode], rootID: String = "dialog_1") {
        self.nodes = nodes
        self.rootID = rootID
    }

    public var nodeCount: Int { nodes.count }
    public func node(_ id: String) -> StoryNode? { nodes[id] }

    /// Every option that points at a node which does not exist, or which exists only as a stub.
    ///
    /// **This is reported, never swallowed.** The tree is genuinely unfinished — depth 1 and 2 are
    /// fully written, depth 3 is 1 of 16 with three more seeded as guidelines-only — and a loader
    /// that quietly dead-ends is how the previous build shipped a game where fifteen of sixteen
    /// paths went nowhere. The validator names them so the gap stays visible.
    public struct Gap: Sendable, Equatable {
        public let from: String
        public let optionIndex: Int
        public let optionText: String
        public let missingID: String
        public let kind: Kind
        public enum Kind: Sendable, Equatable { case absent, stub }
    }

    public func validate() -> [Gap] {
        var gaps: [Gap] = []
        for id in nodes.keys.sorted() {
            guard let node = nodes[id], !node.isTerminal else { continue }
            for (i, text) in node.options.enumerated() {
                let childID = node.childID(forOption: i + 1)
                if let child = nodes[childID] {
                    if child.isStub {
                        gaps.append(Gap(from: id, optionIndex: i + 1, optionText: text,
                                        missingID: childID, kind: .stub))
                    }
                } else {
                    gaps.append(Gap(from: id, optionIndex: i + 1, optionText: text,
                                    missingID: childID, kind: .absent))
                }
            }
        }
        return gaps
    }

    /// Node ids reachable from the root by following options through nodes that actually exist.
    public func reachableIDs() -> Set<String> {
        var seen: Set<String> = []
        var frontier = [rootID]
        while let id = frontier.popLast() {
            guard nodes[id] != nil, !seen.contains(id) else { continue }
            seen.insert(id)
            guard let node = nodes[id], !node.isTerminal else { continue }
            for i in 1...max(node.options.count, 0) where !node.options.isEmpty {
                frontier.append(node.childID(forOption: i))
            }
        }
        return seen
    }

    /// Total words of dialogue, for the honest content accounting.
    public var wordCount: Int {
        nodes.values.reduce(0) { total, node in
            total + node.lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
            + node.finalWords.values.reduce(0) { $0 + $1.split(separator: " ").count }
        }
    }
}
