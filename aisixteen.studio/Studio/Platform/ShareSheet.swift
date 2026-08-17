import SwiftUI
import UniformTypeIdentifiers

/// Share — the one export that asks for no permission at all.
///
/// The enhanced copy is written to a temporary file first because both platforms' share services
/// want a file URL with a real name: handing them raw `Data` produces a share whose attachment is
/// called "Untitled", which is not what someone AirDropping a photo to themselves expects.
private struct ShareModifier: ViewModifier {

    @Binding var item: Data?
    @State private var url: URL?

    func body(content: Content) -> some View {
        content
            .onChange(of: item) { _, data in
                guard let data else { url = nil; return }
                url = Self.temporaryFile(for: data)
            }
            #if os(iOS)
            .sheet(isPresented: Binding(get: { url != nil },
                                        set: { if !$0 { url = nil; item = nil } })) {
                if let url {
                    ActivityView(url: url)
                        .presentationDetents([.medium, .large])
                }
            }
            #else
            .background {
                if let url {
                    MacSharePresenter(url: url) { self.url = nil; item = nil }
                }
            }
            #endif
    }

    private static func temporaryFile(for data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Enhanced-\(UUID().uuidString.prefix(6)).heic")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

extension View {
    func studioShare(_ item: Binding<Data?>) -> some View {
        modifier(ShareModifier(item: item))
    }
}

#if os(iOS)
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
import AppKit

/// `NSSharingServicePicker` needs a real view to anchor to, so this parks an invisible one in the
/// hierarchy and presents from it once.
struct MacSharePresenter: NSViewRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard !context.coordinator.presented else { return }
        context.coordinator.presented = true
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            onFinish()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var presented = false }
}
#endif
