import PhotosUI
import SwiftUI

/// Capture — the front door.
///
/// Chrome follows the handoff exactly; everything behind it is new. All three buttons there had
/// empty actions, there was no AVFoundation, and `coach` / `shotUsable` were `@State` constants
/// that nothing ever changed.
struct CaptureView: View {

    @Bindable var model: CaptureModel
    let onShot: (SourceShot) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false

    var body: some View {
        // A GeometryReader, and the width it hands out is used explicitly.
        //
        // ⚠️ The obvious shape — a ZStack with the preview behind and a VStack of chrome in front —
        // was measured on device and does NOT work here: the chrome column receives no width, so
        // every `Spacer()` in it collapses and any control pinned to an edge draws nothing at all
        // while still reserving its space. Centred, self-sizing elements look perfectly fine, which
        // is why a green test suite and a casual glance both miss it. Taking the width from a
        // GeometryReader and applying it removes the ambiguity entirely.
        GeometryReader { geometry in
            ZStack {
                CameraPreview(session: model.session)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                VStack(spacing: 0) {
                    // Clears the shell's floating Redesign · Library segment, which the root
                    // overlays in the same stack. Too little here and the two capsules collide.
                    modePicker
                        .padding(.top, ARC.shellSegmentClearance)
                    Spacer(minLength: ARC.Space.grid)
                    coachCapsule
                    Spacer(minLength: ARC.Space.grid)
                    controls
                        // Clears the home indicator. `geometry.safeAreaInsets` reports zero once
                        // the reader itself is inside `.ignoresSafeArea()`, so this is explicit.
                        .padding(.bottom, 44)
                }
                .frame(width: geometry.size.width - ARC.Space.wide * 2,
                       height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .background(ARC.canvas)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .alert("Couldn't take that photo",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.clearError() } })) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // ── mode ─────────────────────────────────────────────────────────────────────────────────

    /// Interior vs Exterior is chosen HERE, not later, because it changes two things: the coach
    /// copy (you back away from a facade; you cannot back away from a wall) and the preset set on
    /// the next screen.
    private var modePicker: some View {
        GlassSegment(options: DirectionMode.allCases,
                     selection: $model.mode,
                     title: \.title,
                     identifier: { "capture.mode.\($0.rawValue)" },
                     accessibilityLabel: "Space type")
    }

    // ── coach ────────────────────────────────────────────────────────────────────────────────

    private var coachCapsule: some View {
        StatusCapsule(tone: model.coach.isUsable ? .good : .caution,
                      text: model.coach.text,
                      identifier: "capture.coach")
            .accessibilityLabel(model.coach.isUsable
                                ? "Shot is usable. \(model.coach.text)"
                                : model.coach.text)
            .animation(.easeInOut(duration: 0.2), value: model.coach)
    }

    // ── controls ─────────────────────────────────────────────────────────────────────────────

    /// Shutter centred, import leading, flip trailing.
    ///
    /// A ZStack with an overlaid HStack rather than `HStack { a; Spacer(); b; Spacer(); c }`.
    /// The spacer form centres the middle item only when the two outer items happen to be the
    /// same width, and — measured on device — the leading item did not render at all in that
    /// arrangement. This shape does not depend on either coincidence: the shutter is centred
    /// because it is centred, and the side controls are pinned to the edges.
    private var controls: some View {
        ZStack {
            if model.canCapture { shutter } else { importPrompt }

            HStack(spacing: 0) {
                importButton
                Spacer(minLength: 0)
                if model.canSwitchCamera { flipButton }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76)
    }

    private var importButton: some View {
        Group {
            #if os(iOS)
            // A plain Button plus `.photosPicker(isPresented:)`, NOT `PhotosPicker { label }`.
            // The label-taking initialiser renders nothing at all here — the control occupies its
            // space in the layout and draws no pixels, which is invisible in a green test run and
            // obvious the moment you look at a frame.
            Button { isImporting = true } label: { importLabel }
                .buttonStyle(.plain)
            .photosPicker(isPresented: $isImporting,
                          selection: $pickerItem,
                          matching: .images,
                          photoLibrary: .shared())
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let shot = model.imported(data: data) {
                        onShot(shot)
                    }
                    pickerItem = nil
                }
            }
            #else
            Button { isImporting = true } label: { importLabel }
                .buttonStyle(.plain)
                .fileImporter(isPresented: $isImporting,
                              allowedContentTypes: [.image]) { result in
                    if case .success(let url) = result, let shot = model.imported(from: url) {
                        onShot(shot)
                    }
                }
            #endif
        }
        .accessibilityIdentifier("capture.import")
        .accessibilityLabel("Choose from photo library")
    }

    private var importLabel: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            // Dark rather than translucent white: a light room photo behind a white-on-white
            // control leaves nothing visible at all.
            .fill(.black.opacity(0.34))
            .overlay {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
            }
            .frame(width: 52, height: 52)
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// When there is no camera — the Mac, or access declined — import is the whole screen's
    /// action rather than a corner button. Declining the camera is a supported way to use this
    /// app, not a dead end.
    private var importPrompt: some View {
        PillButton(title: "Choose a photo", role: .glass) { isImporting = true }
            .accessibilityIdentifier("capture.importPrimary")
            #if os(macOS)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result, let shot = model.imported(from: url) {
                    onShot(shot)
                }
            }
            #endif
    }

    private var shutter: some View {
        Button {
            Task {
                if let shot = await model.capture() { onShot(shot) }
            }
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 5)
                .overlay { Circle().fill(.white).padding(8) }
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.45), radius: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isCapturing)
        .opacity(model.isCapturing ? 0.5 : 1)
        .accessibilityIdentifier("capture.shutter")
        .accessibilityLabel("Take photo")
    }

    private var flipButton: some View {
        Button { model.switchCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("capture.flip")
        .accessibilityLabel("Switch camera")
    }
}
