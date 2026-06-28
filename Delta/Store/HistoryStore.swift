import Foundation
import Observation

/// Stores recent comparison inputs (newest first, capped), persisted to UserDefaults as JSON.
@Observable
final class HistoryStore {
    static let maxEntries = 30

    private(set) var entries: [HistoryEntry]

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "history") {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// Records a comparison. Skips when both texts are empty, or when it equals the most recent entry.
    func add(textA: String, textB: String, date: Date) {
        if textA.isEmpty && textB.isEmpty { return }
        if let latest = entries.first, latest.textA == textA, latest.textB == textB { return }
        entries.insert(HistoryEntry(id: UUID(), timestamp: date, textA: textA, textB: textB), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            userDefaults.set(data, forKey: key)
        }
    }
}
