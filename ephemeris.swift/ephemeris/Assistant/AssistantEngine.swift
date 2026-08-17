import Foundation
import FoundationModels
import EphemerisKit

/// The on-device assistant: one question, one answer, grounded in the screen.
///
/// ## Single turn, enforced by construction
///
/// A fresh `LanguageModelSession` per question, and no transcript is ever carried. That is the
/// requested shape, and it also removes the failure mode that would otherwise dominate: the context
/// window is **4,096 tokens shared between prompt and answer**, so a conversation would spend its
/// budget on its own history and start refusing after a handful of turns.
///
/// ## Answers explain; they never compute
///
/// Every number the model may state is one this app computed and handed it. The instructions say so
/// and the sheet says so. An engine oracle-tested against NASA/JPL to arcminutes must not have a
/// language model inventing a degree beside it — that would poison the one thing this app can prove.
///
/// ## Nothing leaves the device
///
/// `SystemLanguageModel.default` only. Private Cloud Compute is deliberately not used: this app is
/// offline and paid-upfront and holds birth data, and a feature that quietly posted someone's birth
/// time to a server would contradict the entire product.
@MainActor
final class AssistantEngine: ObservableObject {

    /// Why the assistant cannot answer, in the user's terms rather than the framework's.
    enum Unavailable: Equatable {
        case deviceNotEligible
        case appleIntelligenceOff
        case modelNotReady
        case languageNotSupported(String)

        var message: String {
            switch self {
            case .deviceNotEligible:
                String(localized: "This device cannot run Apple Intelligence, so the explanation feature is unavailable here.")
            case .appleIntelligenceOff:
                String(localized: "Turn on Apple Intelligence in Settings to use explanations.")
            case .modelNotReady:
                String(localized: "Apple Intelligence is still downloading. Try again shortly.")
            case .languageNotSupported(let name):
                String(localized: "Apple Intelligence does not yet support \(name), so explanations are unavailable in this language.")
            }
        }
    }

    @Published private(set) var answer: String?
    @Published private(set) var isAnswering = false
    @Published private(set) var failure: String?

    // MARK: - Availability

    /// Nil when the assistant can run.
    ///
    /// Checked at the point of use rather than cached: Apple Intelligence can be switched off, and
    /// the model can still be downloading, between one launch and the next.
    static func unavailableReason(locale: Locale = .current) -> Unavailable? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            // ⚠️ Availability is not the whole story for a sixteen-language app. The model supports
            // a subset of languages, and asking it to answer in one it does not know produces
            // `unsupportedLanguageOrLocale` mid-request — a failure the user would read as the
            // feature being broken rather than not offered.
            guard let language = locale.language.languageCode else { return nil }
            let supported = model.supportedLanguages.contains {
                $0.languageCode == language
            }
            guard supported else {
                let name = locale.localizedString(forLanguageCode: language.identifier)
                       ?? language.identifier
                return .languageNotSupported(name)
            }
            return nil
        case .unavailable(.deviceNotEligible):          return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
        case .unavailable(.modelNotReady):              return .modelNotReady
        case .unavailable:                              return .modelNotReady
        }
    }

    // MARK: - Asking

    /// How much of the window the answer may take.
    ///
    /// Reserved explicitly rather than hoped for. Prompt and response share 4,096 tokens, so a
    /// context that fills the window leaves nothing to answer with and the request fails on the
    /// model's own output — an error that looks like the question was too hard.
    static let answerTokenBudget = 700

    func ask(_ question: String, context: ScreenContext, locale: Locale = .current) async {
        answer = nil
        failure = nil
        isAnswering = true
        defer { isAnswering = false }

        if let reason = Self.unavailableReason(locale: locale) {
            failure = reason.message
            return
        }

        let session = LanguageModelSession(instructions: Self.instructions(locale: locale))
        let options = GenerationOptions(maximumResponseTokens: Self.answerTokenBudget)

        do {
            let prompt = try await Self.fittedPrompt(question: question, context: context)
            answer = try await session.respond(to: prompt, options: options).content
        } catch let error as LanguageModelSession.GenerationError {
            failure = Self.describe(error)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Builds the prompt and shrinks the context until it fits the window.
    ///
    /// ## Measured where possible, pessimistic where not
    ///
    /// `SystemLanguageModel.tokenCount(for:)` is the real tokenizer — but it arrived in **iOS 26.4**
    /// and this app deploys to 26.0, so it cannot simply be called. Where it exists it is used;
    /// where it does not, `estimatedTokens` stands in.
    ///
    /// That estimate is deliberately **pessimistic**. The usual rule of thumb is four characters per
    /// token, which is calibrated on English prose; this app's text is dense with glyphs, degree
    /// symbols and multi-byte astrological terms that tokenize far worse. An optimistic estimate
    /// would say "fits", and the request would then fail with `exceededContextWindowSize` — so the
    /// fallback assumes 2.5 characters per token and under-fills instead.
    static func fittedPrompt(question: String, context: ScreenContext) async throws -> String {
        // The window shared by prompt and answer, minus what the answer is allowed.
        let ceiling = 4096 - answerTokenBudget

        var rowLimit = context.rows.count
        var candidate = context
        while true {
            let text = prompt(question: question, context: candidate)
            let used = try await tokens(in: text)
            if used <= ceiling || rowLimit <= 1 { return text }
            // Drop the least-relevant row and re-measure. The rows are already ranked, so the last
            // one is by construction the most droppable.
            rowLimit -= 1
            candidate = candidate.droppingRows(to: rowLimit)
        }
    }

    /// Real token count where the API exists, a pessimistic estimate otherwise.
    static func tokens(in text: String) async throws -> Int {
        if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
            return try await SystemLanguageModel.default.tokenCount(for: text)
        }
        return estimatedTokens(in: text)
    }

    /// 2.5 characters per token — under-counts capacity on purpose. See `fittedPrompt`.
    static func estimatedTokens(in text: String) -> Int {
        Int((Double(text.count) / 2.5).rounded(.up))
    }

    static func prompt(question: String, context: ScreenContext) -> String {
        """
        \(context.promptText)

        QUESTION: \(question)
        """
    }

    // MARK: - Instructions

    static func instructions(locale: Locale = .current) -> String {
        let language = locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "en")
                     ?? "the user's language"
        return """
        You explain what is on the screen of an astronomy and astrology app.

        GROUNDING — the most important rule:
        Answer ONLY from the screen description you are given. Every number, date and position you \
        state must appear in it. If the answer is not there, say plainly that it is not on this \
        screen. Never calculate a position, a time or a chart yourself: the app has already computed \
        these against published astronomical data, and a figure you invent would contradict it.

        IF DATA WAS TRUNCATED:
        You may be shown only a few of many rows. When you are, say so, and never imply the list is \
        complete.

        REGISTER:
        Write for someone who may never have opened an astrology app before, in language a \
        practitioner would still consider correct. Define a term the first time you use it, briefly. \
        Do not be mystical, do not predict, and do not give advice about someone's life — describe \
        what the screen shows and what its terms mean.

        LENGTH: at most two short paragraphs.
        LANGUAGE: answer in \(language).
        """
    }

    // MARK: - Errors

    static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            // Should be unreachable — `fittedPrompt` measures before sending. If it happens, the
            // budgeting is wrong and saying so beats a generic apology.
            String(localized: "There was too much on this screen to summarise. Try asking about one part of it.")
        case .guardrailViolation, .refusal:
            String(localized: "Apple Intelligence declined to answer that one.")
        case .unsupportedLanguageOrLocale:
            String(localized: "Apple Intelligence does not support this language yet.")
        case .assetsUnavailable:
            String(localized: "Apple Intelligence is still downloading. Try again shortly.")
        case .rateLimited:
            String(localized: "Too many questions at once. Try again in a moment.")
        default:
            String(localized: "The explanation could not be generated.")
        }
    }
}

extension ScreenContext {
    /// A copy holding at most `limit` rows, with the omission updated to match.
    ///
    /// The omission is rewritten rather than left alone: shrinking the rows without correcting the
    /// count would tell the model "4 of 104" while showing it three, and the one thing this payload
    /// must never do is misstate its own completeness.
    func droppingRows(to limit: Int) -> ScreenContext {
        let kept = Array(rows.prefix(max(0, limit)))
        let total = omitted?.total ?? rows.count
        let ranking = omitted?.ranking ?? "relevance"
        return ScreenContext(
            screen: screen, gate: gate, situation: situation, schema: schema, rows: kept,
            omitted: kept.count < total
                ? .init(shown: kept.count, total: total, ranking: ranking)
                : nil)
    }
}
