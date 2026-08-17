import SwiftUI

// Capture — one live coach line, not a tutorial. Interior/Exterior changes
// guidance and the preset set. Library import follows the same path
// (depth then estimated monocularly).
struct CaptureView: View {
    @State private var mode: SpaceMode = .interior
    @State private var coach = "Level · whole wall in frame · good light"
    @State private var shotUsable = true

    var body: some View {
        ZStack {
            CameraPreviewPlaceholder() // AVCaptureVideoPreviewLayer in the app

            VStack {
                modePicker.padding(.top, 60)
                Spacer()
                coachCapsule
                Spacer()
                controls.padding(.bottom, 44)
            }
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach([SpaceMode.interior, .exterior], id: \.rawValue) { m in
                Button(m == .interior ? "Interior" : "Exterior") {
                    withAnimation(DS.morph) { mode = m }
                }
                .font(.subheadline.weight(mode == m ? .semibold : .regular))
                .foregroundStyle(mode == m ? .white : DS.ink)
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background { if mode == m { Capsule().fill(DS.ink) } }
            }
        }
        .padding(3)
        .glassEffect(in: .capsule)
        .accessibilityLabel("Space type")
    }

    private var coachCapsule: some View {
        HStack(spacing: 8) {
            Circle().fill(shotUsable ? DS.good : .orange).frame(width: 8, height: 8)
            Text(coach).font(.footnote.weight(.medium)).foregroundStyle(DS.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .glassEffect(in: .capsule)
        .accessibilityLabel(shotUsable ? "Shot is usable. \(coach)" : coach)
    }

    private var controls: some View {
        HStack {
            Button {} label: { RoundedRectangle(cornerRadius: 14).fill(.quaternary).frame(width: 52, height: 52) }
                .accessibilityLabel("Choose from photo library")
            Spacer()
            Button {} label: {
                Circle().strokeBorder(.white, lineWidth: 5).frame(width: 76, height: 76)
                    .background(Circle().fill(.white).padding(8))
            }
            .accessibilityLabel("Take photo")
            Spacer()
            Button {} label: { Image(systemName: "arrow.triangle.2.circlepath").font(.title3).foregroundStyle(DS.ink).frame(width: 52, height: 52) }
                .buttonStyle(.glass)
                .accessibilityLabel("Switch camera")
        }
    }
}

struct CameraPreviewPlaceholder: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xB3A288), Color(hex: 0x75604A)],
                       startPoint: .top, endPoint: .bottom)
    }
}
