import AppKit
import SwiftUI

/// Holds and presents a single diff window instance.
/// On macOS 14, SwiftUI's `Window` scene opens automatically at launch,
/// so this class manages the window explicitly in AppKit for a menu-bar-resident app.
@MainActor
final class DiffWindowManager {
    static let shared = DiffWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DiffWindowView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Delta Diff"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 540, height: 480))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    /// Toggles the window: hides it when it is the frontmost key window,
    /// otherwise shows and activates it (creating it on first use via show()).
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }
}
