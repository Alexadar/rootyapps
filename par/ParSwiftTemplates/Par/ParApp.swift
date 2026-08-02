import SwiftUI

/// Tapes are documents. Nothing device-local, so an iCloud container can be
/// switched on later without a migration.
@main
struct ParApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TapeDocument()) { file in
            RootView(document: file.$document)
        }
        .commands {
            CommandMenu("Solve") {
                Button("Solve") {}.keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandMenu("Tools") {
                // ⌘1…⌘0 reach the tools; full keyboard navigation on the Mac.
                ForEach(Array(RootView.Tool.allCases.enumerated()), id: \.offset) { index, tool in
                    Button(tool.rawValue) {}
                        .keyboardShortcut(KeyEquivalent(Character("\((index + 1) % 10)")), modifiers: .command)
                }
            }
        }
    }
}
