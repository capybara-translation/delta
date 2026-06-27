import AppKit
import SwiftUI

/// 単一インスタンスの diff ウィンドウを保持・表示する。
/// macOS 14 では SwiftUI の `Window` Scene が起動時に自動で開くため、
/// メニューバー常駐アプリとして AppKit で明示的に管理する。
@MainActor
final class DiffWindowManager {
    static let shared = DiffWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DiffWindowView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Diff"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 540, height: 480))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}
