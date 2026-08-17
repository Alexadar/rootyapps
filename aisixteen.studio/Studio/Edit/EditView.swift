import SwiftUI
import RecipeKit

/// The editor (`1b` → `1c` → `1d`), in one view because they are one screen.
///
/// The photo is full-bleed and every control floats over it in a single glass panel. There is no
/// prompt field, no aspect picker, no filter strip — the photo is the subject and the chrome is a
/// guest on top of it.
struct EditView: View {

    @Environment(\.stAccessibility) private var accessibility
    @Environment(\.colorScheme) private var scheme

    @Bindable var model: EditModel
    /// iPad and Mac put the controls in a column instead of a bottom sheet.
    var layout: EditLayout = .stacked
    var onExport: () -> Void
    var onOpenLibrary: () -> Void

    enum EditLayout { case stacked, sideColumn, toolbar }

    var body: some View {
        ZStack {
            canvas
            switch layout {
            case .stacked:    stackedControls
            case .sideColumn: sideColumn
            case .toolbar:    toolbarControls
            }
        }
        .background(LinearGradient(colors: ST.canvasGradient, startPoint: .top, endPoint: .bottom))
        .task { await model.prepareMask(for: model.scope) }
    }

    // MARK: The photo

    private var canvas: some View {
        ZStack {
            // ⚠️ The veil is handed to the comparison rather than laid over it, so it touches the
            // enhanced side **only**. Over the whole canvas it also veils the original, and then the
            // split compares mush against mush for the entire wait — deleting the one thing that
            // makes a tile-by-tile enhance legible.
            //
            // It is a *view* treatment, not baked into the pixels, so the real pipeline's
            // intermediates inherit it unchanged. Under Reduce Motion the blur steps down in three
            // discrete jumps instead of easing: the picture still visibly clears, which is content
            // changing, without a continuously animating blur, which is motion.
            ComparisonView(original: model.original,
                           enhanced: model.displayImage,
                           comparison: $model.comparison,
                           showsHandle: !model.isShowingOriginalOnly || model.phase.isRunning,
                           veil: veil)

            // Painting replaces the hold-to-compare gesture only while Brush is the active scope,
            // and never while a pass is running.
            if model.scope == .brush && !model.phase.isRunning {
                BrushOverlay(model: model)
            }
        }
        .ignoresSafeArea()
    }

    /// The board's values, unscaled: white `.22`, blur 26 → 0 pt.
    private var veil: ComparisonView.Veil? {
        guard model.phase.isRunning else { return nil }
        return ComparisonView.Veil(
            opacity: model.veilOpacity,
            blur: STMotion.veilBlur(model.veilBlur, initial: 26,
                                    reduceMotion: accessibility.reduceMotion))
    }

    // MARK: iPhone — one floating panel at the bottom (1b)

    private var stackedControls: some View {
        VStack {
            HStack {
                Button(action: onOpenLibrary) {
                    Label("Library", systemImage: "chevron.left")
                        .stFont(.control)
                        .foregroundStyle(ST.ink(scheme))
                        .padding(.horizontal, ST.Space.gap)
                        .frame(height: ST.pillHeight)
                }
                .buttonStyle(.plain)
                .stGlassCapsule(.regular)
                .accessibilityIdentifier("edit.back")

                Spacer()
                holdAffordance
            }
            .padding(.horizontal, ST.Space.margin)

            Spacer()
            panel
                .padding(.horizontal, ST.Space.grid)
                .padding(.bottom, ST.Space.grid)
        }
    }

    /// The panel itself — identical content in every layout, only the frame changes.
    private var panel: some View {
        VStack(spacing: ST.Space.grid) {
            ScopeSegment(selection: $model.scope,
                         compact: layout != .stacked,
                         availability: { scope in
                             scope == model.scope ? model.maskAvailability : .ready
                         })

            if let blocked = model.maskAvailability.blockingMessage {
                Text(blocked)
                    .stFont(.footnote)
                    .foregroundStyle(ST.ink2(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("edit.scope.blocked")
            }

            StrengthSlider(strength: $model.strength,
                           isLive: model.recipe.hasVisibleEnhancement,
                           needsRerun: model.needsRerun)

            EnhanceMorph(model: model,
                         onEnhance: { model.enhance() },
                         onCancel: { model.cancel() },
                         onSave: onExport,
                         onRevert: { model.revert() })
        }
        .padding(ST.Space.margin)
        .stGlassCard(.regular, radius: ST.Radius.card)
    }

    private var holdAffordance: some View {
        Text(Comparison.holdAffordance)
            .stFont(.footnote)
            .foregroundStyle(ST.ink2(scheme))
            .padding(.horizontal, ST.Space.gap)
            .frame(height: ST.compactPillHeight)
            .stGlassCapsule(.regular, shadow: false)
            .accessibilityHidden(true)
    }

    // MARK: iPad — a floating right column (1g)

    private var sideColumn: some View {
        HStack {
            VStack {
                holdAffordance
                Spacer()
            }
            .padding(.leading, ST.Space.margin)
            .padding(.top, ST.Space.margin)

            Spacer()

            panel
                .frame(width: 340)
                .padding(.trailing, ST.Space.margin)
        }
    }

    // MARK: Mac — one glass toolbar (1h)

    private var toolbarControls: some View {
        VStack {
            Spacer()
            HStack(spacing: ST.Space.grid) {
                ScopeSegment(selection: $model.scope,
                             compact: true,
                             availability: { scope in
                                 scope == model.scope ? model.maskAvailability : .ready
                             })
                .frame(width: 340)

                StrengthSlider(strength: $model.strength,
                               isLive: model.recipe.hasVisibleEnhancement,
                               needsRerun: model.needsRerun)
                .frame(width: 260)

                EnhanceMorph(model: model,
                             onEnhance: { model.enhance() },
                             onCancel: { model.cancel() },
                             onSave: onExport,
                             onRevert: { model.revert() })
                .frame(width: 300)
            }
            .padding(ST.Space.grid)
            .stGlassCard(.regular, radius: ST.Radius.card)
            .padding(.bottom, ST.Space.margin)
        }
    }
}
