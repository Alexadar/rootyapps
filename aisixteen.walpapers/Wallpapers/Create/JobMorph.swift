import SwiftUI

/// **The morph** (bundle `1b`, `5a`, `5b`): Create button → waking → progress → result.
///
/// ### The capsule never leaves
///
/// Board `5a` settles what the original spec left ambiguous: the capsule is the identified object,
/// and it persists through every state. It starts as *Create*, becomes *Waking the model…*, becomes
/// *Step N of 28* with a fill that appears from zero, and finally becomes *Save for Wallpaper*.
/// Nothing resizes or repositions between waking and the first step — only the label crossfades. The
/// unmeasurable wait and the measurable one are visibly the same object, which is what makes the
/// honesty read as design rather than apology.
///
/// The picture frame is a separate layer that appears beneath it once there is something to show.
///
/// ### The three things that break this silently
///
/// 1. **`GlassEffectContainer` is a stable ancestor** — declared here, above the branch, never
///    rebuilt. Put it inside the `switch` and every morph degrades to a plain fade, with nothing
///    else looking wrong.
/// 2. **`@Namespace` lives here too.** Recreated per body evaluation, every frame gets a fresh
///    identity and the effect is the same silent fade.
/// 3. **Every branch carries the glass *and* the same `glassEffectID`.** Different shapes, sizes and
///    tints are the point; the identity must not vary.
struct JobMorph: View {
    @Environment(\.wpAccessibility) private var accessibility
    @Environment(\.colorScheme) private var scheme

    @Namespace private var jobNamespace

    var model: CreateModel
    var onStart: () -> Void
    var onCancel: () -> Void
    var onPrimaryAction: () -> Void
    var onShare: () -> Void
    var onRegenerate: () -> Void
    var onRetry: () -> Void
    var onEditPrompt: () -> Void
    /// "Save for Wallpaper" on iOS, "Set as Desktop" on the Mac. The verb is the platform's truth.
    var primaryActionTitle: String
    /// Stage 3. `nil` when the tile models are not installed, in which case no control appears —
    /// better than a button that explains why it cannot work.
    /// Built by one factory shared with the Gallery. `nil` means Enhance cannot be offered here.
    var enhance: EnhanceAffordance?

    var body: some View {
        GlassEffectContainer(spacing: WP.Space.gap) {
            switch model.morphStage {
            case .button:   createCapsule
            case .waking:   wakingLayout
            case .progress: progressLayout
            case .result:   resultFrame
            case .failure:  failureCard
            }
        }
        // Stage 4 — the arrival at full-bleed — gets its own faster spring. See `stageChange`.
        .animation(WPMotion.stageChange(toResult: model.morphStage == .result,
                                        reduceMotion: accessibility.reduceMotion),
                   value: model.morphStage)
    }

    // MARK: t = 0 — the Create button

    private var createCapsule: some View {
        Text("Create")
            .wpFont(.button)
            .foregroundStyle(GlassLabel.color(on: model.canStart ? .tinted : .regular,
                                              scheme: scheme,
                                              enabled: model.canStart))
            .frame(maxWidth: .infinity)
            .frame(height: WP.primaryCapsuleHeight)
            .contentShape(Capsule())
            // Always tappable. `onStart` is the shell's `createTapped`, which starts when it can
            // and explains when it cannot — a tap that does nothing at all reads as a broken button.
            .onTapGesture { onStart() }
            .job(role: model.canStart ? .tinted : .regular, shape: Capsule(), in: jobNamespace,
                 reduceMotion: accessibility.reduceMotion)
            .accessibilityElement()
            .accessibilityLabel("Create")
            .accessibilityHint(model.canStart ? "Makes a wallpaper from your prompt"
                                              : "Type a prompt first")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Waking (5a) — an unmeasurable wait

    private var wakingLayout: some View {
        VStack(spacing: WP.Space.margin) {
            pictureFrame {
                VStack(spacing: 20) {
                    BreathingArc()
                    // Past ~3 s a single quiet line explains why, and promises it is a one-time
                    // cost. Nothing else changes: no escalating spinner, no countdown that would
                    // break the promise of calm.
                    if model.wakingIsSlow {
                        Text("First wallpaper of the session takes a moment — the model is loading into memory. The next ones are instant.")
                            .wpFont(.caption)
                            .foregroundStyle(WP.ink3(scheme))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 220)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: model.wakingIsSlow)
            }
            jobCapsule(fraction: nil, label: model.stepText, showsCancel: model.wakingIsSlow)
        }
    }

    // MARK: Running — the picture forms, the capsule counts

    private var progressLayout: some View {
        VStack(spacing: WP.Space.margin) {
            pictureFrame { formingPicture }
            jobCapsule(fraction: model.fraction, label: model.stepText, showsCancel: true)
        }
    }

    /// The 300 × 540 r32 frame. Present from the first moment of a run — empty white glass while the
    /// model wakes, then the emerging latents.
    private func pictureFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: 300, height: 540)
            .wpGlassCard(radius: WP.Radius.frame)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.stepText)
    }

    /// **The identified object.** Create → Waking → Step N → Save for Wallpaper, one identity.
    ///
    /// - Parameter fraction: `nil` while the model is loading. There is no honest number then, so
    ///   there is no fill — an indeterminate bar here would be the app's only fake progress.
    private func jobCapsule(fraction: Double?, label: String, showsCancel: Bool) -> some View {
        ZStack(alignment: .leading) {
            if let fraction {
                GeometryReader { proxy in
                    Capsule()
                        .fill(WP.accent.opacity(0.30))
                        .frame(width: fraction * proxy.size.width)
                        .animation(WPMotion.progressFill, value: fraction)
                }
                .transition(.opacity)
            }

            HStack(spacing: 0) {
                Spacer()
                Text(label)
                    .wpFont(.control, tabularNumbers: true)
                    .foregroundStyle(WP.ink(scheme).opacity(0.75))
                    // The label crossfades rather than sliding: the capsule does not move, only
                    // what it says changes.
                    .contentTransition(.opacity)
                    .id(label)
                    .transition(.opacity)
                Spacer()
                if showsCancel { cancelCircle } else { Color.clear.frame(width: 0) }
            }
            .padding(.trailing, showsCancel ? WP.Space.tight : 0)
        }
        .frame(width: 300, height: WP.primaryCapsuleHeight)
        .job(role: .regular, shape: Capsule(), in: jobNamespace,
             reduceMotion: accessibility.reduceMotion)
        .animation(.easeInOut(duration: 0.2), value: label)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var cancelCircle: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WP.ink(scheme).opacity(0.7))
                .frame(width: WP.minimumHitTarget, height: WP.minimumHitTarget)
                .background(WP.ink(scheme).opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityLabel("Stop")
    }

    /// The emerging image, under the milk veil.
    ///
    /// The veil is a *view* treatment, not baked into the pixels — so the real pipeline's latents
    /// inherit it unchanged. Under Reduce Motion the blur steps down in three discrete jumps instead
    /// of easing: the picture still visibly clears, which is content changing, without a
    /// continuously animating blur, which is motion.
    @ViewBuilder
    private var formingPicture: some View {
        if let preview = model.preview {
            Image(platformImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 300, height: 540)
                .clipped()
                .blur(radius: WPMotion.veilBlur(model.veilBlur,
                                                initial: 26,
                                                reduceMotion: accessibility.reduceMotion),
                      opaque: true)
                .overlay(Color.white.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: WP.Radius.frame, style: .continuous))
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    // MARK: Complete (5b) — three ways out

    private var resultFrame: some View {
        ZStack(alignment: .bottom) {
            // The refinement in flight outranks the stored picture: this is what makes an Enhance
            // visibly do something for the minute it runs.
            if let finished = model.enhancePreview ?? model.finished {
                GeometryReader { proxy in
                    Image(platformImage: finished)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        // Fills and clips, so the displayed rect *is* the container — no fitted-rect
                        // maths needed on this door.
                        .overlay { enhanceVeil }
                }
                .accessibilityLabel(model.prompt)
            }
            resultControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .job(role: .regular, shape: Rectangle(), in: jobNamespace,
             reduceMotion: accessibility.reduceMotion)
        .ignoresSafeArea()
        // Exit ①. Board 5b: the finished picture must never be a dead end — a version without this
        // shipped, and the only remaining action was re-running the same prompt forever.
        .overlay(alignment: .topLeading) {
            Button(action: onEditPrompt) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WP.ink(scheme).opacity(0.8))
                    .frame(width: WP.minimumHitTarget, height: WP.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .wpGlass(.regular, in: Circle())
            .padding(.leading, 16)
            .padding(.top, 70)
            .accessibilityLabel("Back to Create")
        }
    }

    /// The tile grid, drawn over the picture while Enhance runs. See `EnhanceVeil`.
    @ViewBuilder
    private var enhanceVeil: some View {
        if let enhance, enhance.isRunning, let progress = enhance.progress, progress.total > 0 {
            EnhanceVeil(done: progress.done, total: progress.total, imageSize: nil)
        }
    }

    private var resultControls: some View {
        VStack(spacing: WP.Space.gap) {
            promptPlate

            // One treatment, both doors — the identical component the Gallery detail sheet shows.
            EnhanceControls(affordance: enhance)

            ResultActionBar(primaryTitle: primaryActionTitle,
                            onPrimary: onPrimaryAction,
                            collapsesExtras: enhance != nil,
                            overflow: [
                                .init(label: "Make another from this prompt",
                                      symbol: "arrow.clockwise", action: onRegenerate),
                                .init(label: "Share", symbol: "square.and.arrow.up", action: onShare),
                            ])

            Text("Saved to your \(model.finishedRecord == nil ? "device" : "iCloud folder")")
                .wpFont(.footnote)
                .foregroundStyle(WP.ink(scheme).opacity(0.7))
                .padding(.horizontal, WP.Space.gap)
                .padding(.vertical, WP.Space.hair + 2)
                .wpGlassCapsule(.regular, shadow: false)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 120)
    }

    /// Exit ③, and the app's real loop. *Tweak* was called "Use again" and sat in the gallery; board
    /// `5b` promotes it here and renames it, because changing one word and re-rolling is what people
    /// actually do with a generator — it should be the path of least resistance, not a detour
    /// through another screen.
    private var promptPlate: some View {
        Button(action: onEditPrompt) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(WP.ink(scheme).opacity(0.6))
                Text(model.prompt)
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink(scheme).opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text("Tweak")
                    .wpFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(WP.ink(scheme))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(WP.ink(scheme).opacity(0.08), in: Capsule())
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .wpGlassCapsule(.regular)
        .accessibilityLabel("Edit the prompt")
        .accessibilityValue(model.prompt)
    }

    private func circleAction(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(WP.ink(scheme).opacity(0.8))
                .frame(width: WP.smallCircleButton, height: WP.smallCircleButton)
        }
        .buttonStyle(.plain)
        .wpGlass(.regular, in: Circle())
        .accessibilityLabel(label)
    }

    // MARK: Failure

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: WP.Space.gap) {
            Text("That one didn't come together")
                .wpFont(.cardHeading)
                .foregroundStyle(WP.ink(scheme))
            if case .failed(let reason) = model.phase {
                Text(reason)
                    .wpFont(.body)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Nothing was lost — your prompt is still here.")
                .wpFont(.caption)
                .foregroundStyle(WP.ink3(scheme))

            HStack(spacing: WP.Space.gap) {
                Button("Try again", action: onRetry)
                    .buttonStyle(.glassProminent)
                    .tint(WP.accent)
                Button("Edit prompt", action: onEditPrompt)
                    .buttonStyle(.glass)
            }
            .wpFont(.control)
            .padding(.top, WP.Space.hair)
        }
        .padding(WP.Space.margin)
        .frame(maxWidth: 360, alignment: .leading)
        .job(role: .regular,
             shape: RoundedRectangle(cornerRadius: WP.Radius.frame, style: .continuous),
             in: jobNamespace,
             reduceMotion: accessibility.reduceMotion)
        .accessibilityElement(children: .contain)
    }
}

/// The indeterminate arc for the waking state (board `5a`).
///
/// A conic gradient that turns slowly and breathes, **not a system spinner** — a spinner reads as
/// "busy, briefly" and gets more agitating the longer it runs, which is the opposite of what an
/// eight-second wait needs. It communicates *working, duration unknown* and stays calm at both
/// 400 ms and 8 s. Honours Reduce Motion by holding still: an indeterminate indicator has no
/// information in its movement, so removing it costs nothing.
struct BreathingArc: View {
    @Environment(\.wpAccessibility) private var accessibility
    @State private var turning = false
    @State private var breathing = false

    /// The waking frame wants it large; a checklist row wants it at the size of a checkmark.
    /// Additive, so no existing call site changes.
    var side: CGFloat = 66

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(colors: [WP.accent.opacity(0), WP.accent.opacity(0.55)],
                                center: .center),
                style: StrokeStyle(lineWidth: side > 40 ? 5 : 2.5, lineCap: .round))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .opacity(breathing ? 1 : 0.55)
            .onAppear {
                guard !accessibility.reduceMotion else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    turning = true
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
            .accessibilityHidden(true)
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
            .wpGlass(role, in: shape)
            .glassEffectID("job", in: namespace)
            .glassEffectTransition(WPMotion.glassTransition(reduceMotion: reduceMotion))
    }
}
