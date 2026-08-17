import SwiftUI

// Search & Ask — one surface, two depths.
// TIER ONE (ships first): search only — retrieval with citation; a result
// shows what matched and lands on it. This is the primary documented state.
// V2: the generated-answer layer (AnswerCard below) — opt-in on top of
// retrieval, every statement must cite. Nothing else changes when it lands.
struct SearchAskView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var answer: CitedAnswer?     // V2 layer — always nil in tier one
    let answersAvailable: Bool                   // false on ineligible hardware

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !answersAvailable && query.looksLikeQuestion {
                    // The reduced state is a finished experience, not an error screen.
                    QuietCard(title: "Answers need a newer device.",
                              subtitle: "Search still finds everything in your library.")
                }
                if let answer { AnswerCard(answer: answer) }
                if results.isEmpty && !query.isEmpty {
                    NothingFoundView(searchedCount: 214)   // where trust is won or lost
                } else {
                    ForEach(results) { SearchResultRow(result: $0) }
                }
            }
            .padding(24)
        }
        .searchable(text: $query, prompt: "Search your documents")
    }
}

// A result must show WHAT matched; tapping lands on the matched content.
struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        Button { result.openAtMatch() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(result.documentTitle).font(.headline)
                    if result.hasUnresolvedFlags {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(GS.flag)
                    }
                    Spacer()
                    Text(result.meta).font(.footnote).foregroundStyle(.secondary)
                }
                (Text("matched: ") + result.matchedText.highlighted()) // field/value/date, not a filename
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// ── V2 ────────────────────────────────────────────────────────────────
// Generated answers are a V2 layer on top of tier-one search.
// Every generated sentence carries a citation the user can open.
// An uncited sentence is not rendered. Ever.
struct AnswerCard: View {
    let answer: CitedAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ANSWER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("· generated on this \(deviceNoun())").font(.caption).foregroundStyle(.tertiary)
            }
            FlowText(sentences: answer.citedSentences) // each sentence + tappable numbered chip
            Text("Every statement cites a passage. Open a citation to see the source.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

struct NothingFoundView: View {
    let searchedCount: Int

    var body: some View {
        ContentUnavailableView {
            Label("Nothing in your library matches this.", systemImage: "circle.slash")
        } description: {
            Text("Searched \(searchedCount) documents on this \(deviceNoun()). Try different words, or widen the date range.")
            // Never apologetic. Never suggests the web. The app answers from
            // the user's documents and must never appear to know anything else.
        } actions: {
            Button("Any date") {}
            Button("Search similar words") {}
        }
    }
}
