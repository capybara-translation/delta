import Testing
@testable import Delta

struct TabKeyResolverTests {
    @Test func ctrlTabInsertsTab() {
        #expect(TabKeyResolver.action(keyCode: 48, hasControl: true) == .insertTab)
    }

    @Test func tabMovesFocus() {
        #expect(TabKeyResolver.action(keyCode: 48, hasControl: false) == .focusSibling)
    }

    @Test func otherKeyPassesThrough() {
        // keyCode 0 は 'a'。タブキーではない。
        #expect(TabKeyResolver.action(keyCode: 0, hasControl: false) == .passThrough)
    }

    @Test func ctrlOtherKeyPassesThrough() {
        #expect(TabKeyResolver.action(keyCode: 0, hasControl: true) == .passThrough)
    }
}
