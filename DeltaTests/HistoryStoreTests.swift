import Testing
import Foundation
@testable import Delta

struct HistoryStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-history-\(UUID().uuidString)")!
    }

    @Test func addInsertsAtFront() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "a1", textB: "b1", date: Date(timeIntervalSince1970: 1))
        store.add(textA: "a2", textB: "b2", date: Date(timeIntervalSince1970: 2))
        #expect(store.entries.map(\.textA) == ["a2", "a1"])
    }

    @Test func skipsConsecutiveDuplicate() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 1))
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 2))
        #expect(store.entries.count == 1)
    }

    @Test func skipsBothEmpty() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "", textB: "", date: Date(timeIntervalSince1970: 1))
        #expect(store.entries.isEmpty)
    }

    @Test func oneSideEmptyIsRecorded() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "x", textB: "", date: Date(timeIntervalSince1970: 1))
        #expect(store.entries.count == 1)
    }

    @Test func capsAtMaxEntries() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        for i in 0..<(HistoryStore.maxEntries + 5) {
            store.add(textA: "a\(i)", textB: "b\(i)", date: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        #expect(store.entries.count == HistoryStore.maxEntries)
        #expect(store.entries.first?.textA == "a\(HistoryStore.maxEntries + 4)")
        #expect(store.entries.last?.textA == "a5")
    }

    @Test func nonConsecutiveDuplicateIsRecorded() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 1))
        store.add(textA: "z", textB: "w", date: Date(timeIntervalSince1970: 2))
        store.add(textA: "x", textB: "y", date: Date(timeIntervalSince1970: 3))
        #expect(store.entries.count == 3)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = HistoryStore(userDefaults: defaults, key: "h")
        store1.add(textA: "p", textB: "q", date: Date(timeIntervalSince1970: 1))
        let store2 = HistoryStore(userDefaults: defaults, key: "h")
        #expect(store2.entries.map(\.textA) == ["p"])
    }

    @Test func clearEmptiesAndPersists() {
        let defaults = makeDefaults()
        let store1 = HistoryStore(userDefaults: defaults, key: "h")
        store1.add(textA: "p", textB: "q", date: Date(timeIntervalSince1970: 1))
        store1.clear()
        #expect(store1.entries.isEmpty)
        let store2 = HistoryStore(userDefaults: defaults, key: "h")
        #expect(store2.entries.isEmpty)
    }

    @Test func recordsTimestamp() {
        let store = HistoryStore(userDefaults: makeDefaults(), key: "h")
        let d = Date(timeIntervalSince1970: 12345)
        store.add(textA: "a", textB: "b", date: d)
        #expect(store.entries.first?.timestamp == d)
    }
}
