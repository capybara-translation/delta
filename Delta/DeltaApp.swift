import SwiftUI

@main
struct DeltaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Delta Diff", image: "MenuBarIcon") {
            MenuContent()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// Menu-bar menu content. Extracted into a View so it can use the `openSettings`
/// environment action: an accessory (LSUIElement) app must be activated first, or
/// the Settings window opens behind everything and appears not to show.
private struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    @State private var updateChecker = UpdateChecker.shared

    var body: some View {
        if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
            Button("Update available (\(latest))") { updateChecker.openReleasesPage() }
            Divider()
        }
        Button("Open Delta Diff…") { DiffWindowManager.shared.show() }
        Button("Settings…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Check for Updates…") { updateChecker.checkManually() }
        Divider()
        Button("Quit Delta Diff") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Registers the global hotkey at launch via HotKeyController, and clears persisted
/// text at launch when text retention is off. `@MainActor` because its launch work
/// calls main-actor-isolated singletons (HotKeyController, UpdateChecker).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        clearTextIfNeeded()
        HotKeyController.shared.start()
        UpdateChecker.shared.checkOnLaunch()
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
