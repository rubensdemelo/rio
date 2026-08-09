import XCTest

@MainActor
final class InsightHistoryStoreTests: XCTestCase {
    func testRecordsAnUpdatedCardOncePerSession() {
        let repository = TestInsightHistoryRepository()
        let history = InsightHistoryStore(repository: repository)
        let sessionID = UUID()
        let firstSavedAt = Date()
        let updatedSavedAt = firstSavedAt.addingTimeInterval(60)

        history.record(
            cards: [card(text: "Initial decision", state: .new)],
            sessionID: sessionID,
            now: firstSavedAt
        )
        history.record(
            cards: [card(text: "Updated decision", state: .updated)],
            sessionID: sessionID,
            now: updatedSavedAt
        )

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].text, "Updated decision")
        XCTAssertEqual(history.entries[0].state, .updated)
        XCTAssertEqual(history.entries[0].savedAt, updatedSavedAt)
        XCTAssertEqual(repository.entries, history.entries)
    }

    func testPrunesEntriesOlderThanTwoDaysOnLoad() {
        let now = Date()
        let repository = TestInsightHistoryRepository(entries: [
            SavedInsight(
                sessionID: UUID(),
                card: card(text: "Expired", state: .new),
                savedAt: now.addingTimeInterval(-InsightHistoryStore.retention - 1)
            ),
            SavedInsight(
                sessionID: UUID(),
                card: card(text: "Recent", state: .new),
                savedAt: now
            ),
        ])

        let history = InsightHistoryStore(repository: repository)

        XCTAssertEqual(history.entries.map(\.text), ["Recent"])
        XCTAssertEqual(repository.entries.map(\.text), ["Recent"])
    }

    func testClearRemovesPersistedEntries() {
        let repository = TestInsightHistoryRepository()
        let history = InsightHistoryStore(repository: repository)
        history.record(cards: [card(text: "To remove", state: .new)], sessionID: UUID())

        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(repository.entries.isEmpty)
    }

    private func card(text: String, state: InsightCardState) -> InsightCard {
        InsightCard(
            stableKey: "decision-1",
            category: .decision,
            text: text,
            explicitOwner: nil,
            state: state
        )
    }
}

private final class TestInsightHistoryRepository: InsightHistoryPersisting {
    var entries: [SavedInsight]

    init(entries: [SavedInsight] = []) {
        self.entries = entries
    }

    func load() throws -> [SavedInsight] { entries }
    func save(_ entries: [SavedInsight]) throws { self.entries = entries }
}
