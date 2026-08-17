import Foundation
import Observation
import TarotKit

/// Drives one reading's interpretation: checks availability, streams the passages, keeps
/// whatever partial text arrived if the stream dies. Fully testable — the writer is injected,
/// so every availability branch and a mid-stream interruption run under `swift test` with no
/// model anywhere near.
@MainActor
@Observable
final class ReadingComposer {

    enum State: Equatable {
        case idle
        /// The draw works regardless; only the written passage is missing.
        case unavailable(WriterAvailability)
        case writing(PassageDraft)
        case finished(PassageDraft)
        /// Mid-stream failure: show what arrived, say it stopped, offer retry.
        case failed(partial: PassageDraft)
        /// The on-device model declined this draw even in safe mode. Said honestly;
        /// the cards stand on their own.
        case declined
    }

    private(set) var state: State = .idle
    /// Debug-only diagnostic surfaced in the UI while the app has no proper error reporting.
    private(set) var lastErrorDescription: String?
    private var task: Task<Void, Never>?

    func start(reading: Reading, deck: Deck, spread: Spread, writer: ReadingWriter) {
        cancel()
        guard writer.availability == .available else {
            state = .unavailable(writer.availability)
            return
        }
        state = .writing(PassageDraft())
        let stream = writer.write(reading: reading, deck: deck, spread: spread)
        task = Task { @MainActor in
            var latest = PassageDraft()
            do {
                for try await draft in stream {
                    guard !Task.isCancelled else { return }
                    latest = draft
                    state = .writing(draft)
                }
                state = .finished(latest)
                ScenarioCapture.dump(latest)
            } catch is WriterDeclined {
                guard !Task.isCancelled else { return }
                state = .declined
            } catch {
                guard !Task.isCancelled else { return }
                lastErrorDescription = String(describing: error)
                state = .failed(partial: latest)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}
