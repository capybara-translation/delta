import SwiftUI
import Carbon

@main
struct DeltaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Delta", systemImage: "doc.on.doc") {
            Button("Open Diff Window") { DiffWindowManager.shared.show() }
            Divider()
            Button("Quit Delta") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Registers the global hotkey (⌃⌥D) at launch and retains it for the app's lifetime.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey)
        ) {
            DiffWindowManager.shared.toggle()
        }
    }
}
