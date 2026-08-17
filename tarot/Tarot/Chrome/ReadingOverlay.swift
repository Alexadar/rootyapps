import SwiftUI
import TarotKit

/// The reading: three cards named, the passage streaming in as it is written on device.
/// Tapping a card in the scene brings it forward in the immersive viewer (handled by the
/// 3D layer); this panel stays out of the top half of the screen for exactly that reason.
struct ReadingOverlay: View {
    @Environment(AppModel.self) private var model
    /// While the passage streams in, the panel glides along with it — until the reader
    /// scrolls by hand, which hands them the wheel for the rest of this reading.
    @State private var autoFollow = true
    /// The panel's two sizes: a strip over the cards while they're the point, the full
    /// space below the top bar once the text is (owner, 2026-08-17: "hard to read in
    /// tank mode"). Auto-expands when the writing finishes; the reader can toggle any
    /// time. Never overlays the top-bar buttons — expansion fills the VStack slot UNDER
    /// them; covering the cards is fine.
    @State private var expanded = false
    /// The scroll content's natural height, so an expanded panel that holds three short
    /// passages doesn't stretch into a half-screen of empty glass.
    @State private var contentHeight: CGFloat = 0

    private var writingFinished: Bool {
        if case .finished = model.composer.state { return true }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
        VStack {
            HStack {
                Button {
                    model.backToMenu()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(Tokens.label(16))
                        .padding(10)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("reading.menu")
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.45)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                        .font(Tokens.label(15))
                        .padding(10)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("reading.expand")
                Button {
                    model.startDraw()
                } label: {
                    Label("New Draw", systemImage: "sparkles")
                        .font(Tokens.label(15))
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("reading.newDraw")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer(minLength: 8)

            // Grow to the content, stop at the room available. Both numbers matter: the
            // ceiling keeps a ten-card reading scrollable instead of shoving the cards
            // off-screen, and the content fit keeps a short one from leaving a void.
            panel(maxHeight: max(220, geometry.size.height * 0.76))
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        }
        .onChange(of: writingFinished) { _, finished in
            // The result is the moment reading becomes the activity — open the room.
            if finished {
                withAnimation(.easeInOut(duration: 0.45)) { expanded = true }
            }
        }
    }

    /// Everything currently written — the auto-follow trigger. Grows monotonically while
    /// streaming, so each change is "new text arrived".
    private var writtenLength: Int {
        switch model.composer.state {
        case .writing(let draft), .finished(let draft), .failed(let draft):
            return draft.passages.reduce(0) { $0 + $1.count } + (draft.synthesis?.count ?? 0)
        default:
            return 0
        }
    }

    @ViewBuilder
    private func panel(maxHeight ceiling: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reading = model.reading {
                        if let question = reading.question {
                            Text("“\(question)”")
                                .font(Tokens.body(15))
                                .italic()
                                .foregroundStyle(Tokens.inkDim)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("reading.question")
                        }
                        cardsHeader(reading)
                        Divider().overlay(Tokens.gold.opacity(0.3))
                        passagesView(glide: {
                            guard autoFollow else { return }
                            withAnimation(.linear(duration: 0.3)) {
                                proxy.scrollTo("reading.bottom", anchor: .bottom)
                            }
                        })
                    }
                    Color.clear.frame(height: 1).id("reading.bottom")
                }
                .padding(18)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .onScrollPhaseChange { _, newPhase in
                // A drag is the reader taking over; programmatic glides report
                // `.animating`, so they never trip this.
                if newPhase == .interacting { autoFollow = false }
            }
            .onChange(of: writtenLength) {
                guard autoFollow, writtenLength > 0 else { return }
                withAnimation(.linear(duration: 0.9)) {
                    proxy.scrollTo("reading.bottom", anchor: .bottom)
                }
            }
            .onChange(of: model.reading?.id) {
                autoFollow = true
                expanded = false
            }
            // Text scrolling past the panel's edge was cut dead against the glass; a
            // short fade at both ends reads as "there is more here", which is what a
            // scroll actually means.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.035),
                                         .init(color: .black, location: 0.965),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .frame(height: min(max(contentHeight, 96), expanded ? ceiling : 340))
        .tarotGlassPanel()
        .accessibilityIdentifier("reading.panel")
    }

    private func cardsHeader(_ reading: Reading) -> some View {
        // The reading renders under ITS OWN method and deck — replaying a saved ten-card
        // cross must not borrow whatever the menu currently selects.
        let method = Spread.method(id: reading.spreadID)
        let deck = Deck.deck(id: reading.deckID)
        // Three across reads best; ten wraps into rows.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10),
                            count: min(reading.cards.count, 3))
        return LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
            ForEach(Array(reading.cards.enumerated()), id: \.offset) { index, drawn in
                VStack(spacing: 3) {
                    if method.positions.indices.contains(drawn.positionIndex) {
                        Text(L.loc(method.positions[drawn.positionIndex].name))
                            .font(Tokens.label(12))
                            .foregroundStyle(Tokens.inkDim)
                    }
                    Text(L.loc(deck.name(for: drawn.card)))
                        .font(Tokens.title(15))
                        .foregroundStyle(drawn.card.arcana == .major ? Tokens.gold : Tokens.ink)
                        .multilineTextAlignment(.center)
                    if drawn.orientation == .reversed {
                        Text(L.loc("Reversed"))
                            .font(Tokens.label(11))
                            .foregroundStyle(Tokens.inkDim)
                    }
                }
                // Top-aligned, or a card name that wraps to two lines drags its own
                // position label upward and the row's labels stop lining up (owner:
                // "labels not centered").
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("reading.card.\(index)")
            }
        }
    }

    @ViewBuilder
    private func passagesView(glide: @escaping () -> Void) -> some View {
        switch model.composer.state {
        case .idle:
            // The composer never started — with the toggle off, by the reader's own choice.
            if !model.interpretationsEnabled {
                Text("Interpretations are off.")
                    .font(Tokens.body(14))
                    .foregroundStyle(Tokens.inkDim)
                    .accessibilityIdentifier("reading.interpretationsOff")
            }
        case .unavailable(let reason):
            UnavailableNote(reason: reason)
        case .writing(let draft), .finished(let draft):
            draftView(draft, glide: glide)
            if case .writing = model.composer.state {
                MagicalWritingIndicator(label: writingLabel)
                    .accessibilityIdentifier("reading.writing")
            }
        case .declined:
            VStack(alignment: .leading, spacing: 8) {
                Text("The on-device writer declined this particular draw.")
                    .font(Tokens.body(15)).foregroundStyle(Tokens.ink)
                Text("Your cards stand as drawn — this reflection is yours to make.")
                    .font(Tokens.body(14)).foregroundStyle(Tokens.inkDim)
            }
            .accessibilityIdentifier("reading.declined")
        case .failed(let partial):
            draftView(partial, glide: glide)
            HStack(spacing: 12) {
                Text("The writing stopped partway.")
                    .font(Tokens.body(14))
                    .foregroundStyle(Tokens.inkDim)
                Button("Try again") {
                    if let reading = model.reading {
                        model.composer.start(reading: reading,
                                             deck: Deck.deck(id: reading.deckID),
                                             spread: Spread.method(id: reading.spreadID),
                                             writer: model.writer)
                    }
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("reading.retry")
            }
            #if DEBUG
            if let probe = model.fmProbeStatus {
                Text(probe)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.gold)
                    .textSelection(.enabled)
            }
            if let detail = model.composer.lastErrorDescription {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.inkDim)
                    .textSelection(.enabled)
            }
            #endif
        }
    }

    private func draftView(_ draft: PassageDraft, glide: @escaping () -> Void) -> some View {
        let positions = Spread.method(id: model.reading?.spreadID ?? "three-card").positions
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(draft.passages.enumerated()), id: \.offset) { index, passage in
                // An empty passage draws a gold position heading with nothing under it.
                // Guided generation really does return one sometimes — seen live, with the
                // model filling passages 1 and 2 and leaving 0 blank.
                if !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if model.reading?.cards.indices.contains(index) == true,
                   positions.indices.contains(index) {
                    Text(L.loc(positions[index].name))
                        .font(Tokens.label(13))
                        .foregroundStyle(Tokens.gold.opacity(0.9))
                }
                MagicalStreamText(text: passage, onAdvance: glide)
                    .accessibilityIdentifier("reading.passage.\(index)")
                }
            }
            if let synthesis = draft.synthesis, !synthesis.isEmpty {
                Divider().overlay(Tokens.gold.opacity(0.2))
                MagicalStreamText(text: synthesis, italic: true, onAdvance: glide)
                    .accessibilityIdentifier("reading.synthesis")
            }
        }
    }

    private var writingLabel: String {
        // Interpolated strings can't be catalog keys (ephemeris trap #4) — two full keys.
        #if os(macOS)
        L.loc("Being written on this Mac, as you watch…")
        #else
        L.loc("Being written on this device, as you watch…")
        #endif
    }
}

/// Three different absences, three different messages, three different actions.
struct UnavailableNote: View {
    let reason: WriterAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Short and action-first (owner, 2026-08-17). Three reasons stay distinct —
            // "enable" would be a false promise on ineligible hardware. No public deep
            // link to the Apple Intelligence pane exists (verified); naming the path is
            // the honest action.
            switch reason {
            case .available:
                EmptyView()
            case .deviceNotEligible:
                Text(notSupportedLine)
                    .font(Tokens.body(15)).foregroundStyle(Tokens.ink)
            case .notEnabled:
                Text("Enable Apple Intelligence for interpretations.")
                    .font(Tokens.body(15)).foregroundStyle(Tokens.ink)
                Text("Settings → Apple Intelligence & Siri")
                    .font(Tokens.body(13)).foregroundStyle(Tokens.inkDim)
            case .modelNotReady:
                Text("Apple Intelligence is still downloading — interpretations will appear once it's ready.")
                    .font(Tokens.body(15)).foregroundStyle(Tokens.ink)
            }
        }
        .accessibilityIdentifier("reading.unavailable")
    }

    private var notSupportedLine: String {
        // Interpolated strings can't be catalog keys (ephemeris trap #4) — two full keys.
        #if os(macOS)
        L.loc("Interpretations require Apple Intelligence — not supported on this Mac.")
        #else
        L.loc("Interpretations require Apple Intelligence — not supported on this device.")
        #endif
    }
}
