import Foundation
import FoundationModels
import TarotKit

/// The written reading, as structured output — one concrete form per method, because
/// `@Generable`/`@Guide` descriptions must be string literals and `.count(n)` puts the
/// passage arity in the SCHEMA, where constrained decoding enforces it (the retry ladder
/// stays a backstop, not the arity mechanism — at ten passages prompt-only counting
/// drifts). All four map onto the same `PassageDraft`, so the ladder is written once.
protocol WrittenForm: Generable {
    static func draft(from partial: Self.PartiallyGenerated) -> PassageDraft
}

@Generable(description: "A reflective note on a single drawn tarot card.")
struct WrittenReadingOne: WrittenForm {
    @Guide(description: "One reflective passage on the drawn card, five or six sentences.", .count(1))
    var passages: [String]

    static func draft(from partial: PartiallyGenerated) -> PassageDraft {
        PassageDraft(passages: (partial.passages ?? []).compactMap { $0 }, synthesis: nil)
    }
}

@Generable(description: "A reflective reading of a three-card tarot draw.")
struct WrittenReadingThree: WrittenForm {
    @Guide(description: "One reflective paragraph for each card, in the order the cards were given.", .count(3))
    var passages: [String]
    @Guide(description: "Two or three sentences weaving the three cards into one reflection.")
    var synthesis: String

    static func draft(from partial: PartiallyGenerated) -> PassageDraft {
        PassageDraft(passages: (partial.passages ?? []).compactMap { $0 },
                     synthesis: partial.synthesis)
    }
}

@Generable(description: "A reflective reading of a five-card tarot draw.")
struct WrittenReadingFive: WrittenForm {
    @Guide(description: "One reflective paragraph for each card, in the order the cards were given.", .count(5))
    var passages: [String]
    @Guide(description: "Two or three sentences weaving the five cards into one reflection.")
    var synthesis: String

    static func draft(from partial: PartiallyGenerated) -> PassageDraft {
        PassageDraft(passages: (partial.passages ?? []).compactMap { $0 },
                     synthesis: partial.synthesis)
    }
}

@Generable(description: "A reflective reading of a ten-card tarot draw.")
struct WrittenReadingTen: WrittenForm {
    @Guide(description: "One brief reflection for each card, two or three sentences each, in the order the cards were given.", .count(10))
    var passages: [String]
    @Guide(description: "Three or four sentences drawing the ten cards into one reflection.")
    var synthesis: String

    static func draft(from partial: PartiallyGenerated) -> PassageDraft {
        PassageDraft(passages: (partial.passages ?? []).compactMap { $0 },
                     synthesis: partial.synthesis)
    }
}

/// A draft that parsed but is not a reading: the right number of passages, one of them
/// blank. Retryable, not fatal.
struct IncompleteDraft: Error, Equatable {}

/// The only real `ReadingWriter`: Apple's on-device Foundation Models framework, and nothing
/// else. No network, no bundled meanings, no fallback text.
@MainActor
final class FoundationModelsWriter: ReadingWriter {

    var availability: WriterAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            // Future SDKs may add reasons; the closest honest bucket is "not ready".
            return .modelNotReady
        }
    }

    /// The one rule for the reading's language: it must MATCH what the reader sees
    /// (owner, 2026-08-17 — "localized OR English, so the generated text matches").
    /// Start from the language the UI actually renders (the bundle's resolved
    /// localization, not the system locale — a Polish phone renders this app in English,
    /// so its readings must be English too), then require the on-device model to
    /// genuinely support it. Anything else falls back to English — the reading and the
    /// chrome then agree again.
    static func readingLanguage() -> String? {
        let rendered = Bundle.main.preferredLocalizations.first ?? "en"
        let code = Locale(identifier: rendered).language.languageCode?.identifier ?? "en"
        guard code != "en" else { return nil }
        guard SystemLanguageModel.default.supportedLanguages.contains(where: {
            $0.languageCode?.identifier == code
        }) else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }

    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        // The method picks its form ONCE; everything downstream is generic over it.
        switch spread.positions.count {
        case 1: run(WrittenReadingOne.self, reading: reading, deck: deck, spread: spread)
        case 5: run(WrittenReadingFive.self, reading: reading, deck: deck, spread: spread)
        case 10: run(WrittenReadingTen.self, reading: reading, deck: deck, spread: spread)
        default: run(WrittenReadingThree.self, reading: reading, deck: deck, spread: spread)
        }
    }

    private func run<T: WrittenForm>(_ form: T.Type, reading: Reading, deck: Deck,
                                     spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        let instructions = ReadingPrompt.instructions(deck: deck, spread: spread)
        // A seed bump gives a parsing retry genuinely different tokens to sample — the
        // usual cure when guided generation fails to decode. Stays inside the measured
        // Int32.max service boundary.
        func options(seedBump: UInt64) -> GenerationOptions {
            GenerationOptions(
                sampling: reading.interpretationSeed.map {
                    GenerationOptions.SamplingMode.random(top: 40, seed: ($0 &+ seedBump) & 0x7FFF_FFFF)
                },
                temperature: 0.8)
        }

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                var updateCount = 0
                let language = Self.readingLanguage()
                let expectedPassages = spread.positions.count
                @MainActor func attempt(session: LanguageModelSession, safe: Bool,
                                        seedBump: UInt64) async throws {
                    let prompt = ReadingPrompt.prompt(reading: reading, deck: deck,
                                                      spread: spread, safe: safe,
                                                      language: language)
                    let stream = session.streamResponse(to: Prompt(prompt),
                                                        generating: T.self,
                                                        options: options(seedBump: seedBump))
                    var final = PassageDraft()
                    for try await partial in stream {
                        updateCount += 1
                        final = T.draft(from: partial.content)
                        continuation.yield(final)
                    }
                    // Guided generation sometimes satisfies `.count(n)` with a BLANK
                    // element — measured, and reproducible at specific sampling seeds: one
                    // run returned an empty first passage with the other two written. The
                    // schema is happy; the reading is not. Treat it as a failed attempt so
                    // the ladder re-rolls rather than showing a position with no words.
                    guard final.passages.count == expectedPassages,
                          !final.passages.contains(where: {
                              $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          }) else { throw IncompleteDraft() }
                }

                /// One attempt under a first-token watchdog. Measured on this Mac: the
                /// model service sometimes stalls a request indefinitely (or eventually
                /// fails it with ModelManagerError 1032) while a fresh session sails
                /// through — an attempt that produces nothing for 25 s is cancelled and
                /// the ladder moves on rather than hanging the reading forever.
                @MainActor func guardedAttempt(session: LanguageModelSession, safe: Bool,
                                               seedBump: UInt64 = 0) async throws {
                    let before = updateCount
                    let inner = Task { @MainActor in
                        try await attempt(session: session, safe: safe, seedBump: seedBump)
                    }
                    let watchdog = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 25_000_000_000)
                        if updateCount == before { inner.cancel() }
                    }
                    defer { watchdog.cancel() }
                    try await inner.value
                }

                func isRefusal(_ error: Error) -> Bool {
                    if let generation = error as? LanguageModelSession.GenerationError,
                       case .refusal = generation { return true }
                    return false
                }

                /// Guided generation occasionally produces output the schema can't decode —
                /// a pure parsing issue, cured by re-sampling with a different seed.
                func isParsingIssue(_ error: Error) -> Bool {
                    if error is IncompleteDraft { return true }
                    if let generation = error as? LanguageModelSession.GenerationError,
                       case .decodingFailure = generation { return true }
                    return false
                }

                // The ladder: up to three normal attempts — the first retry covers
                // transient service failures (fresh session), the second exists for pure
                // parsing issues (fresh session AND a bumped seed, so the model samples
                // different tokens). A guardrail refusal at any rung drops to the
                // safe-mode prompt; exhausted parsing/transient failures surface honestly.
                var refused = false
                var lastError: Error?
                for round in 0..<3 {
                    do {
                        let session = LanguageModelSession(instructions: instructions)
                        if round > 0 {
                            // A beat before re-rolling: back-to-back requests to the model
                            // service fare worse than spaced ones, and on screen the pause
                            // reads as thinking rather than as a stutter.
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            continuation.yield(PassageDraft())               // clear partial
                        }
                        try await guardedAttempt(session: session, safe: false,
                                                 seedBump: UInt64(round))
                        continuation.finish()
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        lastError = error
                        if isRefusal(error) { refused = true; break }
                        if round == 0 { continue }               // one retry for anything
                        if isParsingIssue(error), round < 2 { continue }
                        break
                    }
                }
                if !refused {
                    continuation.finish(throwing: lastError ?? WriterDeclined())
                    return
                }
                // Refusal rung: the label table catches the cases we measured; this
                // all-nameless prompt catches the ones it didn't predict (OS updates
                // shift the classifier; reader questions add free text). Two rounds here
                // too — a transient or parsing failure on the safe prompt must not
                // masquerade as a decline.
                for round in 0..<2 {
                    do {
                        continuation.yield(PassageDraft())       // clear any partial
                        let fresh = LanguageModelSession(instructions: instructions)
                        try await guardedAttempt(session: fresh, safe: true,
                                                 seedBump: 7 &+ UInt64(round))
                        continuation.finish()
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        if isRefusal(error) || round == 1 {
                            continuation.finish(throwing: WriterDeclined())
                            return
                        }
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
