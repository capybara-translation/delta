/// Tab キーに対する動作。
enum TabKeyAction: Equatable {
    case insertTab      // Ctrl+Tab → リテラルのタブ文字
    case focusSibling   // Tab / Shift+Tab → フォーカス移動
    case passThrough    // タブキー以外
}

/// キーコードと Ctrl 有無からタブキーの動作を判定する純粋ロジック。
enum TabKeyResolver {
    /// Tab キーの仮想キーコード（US 配列・物理位置で不変）。
    static let tabKeyCode: UInt16 = 48

    static func action(keyCode: UInt16, hasControl: Bool) -> TabKeyAction {
        guard keyCode == tabKeyCode else { return .passThrough }
        return hasControl ? .insertTab : .focusSibling
    }
}
