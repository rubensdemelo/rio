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

    func testRecordPersistsACompletedMeetingAndKeepsNewestFirst() {
        let repository = TestMeetingHistoryRepository()
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        let older = meeting(id: UUID(), endedAt: 50)
        let newer = meeting(id: UUID(), endedAt: 100)

        history.record(older, now: date(100))
        history.record(newer, now: date(100))

        XCTAssertEqual(history.meetings.map(\.id), [newer.id, older.id])
        XCTAssertEqual(repository.meetings, history.meetings)
    }

    func testLoadingAndWritingPrunesMeetingsOutsideTheLastTwoDays() {
        let now = date(100_000)
        let expired = meeting(id: UUID(), endedAt: now.timeIntervalSince1970 - MeetingHistoryStore.retention - 1)
        let recent = meeting(id: UUID(), endedAt: now.timeIntervalSince1970)
        let repository = TestMeetingHistoryRepository(meetings: [expired, recent])

        let history = MeetingHistoryStore(repository: repository, now: now)

        XCTAssertEqual(history.meetings.map(\.id), [recent.id])
        XCTAssertEqual(repository.meetings, [recent])

        history.record(expired, now: now)

        XCTAssertEqual(history.meetings, [recent])
        XCTAssertEqual(repository.meetings, [recent])
    }

    func testRecordingTheSameMeetingIDReplacesThePreviousSnapshot() {
        let repository = TestMeetingHistoryRepository()
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        let id = UUID()

        history.record(
            meeting(id: id, endedAt: 50, transcriptText: "Initial"),
            now: date(100)
        )
        history.record(
            meeting(id: id, endedAt: 60, transcriptText: "Final"),
            now: date(100)
        )

        XCTAssertEqual(history.meetings.count, 1)
        XCTAssertEqual(history.meetings[0].transcriptSegments.map(\.text), ["Final"])
    }

    func testClearMeetingAndClearAllPersistTheChange() {
        let repository = TestMeetingHistoryRepository()
        let history = MeetingHistoryStore(repository: repository, now: date(100))
        let first = meeting(id: UUID(), endedAt: 50)
        let second = meeting(id: UUID(), endedAt: 60)
        history.record(first, now: date(100))
        history.record(second, now: date(100))

        history.clear(meetingID: first.id)

        XCTAssertEqual(history.meetings, [second])
        XCTAssertEqual(repository.meetings, [second])

        history.clearAll()

        XCTAssertTrue(history.meetings.isEmpty)
        XCTAssertTrue(repository.meetings.isEmpty)
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
    }

    func testSavedMeetingRoundTripsTheMeetingProfile() throws {
        let expected = meeting(id: UUID(), endedAt: 100, profile: .internalTechnical)

        let decoded = try JSONDecoder().decode(
            SavedMeeting.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded.profile, .internalTechnical)
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

    private func meeting(
        id: UUID,
        endedAt: TimeInterval,
        transcriptText: String = "Transcript",
        profile: MeetingProfile = .customerCritical
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

    init(meetings: [SavedMeeting] = []) {
        self.meetings = meetings
    }

    func load() throws -> [SavedMeeting] { meetings }

    func save(_ meetings: [SavedMeeting]) throws {
        self.meetings = meetings
    }
}
