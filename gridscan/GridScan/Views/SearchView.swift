import SwiftUI

// Search — tier one is retrieval + citation ONLY. Results show WHAT matched; tapping
// lands on the document. The v2 generated-answer layer (AnswerCard) is NOT built:
// there is deliberately no "answer" surface in this target. The app answers from the
// user's documents and must never appear to know anything else.
struct SearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searchedCount = 0
    @State private var openDocumentID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !query.isEmpty && results.isEmpty {
                    nothingFound
                } else {
                    ForEach(results) { hit in
                        row(hit)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Search")
        .navigationDestination(item: $openDocumentID) { id in
            DocumentView(documentID: id)
        }
        .searchable(text: $query, prompt: "Search your documents")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            results = (try? await env.store.search(query)) ?? []
            searchedCount = (try? await env.store.summaries().count) ?? 0
        }
    }

    private func row(_ hit: SearchHit) -> some View {
        Button { openDocumentID = hit.documentID } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(hit.documentTitle).font(.headline)
                    if hit.hasUnresolvedFlags {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(GS.flag)
                    }
                    Spacer()
                    Text(hit.location).font(.footnote).foregroundStyle(.secondary)
                }
                (Text("matched: ").foregroundStyle(.secondary)
                    + Text(hit.matchedText).fontWeight(.semibold))
                    .font(.subheadline)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GS.surface, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.result.\(hit.documentID.uuidString)")
    }

    private var nothingFound: some View {
        ContentUnavailableView {
            Label("Nothing in your library matches this.", systemImage: "circle.slash")
        } description: {
            // Never apologetic. Never suggests the web.
            Text("Searched \(searchedCount) document(s) on this device. Try different words.")
        }
        .accessibilityIdentifier("search.nothingFound")
    }
}
