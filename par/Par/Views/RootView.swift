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

        /// The stable slug the capture pipeline uses — `rawValue` carries spaces and an ampersand.
        public var slug: String {
            switch self {
            case .tvm: return "tvm"
            case .amortization: return "amortization"
            case .cashFlow: return "cashflow"
            case .bond: return "bond"
            case .rate: return "rate"
            case .depreciation: return "depreciation"
            case .dates: return "dates"
            case .percent: return "percent"
            case .statistics: return "statistics"
            case .realEstate: return "realestate"
            }
        }

        /// The tool named by `PAR_TOOL`, if any. Nil when the variable is unset or unrecognised —
        /// a typo in a capture script must not silently show the wrong screen.
        static var launchTool: Tool? {
            guard let slug = ProcessInfo.processInfo.environment["PAR_TOOL"] else { return nil }
            return Tool.allCases.first { $0.slug == slug }
        }
    }

    @Binding private var document: TapeDocument
    @State private var tool: Tool
    // `PAR_TAPE=1` opens straight onto the tape. On iPhone it is a sheet, so a screenshot of it has
    // to be asked for; on iPad it is already beside the calculator and this changes nothing.
    @State private var isTapePresented = ProcessInfo.processInfo.environment["PAR_TAPE"] == "1"
    @State private var isReferencePresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(document: Binding<TapeDocument>) {
        self._document = document
        // `PAR_TOOL=bond` opens straight onto a tool. Used by the screenshot and reel pipelines so a
        // capture lands on the right screen without a scripted tap, and by the UI tests that pin
        // those deep links. Unset in normal use, where the app opens on TVM.
        _tool = State(initialValue: Tool.launchTool ?? .tvm)
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
        // The tool selection is `@State` here, which `.commands` cannot reach — the reason eleven
        // menu items shipped with empty closures. Publishing it to the focused scene is what makes
        // ⌘1…⌘0 real.
        .focusedSceneValue(\.toolSelection, $tool)
    }

    // MARK: - Compact: the tape is a second surface, reachable without losing
    // what is being typed. The last solve always peeks above the keypad.

    private var compactLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                SubScreenPicker(
                    options: Tool.allCases.map { ($0, $0.rawValue) },
                    selection: $tool,
                    identifier: "tool.picker"
                )
                referenceButton
                    .padding(.trailing, 10)
            }
            .padding(.vertical, 8)

            screen

            if let last = document.rows.last {
                TapePeekStrip(row: last) { isTapePresented = true }
            }
        }
        .sheet(isPresented: $isTapePresented) {
            // A drag indicator alone is not a dismissal affordance: it is discoverable only if you
            // already know the gesture. The explicit Done button is what a one-handed user on a job
            // site reaches for — and it is what makes the tape reachable and leaveable in a tour.
            TapeView(document: $document) { isTapePresented = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isReferencePresented) {
            ReferenceView { isReferencePresented = false }
        }
    }

    // MARK: - Regular: the tape sits BESIDE the calculator. Two of the
    // incumbents' fatal reviews are about exactly this.

    /// Sources, conventions and the two known table discrepancies. Reachable from every screen:
    /// "which convention did it use" is the question paid calculators lose their ratings over.
    private var referenceButton: some View {
        Button {
            isReferencePresented = true
        } label: {
            Label("Reference", systemImage: "checkmark.shield")
                .font(.subheadline)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(Par.Palette.labelSecondary)
        .frame(minWidth: Par.Metrics.minHitTarget, minHeight: Par.Metrics.minHitTarget)
        .accessibilityIdentifier("reference.open")
        .accessibilityLabel("Reference: sources, conventions and known discrepancies")
    }

    private var sidebarSelection: Binding<Tool?> {
        Binding(get: { tool }, set: { if let new = $0 { tool = new } })
    }

    private var regularLayout: some View {
        NavigationSplitView {
            // A sidebar selection is optional on iOS (a split view can have nothing selected), so
            // the binding maps through, refusing to leave the detail pane empty on a deselect.
            List(Tool.allCases, id: \.self, selection: sidebarSelection) { item in
                Text(item.rawValue).tag(item)
                    .accessibilityIdentifier("sidebar.tool.\(item.rawValue)")
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 260)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    referenceButton
                        .labelStyle(.titleAndIcon)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .sheet(isPresented: $isReferencePresented) {
                ReferenceView { isReferencePresented = false }
            }
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
        case .amortization: AmortizationScreen(document: $document)
        case .cashFlow: CashFlowScreen(document: $document)
        case .bond: BondScreen(document: $document)
        case .rate: RateScreen(document: $document)
        case .depreciation: DepreciationScreen(document: $document)
        case .dates: DayCountScreen(document: $document)
        case .percent: PercentScreen(document: $document)
        case .statistics: StatisticsScreen(document: $document)
        case .realEstate: RealEstateScreen(document: $document)
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
            .background(Par.Palette.surface, in: RoundedRectangle(cornerRadius: Par.Metrics.rowRadius, style: .continuous))
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
