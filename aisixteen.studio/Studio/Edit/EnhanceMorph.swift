import SwiftUI
import RecipeKit
import EnhanceKit

/// **The morph** (`1b` → `1c` → `1d`): Enhance → progress → Save.
///
/// ### The capsule never leaves
///
/// It is the identified object and it persists through every state. It starts as *Enhance*, widens
/// into *Enhancing · step 9 of 20* with Cancel inside and the tint drained to neutral, and becomes
/// *Save…* when the pass lands. Failure stops it, drains the tint and morphs it into the card.
/// Cancel plays the whole thing in reverse and the photo returns untouched.
///
/// ### The three things that break this silently
///
/// 1. **`GlassEffectContainer` is a stable ancestor** — declared here, above the branch, never
///    rebuilt. Put it inside the `switch` and every morph degrades to a plain fade, with nothing
///    else looking wrong.
/// 2. **`@Namespace` lives here too.** Recreated per body evaluation, every frame gets a fresh
///    identity and the effect is the same silent fade.
/// 3. **Every branch carries the glass *and* the same `glassEffectID`.** Different shapes, widths
///    and tints are the point; the identity must not vary.
struct EnhanceMorph: View {

    @Environment(\.stAccessibility) private var accessibility
    @Environment(\.colorScheme) private var scheme
    @Namespace private var jobNamespace

    var model: EditModel
    var onEnhance: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void
    var onRevert: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: ST.Space.gap) {
            switch model.morphStage {
            case .enhance:  enhanceCapsule
            case .progress: progressCapsule
            case .save:     saveRow
            case .failure:  failureCard
            }
        }
        .animation(STMotion.morph(reduceMotion: accessibility.reduceMotion), value: model.morphStage)
    }

    // MARK: t = 0

    private var enhanceCapsule: some View {
        Button(action: onEnhance) {
            Text(model.needsRerun ? "Enhance again" : "Enhance")
                .stFont(.button)
                .foregroundStyle(GlassLabel.color(on: model.canEnhance ? .tinted : .regular,
                                                  scheme: scheme,
                                                  enabled: model.canEnhance))
                .frame(maxWidth: .infinity)
                .frame(height: ST.primaryCapsuleHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canEnhance)
        .job(role: model.canEnhance ? .tinted : .regular, shape: Capsule(),
             in: jobNamespace, reduceMotion: accessibility.reduceMotion)
        .accessibilityIdentifier("edit.enhance")
        .accessibilityLabel("Enhance")
        .accessibilityHint(enhanceHint)
    }

    private var enhanceHint: String {
        if let blocked = model.maskAvailability.blockingMessage { return blocked }
        if model.strength.isZero { return "Raise the strength first" }
        return "Enhances the \(model.scope.displayName.lowercased()) at \(model.strength.displayName)"
    }

    // MARK: Running — the tint drains, Cancel appears inside

    private var progressCapsule: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(ST.accent.opacity(0.28))
                    .frame(width: model.progressFraction * proxy.size.width)
                    .animation(STMotion.progressFill, value: model.progressFraction)
            }

            HStack(spacing: 0) {
                Spacer()
                Text(model.stepLabel)
                    .stFont(.control, tabularNumbers: true)
                    .foregroundStyle(ST.ink(scheme).opacity(0.78))
                    // The label crossfades rather than sliding: the capsule does not move, only what
                    // it says changes.
                    .contentTransition(.opacity)
                    .id(model.stepLabel)
                Spacer()
                cancelCircle
            }
            .padding(.trailing, ST.Space.tight)
        }
        .frame(height: ST.primaryCapsuleHeight)
        .frame(maxWidth: .infinity)
        // ⚠️ `.regular`, not `.tinted` — this is the tint draining to neutral, and it is the whole
        // reason the running state reads as calm rather than urgent.
        .job(role: .regular, shape: Capsule(), in: jobNamespace,
             reduceMotion: accessibility.reduceMotion)
        .animation(.easeInOut(duration: 0.2), value: model.stepLabel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edit.progress")
        .accessibilityLabel(model.stepLabel)
    }

    private var cancelCircle: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ST.ink(scheme).opacity(0.7))
                .frame(width: ST.minimumHitTarget, height: ST.minimumHitTarget)
                .background(ST.ink(scheme).opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityIdentifier("edit.cancel")
        .accessibilityLabel("Cancel")
        .accessibilityHint("Stops the pass. Your photo is unchanged.")
    }

    // MARK: Complete — Save…, with Revert always beside it

    private var saveRow: some View {
        HStack(spacing: ST.Space.gap) {
            Button(action: onRevert) {
                Text("Revert")
                    .stFont(.button)
                    .foregroundStyle(ST.ink(scheme))
                    .frame(height: ST.primaryCapsuleHeight)
                    .padding(.horizontal, ST.Space.margin)
            }
            .buttonStyle(.plain)
            .stGlassCapsule(.regular)
            .accessibilityIdentifier("edit.revert")
            .accessibilityHint("Throws the enhancement away. Your photo was never changed.")

            Button(action: onSave) {
                Text("Save…")
                    .stFont(.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: ST.primaryCapsuleHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .job(role: .tinted, shape: Capsule(), in: jobNamespace,
                 reduceMotion: accessibility.reduceMotion)
            .accessibilityIdentifier("edit.save")
        }
    }

    // MARK: Failure

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: ST.Space.gap) {
            Text(EnhanceError.failureHeading)
                .stFont(.cardHeading)
                .foregroundStyle(ST.ink(scheme))

            if case .failed(let error) = model.phase, let reason = error.displayReason {
                Text(reason)
                    .stFont(.body)
                    .foregroundStyle(ST.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(EnhanceError.failureReassurance)
                .stFont(.caption)
                .foregroundStyle(ST.ink3(scheme))

            HStack(spacing: ST.Space.gap) {
                Button("Try again", action: onEnhance)
                    .buttonStyle(.glassProminent)
                    .tint(ST.accent)
                Button("Not now") { model.dismissFailure() }
                    .buttonStyle(.glass)
            }
            .stFont(.control)
            .padding(.top, ST.Space.hair)
        }
        .padding(ST.Space.margin)
        .frame(maxWidth: 380, alignment: .leading)
        .job(role: .regular,
             shape: RoundedRectangle(cornerRadius: ST.Radius.frame, style: .continuous),
             in: jobNamespace,
             reduceMotion: accessibility.reduceMotion)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edit.failure")
    }
}

private extension View {
    /// Applies the job's glass and its identity together.
    ///
    /// One helper rather than two modifiers at each call site, because forgetting the identity on a
    /// single branch is invisible in code review and subtle on screen.
    func job<S: Shape>(role: GlassRole,
                       shape: S,
                       in namespace: Namespace.ID,
                       reduceMotion: Bool) -> some View {
        self
            .stGlass(role, in: shape)
            .glassEffectID("job", in: namespace)
            .glassEffectTransition(STMotion.glassTransition(reduceMotion: reduceMotion))
    }
}
