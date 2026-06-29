import AppKit
import SwiftUI

/// Holds and presents a single diff window instance, and switches the app's
/// activation policy so it appears in Cmd+Tab and the Dock only while the
/// window is visible (otherwise it stays a menu-bar accessory).
@MainActor
final class DiffWindowManager: NSObject, NSWindowDelegate {
    static let shared = DiffWindowManager()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DiffWindowView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Delta Diff"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 540, height: 480))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.delegate = self
            window = newWindow
        }
        // Become a regular app while the window is visible so it shows in Cmd+Tab and the Dock.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        // Force activation so the window comes to the front from BOTH the global
        // hotkey (background) and the menu-bar item.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Toggles the window: hides it when it is the frontmost key window,
    /// otherwise shows and activates it (creating it on first use via show()).
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    /// Hides the window via orderOut and returns to a menu-bar accessory.
    /// (orderOut does not fire windowWillClose, so the policy is reset here.)
    private func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // Closing the window (red button / ⌘W) returns to a menu-bar accessory.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
