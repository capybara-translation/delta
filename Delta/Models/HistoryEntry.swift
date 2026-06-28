import Foundation

/// One recorded comparison: the two input texts and when they were compared.
struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let textA: String
    let textB: String
}
