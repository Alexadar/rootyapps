import SwiftUI

/// The adaptive shell. This is the wedge: it must genuinely work on iPhone
/// (portrait AND landscape), iPad at every column width including Split View and
/// Slide Over, and a Mac window dragged small. Nothing fixed-width, nothing that
/// assumes a full-screen iPad, nothing that clips a control off-screen.
public struct RootView: View {
    public enum Tool: String, CaseIterable, Hashable {
        case tvm = "TVM"
        case amortization = "Amortization"
        case cashFlow = "Cash Flow"
        case bond = "Bond"
        case rate = "Rate & APR"
        case depreciation = "Depreciation"
        case dates = "Dates"
        case percent = "Percent"
        case statistics = "Statistics"
        case realEstate = "Real Estate"
    }

    @Binding private var document: TapeDocument
    @State private var tool: Tool = .tvm
    @State private var isTapePresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout          // iPhone, iPad Slide Over, narrow Split View
            } else {
                regularLayout          // iPad landscape, Mac
            }
        }
        .background(Par.Palette.base)
        .parAppearance()
    }

    // MARK: - Compact: the tape is a second surface, reachable without losing
    // what is being typed. The last solve always peeks above the keypad.

    private var compactLayout: some View {
        VStack(spacing: 0) {
            SubScreenPicker(
                options: Tool.allCases.map { ($0, $0.rawValue) },
                selection: $tool,
                identifier: "tool.picker"
            )
            .padding(.vertical, 8)

            screen

            if let last = document.rows.last {
                TapePeekStrip(row: last) { isTapePresented = true }
            }
        }
        .sheet(isPresented: $isTapePresented) {
            TapeView(document: $document)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Regular: the tape sits BESIDE the calculator. Two of the
    // incumbents' fatal reviews are about exactly this.

    private var regularLayout: some View {
        NavigationSplitView {
            List(Tool.allCases, id: \.self, selection: $tool) { item in
                Text(item.rawValue).tag(item)
                    .accessibilityIdentifier("sidebar.tool.\(item.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 260)
        } detail: {
            HStack(spacing: 0) {
                screen
                    .frame(minWidth: 380, maxWidth: .infinity)
                Divider().overlay(Par.Palette.separator)
                TapeView(document: $document)
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch tool {
        case .tvm: TVMScreen(document: $document)
        default:
            ContentUnavailableView(
                tool.rawValue,
                systemImage: "function",
                description: Text("Screen scaffolded on the same primitives — see README.")
            )
            .accessibilityIdentifier("screen.placeholder.\(tool.rawValue)")
        }
    }
}

/// The peeking strip: a solve is never a dead end, and the tape is never fully
/// out of sight on a phone.
public struct TapePeekStrip: View {
    private let row: TapeRow
    private let onTap: () -> Void

    public init(row: TapeRow, onTap: @escaping () -> Void) {
        self.row = row
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("Tape").font(.caption).foregroundStyle(Par.Palette.labelSecondary)
                Text(row.label.isEmpty ? row.inputs.toolName : row.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(Par.Palette.labelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Par.Metrics.minHitTarget)
            .frame(maxWidth: .infinity)
            .background(Par.Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Par.Metrics.gutter)
        .padding(.bottom, 8)
        .accessibilityIdentifier("tape.peek")
        .accessibilityLabel("Open the tape. Last solve: \(row.label.isEmpty ? row.inputs.toolName : row.label)")
    }
}

#Preview("Root — regular width") {
    RootView(document: .constant(TapeDocument(title: "Refi comparison — Alvarez")))
}

#Preview("Root — compact width") {
    RootView(document: .constant(TapeDocument(title: "Refi comparison — Alvarez")))
        .environment(\.horizontalSizeClass, .compact)
}
