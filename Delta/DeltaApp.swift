import SwiftUI
import Carbon

@main
struct DeltaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Delta Diff", systemImage: "doc.on.doc") {
            Button("Open Delta Diff") { DiffWindowManager.shared.show() }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Delta Diff") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// Registers the global hotkey (⌃⌥D) at launch, retains it for the app's lifetime,
/// and clears persisted text at launch when text retention is off.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clearTextIfNeeded()
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey)
        ) {
            DiffWindowManager.shared.toggle()
        }
    }

    /// When "keep text between launches" is off, start each launch with empty input.
    /// A missing key (first launch) is treated as true (keep).
    private func clearTextIfNeeded() {
        let defaults = UserDefaults.standard
        let keep = defaults.object(forKey: "keepTextOnReopen") as? Bool ?? true
        if !keep {
            defaults.removeObject(forKey: "textA")
            defaults.removeObject(forKey: "textB")
        }
    }
}
