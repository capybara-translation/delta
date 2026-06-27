import SwiftUI

@main
struct DeltaApp: App {
    var body: some Scene {
        MenuBarExtra("Delta", systemImage: "doc.on.doc") {
            Button("Open Diff Window") { /* Task 3 で実装 */ }
            Divider()
            Button("Quit Delta") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
