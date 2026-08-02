import SwiftUI

/// Label this solve, and put it on the tape.
///
/// This used to be a `ToolbarItem`. Nine of the ten screens had no other way to append, and
/// `RootView.compactLayout` is a bare `VStack` with no navigation container of its own — so whether
/// the control existed at all on iPhone rested entirely on `DocumentGroup` supplying an implicit
/// navigation bar. Under `PAR_CAPTURE` it demonstrably does not, which is why no screenshot or reel
/// frame ever showed it. A row that cannot be appended is a calculator that cannot keep its tape,
/// which is the entire product.
///
/// So it lives in the body now: same control, same place, every platform and every width, visible in
/// a screenshot and reachable by a test. It also publishes the append action to the focused scene,
/// which is what lets the Mac's ⌘⌥S do the same thing.
public struct AppendToTapeBar: View {
    @Binding private var label: String
    private let canAppend: Bool
    private let identifier: String
    private let append: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(label: Binding<String>, canAppend: Bool, identifier: String,
                append: @escaping () -> Void) {
        self._label = label
        self.canAppend = canAppend
        self.identifier = identifier
        self.append = append
    }

    public var body: some View {
        // In a compact width the bar scrolls with the content, which is fine: a phone screen is
        // short and the bar is never far. A regular width is where this went wrong — on a 1440x900
        // Mac window the scroll content runs past 2,500pt, so the bar sat below the fold and a click
        // landed outside the window entirely. Nine of ten screens could not reach their own tape.
        //
        // There, `RootView` pins it instead (see `regularLayout`), and this renders nothing but still
        // publishes the command — so there is exactly one bar on screen either way.
        if horizontalSizeClass == .compact {
            content
        } else {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
                .focusedSceneValue(\.appendToTape, command)
        }
    }

    /// The bar itself, so the pinned copy and the inline copy cannot drift apart.
    @ViewBuilder
    public var content: some View {
        HStack(spacing: 8) {
            TextField("Label this solve", text: $label)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Par.Palette.label)
                .accessibilityIdentifier("\(identifier).label")

            Button {
                append()
                label = ""              // the next solve starts unnamed, not inheriting the last
            } label: {
                Label("Add to tape", systemImage: "plus.rectangle.on.rectangle")
                    .font(.subheadline.weight(.medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAppend ? Par.Palette.accent : Par.Palette.labelQuaternary)
            .disabled(!canAppend)
            .accessibilityIdentifier("\(identifier).append")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(minHeight: Par.Metrics.minHitTarget)
        .glassCard(radius: 16)
        .focusedSceneValue(\.appendToTape, command)
    }

    private var command: AppendCommand? {
        canAppend ? AppendCommand(id: identifier, label: $label, run: append) : nil
    }
}

/// A screen's append action, published to the focused scene so the Mac menu bar can invoke it.
///
/// `Equatable` by identifier rather than by closure — closures are not comparable, and SwiftUI needs
/// to know whether the focused value changed. The identifier is stable per screen, so it does.
public struct AppendCommand: Equatable {
    public let id: String
    /// The row label, so a pinned bar rendered elsewhere edits the same string the screen owns.
    public let label: Binding<String>
    public let run: () -> Void

    public static func == (lhs: AppendCommand, rhs: AppendCommand) -> Bool { lhs.id == rhs.id }
}

public struct AppendToTapeKey: FocusedValueKey {
    public typealias Value = AppendCommand
}

public struct ToolSelectionKey: FocusedValueKey {
    public typealias Value = Binding<RootView.Tool>
}

public extension FocusedValues {
    var appendToTape: AppendCommand? {
        get { self[AppendToTapeKey.self] }
        set { self[AppendToTapeKey.self] = newValue }
    }

    /// The tool picker's selection, so ⌘1…⌘0 can drive it. `RootView` owns it as `@State`, which is
    /// unreachable from `.commands` — the reason eleven menu items shipped with empty closures.
    var toolSelection: Binding<RootView.Tool>? {
        get { self[ToolSelectionKey.self] }
        set { self[ToolSelectionKey.self] = newValue }
    }
}
