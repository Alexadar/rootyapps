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
/// blank, or one that has fallen into repetition. Retryable, not fatal.
struct IncompleteDraft: Error, Equatable {}

/// The only real `ReadingWriter`: Apple's on-device Foundation Models framework, and nothing
/// else. No network, no bundled meanings, no fallback text.
@MainActor
final class FoundationModelsWriter: ReadingWriter {

    /// The generation currently in flight, and the session running it.
    ///
    /// `ReadingComposer.cancel()` cancels its own Task, but cancelling a Swift Task does not abort
    /// the request already inside the model service — it keeps working. So a second draw started
    /// while the first was still generating queued behind it and appeared to produce nothing.
    /// Holding both here lets a new draw actively stand down the old one instead of racing it.
    private var inFlight: Task<Void, Never>?
    private var inFlightSession: LanguageModelSession?

    /// True while the model is still answering. `isResponding` is on the session in the SDK; the
    /// framework also has a `GenerationError.concurrentRequests` case, which is Foundation Models
    /// saying plainly that overlapping requests are a real failure and not merely slow.
    var isGenerating: Bool { inFlightSession?.isResponding ?? false }

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
                temperature: 0.8,
                // The ceiling that makes a runaway impossible rather than merely unlikely.
                maximumResponseTokens: WritingLimits.maximumTokens(for: spread))
        }

        // Stand the previous generation down BEFORE starting a new one. Cancelling is not
        // instant — the service finishes or aborts on its own schedule — so wait briefly for the
        // session to stop responding rather than firing a second request into a busy service.
        inFlight?.cancel()
        let previous = inFlightSession

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                if let previous, previous.isResponding {
                    for _ in 0..<30 {                       // up to ~3 s, then proceed regardless
                        if !previous.isResponding { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                var updateCount = 0
                let language = Self.readingLanguage()
                let expectedPassages = spread.positions.count
                let expected = WritingLimits.expectedCharacters(for: spread)
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
                        // Stop the moment a new draw begins. `ReadingComposer.cancel()` cancels
                        // this task, but without an explicit check the loop keeps consuming the
                        // stream and keeps the request alive; breaking out lets the stream
                        // deinitialise and releases the model service for the next draw. This is
                        // the difference between "the old reading stops" and "the new one never
                        // starts", which is how the bug presented on device.
                        if Task.isCancelled { throw CancellationError() }
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
                    // Repetition is a different failure from a blank, and it reaches the reader
                    // looking like a finished reading. Judge the whole text, not each passage:
                    // the loop often spans the boundary, repeating the same sentence across a
                    // passage and the synthesis.
                    let whole = (final.passages + [final.synthesis ?? ""]).joined(separator: " ")
                    if WritingLimits.isDegenerate(whole, expectedCharacters: expected) {
                        throw IncompleteDraft()
                    }
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
                    // Silence watchdog: nothing at all for 25 s means the service stalled.
                    let watchdog = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 25_000_000_000)
                        if updateCount == before { inner.cancel() }
                    }
                    // TOTAL-duration watchdog. The silence watchdog cannot catch a runaway,
                    // because a repetition loop keeps producing tokens — `updateCount` climbs
                    // steadily while the reading never ends. That is exactly the failure seen on
                    // device, and it is why an unbounded generation could hold the model service
                    // and starve the next draw. No legitimate reading takes ninety seconds.
                    let deadline = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 90_000_000_000)
                        inner.cancel()
                    }
                    defer { watchdog.cancel(); deadline.cancel() }
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
                        self.inFlightSession = session
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
                    } catch is CancellationError {
                        // A new draw replaced this one. Not a failure, and emphatically not
                        // something to retry — retrying would start a fresh request for a reading
                        // nobody is waiting for any more, and starve the draw that replaced it.
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
                        self.inFlightSession = fresh
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
            self.inFlight = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
