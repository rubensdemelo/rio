import Foundation
import XCTest

@MainActor
final class MeetingHistoryStoreTests: XCTestCase {
    func testSavedMeetingOrdersAndDeduplicatesTranscriptSegments() {
        let meeting = SavedMeeting(
            id: UUID(),
            startedAt: date(0),
            endedAt: date(60),
            transcriptSegments: [
                segment(sequenceNumber: 2, startOffset: 30, endOffset: 40, text: "Second"),
                segment(sequenceNumber: 1, startOffset: 10, endOffset: 20, text: "First"),
                segment(sequenceNumber: 2, startOffset: 30, endOffset: 40, text: "Duplicate"),
            ],
            insights: [],
            incompleteTranscript: false
        )

        XCTAssertEqual(meeting.transcriptSegments.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(meeting.transcriptSegments.map(\.text), ["First", "Second"])
    }

    func testLoadingAndWritingPrunesMeetingsOutsideTheLastTwoDays() throws {
        let now = date(100_000)
        let expired = meeting(id: UUID(), endedAt: now.timeIntervalSince1970 - MeetingHistoryStore.retention - 1)
        let recent = meeting(id: UUID(), endedAt: now.timeIntervalSince1970)
        let repository = TestMeetingHistoryRepository(meetings: [expired, recent])

        let history = MeetingHistoryStore(repository: repository, now: now)

        XCTAssertEqual(history.meetings.map(\.id), [recent.id])
        XCTAssertEqual(repository.meetings, [recent])

        try history.record(expired, now: now)

        XCTAssertEqual(history.meetings, [recent])
        XCTAssertEqual(repository.meetings, [recent])
    }

    func testRecordingTheSameMeetingIDReplacesThePreviousSnapshot() throws {
        let repository = TestMeetingHistoryRepository()
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        let id = UUID()

        try history.record(
            meeting(id: id, endedAt: 50, transcriptText: "Initial"),
            now: date(100)
        )
        try history.record(
            meeting(id: id, endedAt: 60, transcriptText: "Final"),
            now: date(100)
        )

        XCTAssertEqual(history.meetings.count, 1)
        XCTAssertEqual(history.meetings[0].transcriptSegments.map(\.text), ["Final"])
    }

    func testClearMeetingAndClearAllPersistTheChange() throws {
        let repository = TestMeetingHistoryRepository()
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        let first = meeting(id: UUID(), endedAt: 50)
        let second = meeting(id: UUID(), endedAt: 60)
        try history.record(first, now: date(100))
        try history.record(second, now: date(100))

        try history.clear(meetingID: first.id)

        XCTAssertEqual(history.meetings, [second])
        XCTAssertEqual(repository.meetings, [second])

        try history.clearAll()

        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertTrue(repository.meetings.isEmpty)
    }

    func testClearMeetingFailureKeepsEveryMeetingVisibleAndCanRetry() throws {
        let first = meeting(id: UUID(), endedAt: 50)
        let second = meeting(id: UUID(), endedAt: 60)
        let repository = TestMeetingHistoryRepository(meetings: [second, first])
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        repository.shouldFailSaves = true

        XCTAssertThrowsError(try history.clear(meetingID: first.id))
        XCTAssertEqual(history.meetings, [second, first])
        XCTAssertEqual(repository.meetings, [second, first])

        repository.shouldFailSaves = false
        try history.clear(meetingID: first.id)

        XCTAssertEqual(history.meetings, [second])
        XCTAssertEqual(repository.meetings, [second])
    }

    func testClearAllFailureKeepsMeetingsVisibleAndCanRetry() throws {
        let first = meeting(id: UUID(), endedAt: 50)
        let second = meeting(id: UUID(), endedAt: 60)
        let repository = TestMeetingHistoryRepository(meetings: [second, first])
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        repository.shouldFailSaves = true

        XCTAssertThrowsError(try history.clearAll())
        XCTAssertEqual(history.meetings, [second, first])
        XCTAssertEqual(repository.meetings, [second, first])

        repository.shouldFailSaves = false
        try history.clearAll()

        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertTrue(repository.meetings.isEmpty)
    }

    func testRecordFailureKeepsBoundedPendingSnapshotAndCanRetry() throws {
        let repository = TestMeetingHistoryRepository()
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        let failedMeeting = meeting(id: UUID(), endedAt: 100)
        repository.shouldFailSaves = true

        XCTAssertThrowsError(try history.record(failedMeeting, now: date(100)))
        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertEqual(history.pendingMeeting, failedMeeting)
        XCTAssertEqual(history.persistenceIssue, .saveFailed)

        repository.shouldFailSaves = false
        try history.retryPendingMeeting(now: date(100))

        XCTAssertEqual(history.meetings, [failedMeeting])
        XCTAssertNil(history.pendingMeeting)
        XCTAssertNil(history.persistenceIssue)
    }

    func testClockAdvancementPrunesWithoutRecordingAnotherMeeting() throws {
        let meeting = meeting(id: UUID(), endedAt: 100)
        let repository = TestMeetingHistoryRepository(meetings: [meeting])
        let history = MeetingHistoryStore(repository: repository, now: date(100))

        try history.pruneExpired(
            now: date(100 + MeetingHistoryStore.retention + 1)
        )

        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertTrue(repository.meetings.isEmpty)
    }

    func testFailedExpiryWriteHidesExpiredMeetingAndSurfacesAtRestFailure() {
        let meeting = meeting(id: UUID(), endedAt: 100)
        let repository = TestMeetingHistoryRepository(meetings: [meeting])
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        repository.shouldFailSaves = true

        XCTAssertThrowsError(
            try history.pruneExpired(
                now: date(100 + MeetingHistoryStore.retention + 1)
            )
        )

        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertEqual(repository.meetings, [meeting])
        XCTAssertEqual(history.persistenceIssue, .expirySaveFailed)

        repository.shouldFailSaves = false
        XCTAssertNoThrow(
            try history.pruneExpired(
                now: date(100 + MeetingHistoryStore.retention + 2)
            )
        )
        XCTAssertTrue(repository.meetings.isEmpty)
        XCTAssertNil(history.persistenceIssue)
    }

    func testAggregateMeetingCountEvictsOldestDeterministically() throws {
        let now = date(1_000_000)
        let meetings = (0...MeetingHistoryStore.maximumMeetingCount).map { offset in
            meeting(
                id: UUID(),
                endedAt: now.timeIntervalSince1970 - TimeInterval(offset)
            )
        }
        let repository = TestMeetingHistoryRepository(meetings: meetings)

        let history = MeetingHistoryStore(repository: repository, now: now)

        XCTAssertEqual(history.meetings.count, MeetingHistoryStore.maximumMeetingCount)
        XCTAssertEqual(history.meetings.map(\.endedAt), meetings.dropLast().map(\.endedAt))
        XCTAssertEqual(repository.meetings, history.meetings)
    }

    func testAggregateEncodedByteBoundEvictsOldestMeetings() throws {
        let now = date(1_000_000)
        let largeTranscript = (0..<1_000).map { sequence in
            segment(
                sequenceNumber: UInt64(sequence),
                startOffset: TimeInterval(sequence),
                endOffset: TimeInterval(sequence + 1),
                text: String(repeating: "x", count: 1_000)
            )
        }
        let meetings = (0..<9).map { offset in
            SavedMeeting(
                startedAt: now.addingTimeInterval(-TimeInterval(offset + 30)),
                endedAt: now.addingTimeInterval(-TimeInterval(offset)),
                transcriptSegments: largeTranscript,
                insights: [],
                incompleteTranscript: false
            )
        }
        let repository = TestMeetingHistoryRepository(meetings: meetings)

        let history = MeetingHistoryStore(repository: repository, now: now)
        let encoded = try JSONEncoder().encode(history.meetings)

        XCTAssertLessThan(history.meetings.count, meetings.count)
        XCTAssertLessThanOrEqual(encoded.count, MeetingHistoryStore.maximumEncodedByteCount)
        XCTAssertEqual(history.meetings.first?.id, meetings.first?.id)
    }

    func testCorruptHistoryLoadIsReportedWithoutOverwritingTheRepository() {
        let repository = TestMeetingHistoryRepository()
        repository.shouldFailLoads = true

        let history = MeetingHistoryStore(repository: repository, now: date(100))

        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertEqual(history.persistenceIssue, .loadFailed)
        XCTAssertEqual(repository.saveCount, 0)
    }

    func testSuccessfulExpiryPassPreservesPendingSaveFailureStatus() {
        let repository = TestMeetingHistoryRepository(
            meetings: [meeting(id: UUID(), endedAt: 0)]
        )
        let history = MeetingHistoryStore(repository: repository, now: date(0))
        repository.shouldFailSaves = true

        XCTAssertThrowsError(
            try history.record(meeting(id: UUID(), endedAt: 60), now: date(60))
        )
        XCTAssertNotNil(history.pendingMeeting)
        repository.shouldFailSaves = false

        history.load(now: date(MeetingHistoryStore.retention + 1))

        XCTAssertEqual(history.persistenceIssue, .saveFailed)
        XCTAssertNotNil(history.pendingMeeting)
    }

    func testDeletingAnotherMeetingPreservesPendingSaveRetryStatus() throws {
        let durableMeeting = meeting(id: UUID(), endedAt: 30)
        let repository = TestMeetingHistoryRepository(meetings: [durableMeeting])
        let history = MeetingHistoryStore(repository: repository, now: date(30))
        repository.shouldFailSaves = true

        XCTAssertThrowsError(
            try history.record(meeting(id: UUID(), endedAt: 60), now: date(60))
        )
        repository.shouldFailSaves = false

        try history.clear(meetingID: durableMeeting.id)

        XCTAssertEqual(history.persistenceIssue, .saveFailed)
        XCTAssertNotNil(history.pendingMeeting)
    }

    func testTranscriptTextIsBoundedWithoutStoringAudio() throws {
        let text = String(repeating: "x", count: SavedMeeting.maximumTranscriptSegmentUTF8ByteCount + 100)
        let meeting = meeting(id: UUID(), endedAt: 100, transcriptText: text)

        XCTAssertLessThanOrEqual(
            meeting.transcriptSegments[0].text.utf8.count,
            SavedMeeting.maximumTranscriptSegmentUTF8ByteCount
        )

        let data = try JSONEncoder().encode(meeting)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("audio"))
    }

    func testSavedMeetingRoundTripsInsightsAndIncompleteTranscriptState() throws {
        let savedAt = date(100)
        let insight = SavedInsight(
            sessionID: UUID(),
            card: InsightCard(
                stableKey: "decision-1",
                category: .decision,
                text: "The launch date is Friday.",
                explicitOwner: nil,
                state: .new
            ),
            savedAt: savedAt
        )
        let expected = SavedMeeting(
            id: UUID(),
            startedAt: date(70),
            endedAt: savedAt,
            transcriptSegments: [segment(sequenceNumber: 1, startOffset: 0, endOffset: 30, text: "Partial")],
            insights: [insight],
            incompleteTranscript: true
        )

        let decoded = try JSONDecoder().decode(
            SavedMeeting.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded, expected)
        XCTAssertTrue(decoded.incompleteTranscript)
        XCTAssertEqual(decoded.insights, [insight])
        XCTAssertEqual(decoded.insights[0].card.changedAt, savedAt)
    }

    func testSavedMeetingWithoutProfileDefaultsToCustomerCritical() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "startedAt": 70,
          "endedAt": 100,
          "transcriptSegments": [],
          "insights": [],
          "incompleteTranscript": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SavedMeeting.self, from: legacyJSON)

        XCTAssertEqual(decoded.profile, .customerCritical)
    }

    func testFileRepositoryRoundTripsMeetingHistory() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let repository = FileMeetingHistoryRepository(fileURL: fileURL)
        let expected = [meeting(id: UUID(), endedAt: 100)]

        try repository.save(expected)

        XCTAssertEqual(try repository.load(), expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLegacyInsightHistoryFileIsRemoved() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("recent-insights.json")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Data("legacy insight text".utf8).write(to: fileURL)

        try LegacyInsightHistoryFile.remove(at: fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func meeting(
        id: UUID,
        endedAt: TimeInterval,
        transcriptText: String = "Transcript",
        profile: MeetingProfile = .fallback
    ) -> SavedMeeting {
        SavedMeeting(
            id: id,
            startedAt: Date(timeIntervalSince1970: endedAt - 30),
            endedAt: Date(timeIntervalSince1970: endedAt),
            transcriptSegments: [
                segment(sequenceNumber: 1, startOffset: 0, endOffset: 30, text: transcriptText)
            ],
            insights: [],
            incompleteTranscript: false,
            profile: profile
        )
    }

    private func segment(
        sequenceNumber: UInt64,
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        text: String
    ) -> SavedTranscriptSegment {
        SavedTranscriptSegment(
            sequenceNumber: sequenceNumber,
            startOffset: startOffset,
            endOffset: endOffset,
            text: text
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

private final class TestMeetingHistoryRepository: MeetingHistoryPersisting {
    var meetings: [SavedMeeting]
    var shouldFailLoads = false
    var shouldFailSaves = false
    private(set) var saveCount = 0

    init(meetings: [SavedMeeting] = []) {
        self.meetings = meetings
    }

    func load() throws -> [SavedMeeting] {
        if shouldFailLoads {
            throw TestError.loadFailed
        }
        return meetings
    }

    func save(_ meetings: [SavedMeeting]) throws {
        saveCount += 1
        if shouldFailSaves {
            throw TestError.saveFailed
        }
        self.meetings = meetings
    }

    private enum TestError: Error {
        case loadFailed
        case saveFailed
    }
}
