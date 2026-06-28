/// The action to take for a Tab key event.
enum TabKeyAction: Equatable {
    case insertTab      // Ctrl+Tab → insert a literal tab character
    case focusSibling   // Tab / Shift+Tab → move focus to sibling
    case passThrough    // any key other than Tab
}

/// Pure logic that determines the Tab key action from the key code and Ctrl modifier.
enum TabKeyResolver {
    /// Virtual key code for the Tab key (US layout, fixed by physical position).
    static let tabKeyCode: UInt16 = 48

    static func action(keyCode: UInt16, hasControl: Bool) -> TabKeyAction {
        guard keyCode == tabKeyCode else { return .passThrough }
        return hasControl ? .insertTab : .focusSibling
    }
}
