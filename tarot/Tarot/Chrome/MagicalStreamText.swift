import SwiftUI

/// Text that materializes like ink on a conjured scroll: a reveal frontier advances
/// smoothly through the string at reading pace — decoupled from the model's chunky stream
/// updates — and the newest characters carry a golden, fading edge that cools into ink as
/// they age. The movie effect, built from nothing but an AttributedString tail.
///
/// Reduce Motion collapses it to plain text (no frontier, no shimmer).
struct MagicalStreamText: View {
    let text: String
    var font: Font = Tokens.body(16)
    var color: Color = Tokens.ink
    var italic: Bool = false
    /// Called whenever the frontier advances — the parent uses it to glide the scroll.
    var onAdvance: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: Double = 0
    @State private var lastTick: Date?

    /// Characters the golden edge spans while materializing.
    private let tailLength = 26
    /// Base reveal pace (chars/second) — a comfortable reading speed; when the model runs
    /// ahead, the frontier hurries to catch up rather than falling cinematic-ally behind.
    private let basePace: Double = 55

    private var revealedCount: Int { min(text.count, Int(revealed)) }
    /// The frontier runs one tail-length PAST the end, so the golden edge cools fully to
    /// ink before the animation stops — otherwise the last sentence freezes mid-fade.
    private var finished: Bool { revealed >= Double(text.count + tailLength) }

    var body: some View {
        if reduceMotion {
            styled(Text(text))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                    paused: finished)) { timeline in
                styled(Text(attributed))
                    .onChange(of: timeline.date) { _, now in
                        advance(to: now)
                    }
            }
            .onChange(of: text) { _, newValue in
                // A retry clears the draft; the frontier must never point past the end.
                revealed = min(revealed, Double(newValue.count))
            }
        }
    }

    private func styled(_ text: Text) -> some View {
        (italic ? text.italic() : text)
            .font(font)
            .foregroundStyle(color)
    }

    private func advance(to now: Date) {
        defer { lastTick = now }
        guard let lastTick else { return }
        let dt = min(now.timeIntervalSince(lastTick), 0.2)
        let target = Double(text.count + tailLength)   // overshoot = the cool-down
        guard revealed < target else { return }
        // Hurry when far behind, but stay cinematic: with generation starting at draw
        // start the text often arrives fully written, and 160 chars/s keeps the reveal
        // a performance rather than a paste. The cool-down past the end runs at base pace.
        let textLag = max(0, Double(text.count) - revealed)
        let pace = max(basePace, min(textLag * 0.8, 160))
        revealed = min(target, revealed + pace * dt)
        onAdvance?()
    }

    private var attributed: AttributedString {
        let visible = revealedCount
        guard visible > 0 else { return AttributedString() }
        let characters = Array(text.prefix(visible))
        // Age is distance from the (possibly overshooting) frontier — so once the frontier
        // runs past the end, the whole tail finishes cooling to solid ink.
        let solidEnd = max(0, min(visible, Int(revealed) - tailLength))

        var result = AttributedString(String(characters[0..<solidEnd]))
        result.foregroundColor = color

        // The materializing edge: each newer character is fainter and more golden,
        // dissolving to nothing at the frontier.
        for index in solidEnd..<visible {
            let age = min(1.0, (revealed - Double(index)) / Double(tailLength))
            var glyph = AttributedString(String(characters[index]))
            glyph.foregroundColor = Color(
                red: 0.93 - 0.05 * age, green: 0.90 - 0.13 * (1 - age), blue: 0.84 - 0.49 * (1 - age)
            ).opacity(0.15 + 0.85 * age)
            result += glyph
        }
        return result
    }
}

/// The writing indicator, without machinery: three stars breathe in sequence while the
/// label shimmers between ink and gold. No spinner — nothing in this panel should look
/// like a system control. Honest wording stays ("on this Mac/device"); only the clothes
/// are magical. Reduce Motion: still stars, plain label.
struct MagicalWritingIndicator: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            row(phase: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                row(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func row(phase: Double?) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let twinkle = phase.map { 0.45 + 0.55 * pow(sin($0 * 2.1 + Double(index) * 2.1), 2) } ?? 0.7
                    Text("✶")
                        .font(Tokens.body(13))
                        .foregroundStyle(Tokens.gold.opacity(twinkle))
                        .scaleEffect(0.85 + 0.25 * twinkle)
                }
            }
            let shimmer = phase.map { 0.5 + 0.5 * sin($0 * 1.3) } ?? 0
            Text(label)
                .font(Tokens.body(13))
                .foregroundStyle(Color(
                    red: 0.68 + 0.20 * shimmer,
                    green: 0.65 + 0.07 * shimmer,
                    blue: 0.62 - 0.27 * shimmer))
        }
    }
}
