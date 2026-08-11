import Combine
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
            state: state.domainValue
        )
    }
}

protocol InsightHistoryPersisting {
    func load() throws -> [SavedInsight]
    func save(_ entries: [SavedInsight]) throws
}

struct FileInsightHistoryRepository: InsightHistoryPersisting {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() throws -> [SavedInsight] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try JSONDecoder().decode([SavedInsight].self, from: Data(contentsOf: fileURL))
    }

    func save(_ entries: [SavedInsight]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("Rio", isDirectory: true)
            .appendingPathComponent("recent-insights.json")
    }
}

@MainActor
final class InsightHistoryStore: ObservableObject {
    static let retention: TimeInterval = 48 * 60 * 60
    static let maximumEntryCount = 200

    @Published private(set) var entries: [SavedInsight]

    private let repository: any InsightHistoryPersisting

    init(repository: any InsightHistoryPersisting = FileInsightHistoryRepository()) {
        self.repository = repository
        let loadedEntries = (try? repository.load()) ?? []
        entries = Self.retainedEntries(from: loadedEntries, now: Date())
        if entries != loadedEntries {
            try? repository.save(entries)
        }
    }

    func record(cards: [InsightCard], sessionID: UUID, now: Date = Date()) {
        guard !cards.isEmpty else { return }

        var updatedEntries = Self.retainedEntries(from: entries, now: now)
        for card in cards {
            if let index = updatedEntries.firstIndex(where: {
                $0.sessionID == sessionID && $0.stableKey == card.stableKey
            }) {
                let existingEntry = updatedEntries[index]
                guard existingEntry.category.domainValue != card.category
                    || existingEntry.text != card.text
                    || existingEntry.state.domainValue != card.state else {
                    continue
                }

                updatedEntries[index] = SavedInsight(
                    id: existingEntry.id,
                    sessionID: sessionID,
                    card: card,
                    savedAt: now
                )
            } else {
                updatedEntries.append(SavedInsight(sessionID: sessionID, card: card, savedAt: now))
            }
        }

        updatedEntries = Self.retainedEntries(from: updatedEntries, now: now)
        guard updatedEntries != entries else { return }
        entries = updatedEntries
        try? repository.save(entries)
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        try? repository.save(entries)
    }

    private static func retainedEntries(
        from entries: [SavedInsight],
        now: Date
    ) -> [SavedInsight] {
        let earliestRetainedDate = now.addingTimeInterval(-retention)
        return entries
            .filter { $0.savedAt >= earliestRetainedDate }
            .sorted { $0.savedAt > $1.savedAt }
            .prefix(maximumEntryCount)
            .map { $0 }
    }
}
