import SwiftUI
import MetalKit
import simd

/// The shell: a Metal view, a demo picker, a readout, and the controls.
///
/// It owns no physics. The picker chooses a `Demo`, the demo builds a `Snapshot` out of the Kits,
/// and the renderer draws it. Everything flows one way.
struct ContentView: View {
    @State private var demo: Demo = LaunchOverride.demo ?? .bubbleWall
    @State private var spin: Double = 0.8
    @State private var showsCatalog = true

    /// Manual overrides the demo's scripted camera. It starts from wherever the script had reached,
    /// so toggling never jumps.
    @State private var manual = false
    @State private var rig = CameraRig()

    /// Time is a *coordinate*, not a clock. Every demo is a pure function of it, so scrubbing
    /// backwards retraces exactly — nothing accumulates and nothing needs storing.
    @State private var playing = true
    @State private var scrubTime: Double = 0

    /// Integration steps in the geodesic pass. The default melts a phone at native resolution:
    /// 256 RK4 steps per pixel is ~5×10⁸ steps a second at 60 fps on a 2556×1179 panel.
    @State private var quality: Double = 96

    @State private var dragStart: CGSize = .zero
    @State private var rigAtDragStart = CameraRig()

    var body: some View {
        ZStack(alignment: .topLeading) {
            RelativisticView(demo: demo, spin: spin, manual: manual, rig: $rig,
                             playing: playing, scrubTime: $scrubTime, quality: Float(quality))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    if showsCatalog { catalog }
                    Spacer()
                    readout
                }
                Spacer()
                if manual { manualBar }
                transport
            }
            .padding(14)
        }
        .background(Color(red: 0.03, green: 0.04, blue: 0.06))
    }

    // MARK: - Panels

    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(1...4, id: \.self) { tier in
                    Text(Self.tierName(tier))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xCD8856))
                        .padding(.top, 8)
                    ForEach(Demo.allCases.filter { $0.tier == tier }) { d in
                        Button { demo = d } label: {
                            HStack(spacing: 6) {
                                Text(String(format: "%02d", d.rawValue))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(d.title)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(d == demo ? Color(hex: 0xD7687F) : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("demo.\(d.rawValue)")
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 250)
        .frame(maxHeight: 420)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var readout: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(demo.title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: 0xD7687F))
            Text(demo.isWorldSpace ? "WORLD-SPACE — geodesics" : "SCREEN-SPACE — camera only")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(demo.isWorldSpace ? Color(hex: 0x459AA0) : Color(hex: 0xCD8856))
            Text(demo.oracle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            // What the camera is trying to show you. Without this the motion is mysterious.
            Text(manual ? "drag = orbit · two fingers = pan · pinch = zoom"
                        : demo.cameraMove.intent)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(hex: 0xEFB162).opacity(0.85))
                .frame(maxWidth: 320, alignment: .trailing)
                .multilineTextAlignment(.trailing)

            HStack(spacing: 6) {
                Text("spin a").font(.system(size: 9, design: .monospaced))
                Slider(value: $spin, in: 0...0.999).frame(width: 110)
                Text(String(format: "%.3f", spin))
                    .font(.system(size: 9, design: .monospaced)).frame(width: 38, alignment: .leading)
            }
            HStack(spacing: 6) {
                Text("steps").font(.system(size: 9, design: .monospaced))
                Slider(value: $quality, in: 24...256, step: 8).frame(width: 110)
                Text("\(Int(quality))")
                    .font(.system(size: 9, design: .monospaced)).frame(width: 38, alignment: .leading)
            }
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readout")
    }

    /// Manual controls, as explicit buttons.
    ///
    /// Gestures alone were not enough: the overlay panels can swallow a drag, and when a control
    /// might not be firing you cannot tell a broken camera from a broken render. Buttons remove
    /// that ambiguity — every one of them changes the pose by a known amount, so if the view does
    /// not move, the render is what is wrong.
    private var manualBar: some View {
        HStack(spacing: 10) {
            // Named viewpoints. Jumping to a KNOWN angle is what separates "looks odd" from
            // "wrong from the side, right from the front".
            ForEach(CameraRig.Preset.allCases, id: \.self) { p in
                Button { rig.apply(p) } label: {
                    Text(p.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x459AA0))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preset.\(p.rawValue)")
            }

            Divider().frame(height: 14)

            Text("rot").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            nudge("←") { rig.orbit(deltaAzimuth: -0.20, deltaElevation: 0) }
            nudge("→") { rig.orbit(deltaAzimuth: 0.20, deltaElevation: 0) }
            nudge("↑") { rig.orbit(deltaAzimuth: 0, deltaElevation: 0.15) }
            nudge("↓") { rig.orbit(deltaAzimuth: 0, deltaElevation: -0.15) }

            Divider().frame(height: 14)

            Text("move").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            nudge("◀") { rig.pan(right: -1, up: 0) }
            nudge("▶") { rig.pan(right: 1, up: 0) }
            nudge("▲") { rig.pan(right: 0, up: 1) }
            nudge("▼") { rig.pan(right: 0, up: -1) }

            Divider().frame(height: 14)

            Text("zoom").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            nudge("+") { rig.dolly(scale: 1.18) }
            nudge("−") { rig.dolly(scale: 1 / 1.18) }

            Divider().frame(height: 14)

            Button {
                // Back to the demo's own scripted pose at the current instant — not to a global
                // default, because "reset" should mean "show me what this demo intends".
                rig.applyScripted(demo.cameraMove, at: scrubTime)
            } label: {
                Text("RESET")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xD7687F))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("resetCamera")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manualBar")
    }

    private func nudge(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 22)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    /// Transport: manual toggle, play/pause, and the time scrubber.
    private var transport: some View {
        HStack(spacing: 12) {
            Button { toggleManual() } label: {
                Text(manual ? "MANUAL" : "AUTO")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(manual ? Color(hex: 0xD7687F) : Color(hex: 0x459AA0))
                    .frame(width: 72)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manualToggle")

            Button { playing.toggle() } label: {
                Text(playing ? "❚❚" : "▶")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary).frame(width: 26)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("playToggle")

            Text("t").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Slider(value: $scrubTime, in: 0...120)
                .accessibilityIdentifier("timeSlider")
            Text(String(format: "%6.2f M", scrubTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 74, alignment: .leading)

            if manual {
                Text(String(format: "r %.1f  az %.2f  el %.2f",
                            rig.distance, rig.azimuth, rig.elevation))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xEFB162).opacity(0.8))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Manual picks up exactly where the script left it, so the view does not jump on toggle.
    private func toggleManual() {
        if !manual {
            var seeded = rig
            seeded.applyScripted(demo.cameraMove, at: scrubTime)
            rig = seeded
        }
        manual.toggle()
    }

    private static func tierName(_ t: Int) -> String {
        switch t {
        case 1: return "TIER 1 · SCREEN-SPACE"
        case 2: return "TIER 2 · GEODESICS"
        case 3: return "TIER 3 · PORTALS"
        default: return "TIER 4 · MECHANICS"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The MTKView host. Rebuilds the snapshot each frame from the Kits; the renderer never computes.
struct RelativisticView {
    var demo: Demo
    var spin: Double
    var manual: Bool
    @Binding var rig: CameraRig
    var playing: Bool
    @Binding var scrubTime: Double
    var quality: Float
}

#if os(macOS)
import AppKit
extension RelativisticView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { context.coordinator.view }
    func updateNSView(_ nsView: MTKView, context: Context) { push(context.coordinator) }
    func makeCoordinator() -> DemoCoordinator { DemoCoordinator() }
}
#else
import UIKit
extension RelativisticView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { context.coordinator.view }
    func updateUIView(_ uiView: MTKView, context: Context) { push(context.coordinator) }
    func makeCoordinator() -> DemoCoordinator { DemoCoordinator() }
}
#endif

extension RelativisticView {
    func push(_ c: DemoCoordinator) {
        c.demo = demo
        c.spin = spin
        c.manual = manual
        c.quality = quality
        c.playing = playing
        c.manualRig = rig
        c.time = scrubTime
        c.onTimeAdvanced = { t in scrubTime = t }
        c.onRigChanged = { r in rig = r }
    }
}

/// Drives the frame clock and rebuilds the snapshot.
///
/// The only place presentation time exists. Even here it is a *coordinate* handed to a pure
/// function, never an accumulator the simulation reads — which is exactly why scrubbing works.
final class DemoCoordinator: NSObject, MTKViewDelegate {
    let view = MTKView()
    private var renderer: Renderer?

    var demo: Demo = .bubbleWall
    var spin: Double = 0.8
    var manual = false
    var playing = true
    var quality: Float = 96
    var time: Double = 0
    var manualRig = CameraRig()
    var onTimeAdvanced: ((Double) -> Void)?
    var onRigChanged: ((CameraRig) -> Void)?

    override init() {
        super.init()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        renderer = Renderer(view: view)
        view.delegate = self
        installGestures()
    }

    // MARK: - Gestures
    //
    // Native recognizers attached to the MTKView, NOT SwiftUI gestures.
    //
    // SwiftUI's `DragGesture` cannot distinguish one finger from two, and its arbitration hands the
    // touch to whichever overlay is on top — so a drag that starts near a panel silently does
    // nothing. UIKit/AppKit recognizers take a touch count directly and live on the view being
    // manipulated, which is both the reliable answer and the conventional one.
    //
    // Deltas are consumed incrementally (`setTranslation(.zero)`) rather than read as an absolute,
    // so a gesture never fights the scripted camera or snaps when it begins.

    #if os(iOS)
    private func installGestures() {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        // Pinch and two-finger pan must run together: zooming while repositioning is one motion.
        pinch.delegate = self
        pan.delegate = self
        view.addGestureRecognizer(orbit)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
    }

    @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
        guard manual else { return }
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        manualRig.orbit(deltaAzimuth: Float(-d.x) * 0.008, deltaElevation: Float(d.y) * 0.008)
        onRigChanged?(manualRig)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard manual else { return }
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        manualRig.pan(right: Float(-d.x) * 0.03, up: Float(d.y) * 0.03)
        onRigChanged?(manualRig)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard manual else { return }
        manualRig.dolly(scale: Float(g.scale))
        g.scale = 1
        onRigChanged?(manualRig)
    }
    #else
    private func installGestures() {
        let orbit = NSPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.buttonMask = 0x1                      // left drag orbits
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.buttonMask = 0x2                        // right drag pans
        let zoom = NSMagnificationGestureRecognizer(target: self, action: #selector(handleZoom(_:)))
        view.addGestureRecognizer(orbit)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(zoom)
    }

    @objc private func handleOrbit(_ g: NSPanGestureRecognizer) {
        guard manual else { return }
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        manualRig.orbit(deltaAzimuth: Float(-d.x) * 0.008, deltaElevation: Float(-d.y) * 0.008)
        onRigChanged?(manualRig)
    }

    @objc private func handlePan(_ g: NSPanGestureRecognizer) {
        guard manual else { return }
        let d = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        manualRig.pan(right: Float(-d.x) * 0.03, up: Float(-d.y) * 0.03)
        onRigChanged?(manualRig)
    }

    @objc private func handleZoom(_ g: NSMagnificationGestureRecognizer) {
        guard manual else { return }
        manualRig.dolly(scale: Float(1 + g.magnification))
        g.magnification = 0
        onRigChanged?(manualRig)
    }
    #endif

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.mtkView(view, drawableSizeWillChange: size)
    }

    func draw(in view: MTKView) {
        guard let renderer else { return }

        // Frozen time wins, so a captured frame is reproducible.
        if let frozen = LaunchOverride.frozenTime {
            // Publish it too, or the transport reads 0.00 M while the camera is plainly elsewhere —
            // which makes a captured frame look like the controls are broken.
            if time != frozen { time = frozen; onTimeAdvanced?(frozen) }
        } else if playing {
            time += 1.0 / 60.0
            if time > 120 { time = 0 }
            onTimeAdvanced?(time)
        }

        var rig = manualRig
        if !manual { rig.applyScripted(demo.cameraMove, at: time) }

        var snap = demo.makeSnapshot(spin: spin, time: time, camera: rig.camera())
        snap.relativity.integrationSteps = quality
        renderer.snapshot = snap
        renderer.draw(in: view)
    }
}


#if os(iOS)
extension DemoCoordinator: UIGestureRecognizerDelegate {
    /// Pinch and two-finger pan are one motion to the hand, so they must not cancel each other.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
