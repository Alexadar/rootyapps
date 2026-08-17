import Foundation

/// Prints a finished reading in the exact shape `will-i-be-rich.scenario.yaml` wants, so the
/// text a scenario replays is REAL model output copied verbatim off the device that wrote it —
/// never hand-written prose dressed up as a reading.
///
/// Why a print and not a file: the capture device is a phone or an iPad, and stdout comes back
/// over `devicectl … --console` without any container spelunking or a share sheet. Wrapped in
/// unmistakable markers because the console around it is full of RealityKit chatter.
///
/// The body is `#if DEBUG` and gated again on the launch flag, so a Release build prints
/// nothing and a Debug build prints only when it was asked to capture.
enum ScenarioCapture {

    static func dump(_ draft: PassageDraft) {
        #if DEBUG
        guard LaunchOverride.present("-TAROT_SCENARIO_LIVE") else { return }
        var out = "SCENARIO_YAML_BEGIN\npassages:\n"
        for passage in draft.passages {
            out += "  - |\n" + block(passage, indent: "    ")
        }
        if let synthesis = draft.synthesis {
            out += "synthesis: |\n" + block(synthesis, indent: "  ")
        }
        out += "SCENARIO_YAML_END"
        print(out)
        #endif
    }

    /// A YAML block scalar: one paragraph, wrapped on word boundaries so the file stays
    /// readable in review. The model's own newlines collapse to spaces — a passage is one
    /// paragraph by contract, and a stray newline mid-passage would change the indent and
    /// silently end the block.
    private static func block(_ text: String, indent: String, width: Int = 88) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        var current = ""
        for word in flat.split(separator: " ") {
            if current.isEmpty { current = String(word) }
            else if current.count + word.count + 1 > width { lines.append(current); current = String(word) }
            else { current += " " + word }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.map { indent + $0 + "\n" }.joined()
    }
}
