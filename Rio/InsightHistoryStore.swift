import Foundation

struct SavedInsight: Codable, Equatable, Identifiable, Sendable {
    enum Category: String, Codable, Sendable {
        case important
        case decision
        case action
        case question
        case risk

        init(_ category: InsightCategory) {
            switch category {
            case .important: self = .important
            case .decision: self = .decision
            case .action: self = .action
            case .question: self = .question
            case .risk: self = .risk
            }
        }

        var domainValue: InsightCategory {
            switch self {
            case .important: .important
            case .decision: .decision
            case .action: .action
            case .question: .question
            case .risk: .risk
            }
        }
    }

    enum State: String, Codable, Sendable {
        case new
        case updated
        case resolved

        init(_ state: InsightCardState) {
            switch state {
            case .new: self = .new
            case .updated: self = .updated
            case .resolved: self = .resolved
            }
        }

        var domainValue: InsightCardState {
            switch self {
            case .new: .new
            case .updated: .updated
            case .resolved: .resolved
            }
        }
    }

    let id: UUID
    let sessionID: UUID
    let stableKey: String
    let category: Category
    let text: String
    let state: State
    let savedAt: Date

    init(id: UUID = UUID(), sessionID: UUID, card: InsightCard, savedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        stableKey = card.stableKey
        category = Category(card.category)
        text = card.text
        state = State(card.state)
        self.savedAt = savedAt
    }

    var card: InsightCard {
        InsightCard(
            stableKey: stableKey,
            category: category.domainValue,
            text: text,
            explicitOwner: nil,
            state: state.domainValue,
            changedAt: savedAt
        )
    }
}

enum LegacyInsightHistoryFile {
    static func remove(
        at fileURL: URL = defaultFileURL(),
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return directory
            .appendingPathComponent("Rio", isDirectory: true)
            .appendingPathComponent("recent-insights.json")
    }
}
