import Security
import XCTest

@MainActor
final class ApplicationShellTests: XCTestCase {

    func testInsightAccessibilityDoesNotExposeAnOwner() {
        let changedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let card = InsightCard(
            stableKey: "synthetic-owner",
            category: .action,
            text: "Synthetic action",
            explicitOwner: "Alex",
            state: .new,
            changedAt: changedAt
        )

        XCTAssertFalse(card.accessibilityDescription.contains("Owner:"))
        XCTAssertFalse(card.accessibilityDescription.contains("Alex"))
        XCTAssertTrue(
            card.accessibilityDescription.contains(
                changedAt.formatted(date: .abbreviated, time: .shortened)
            )
        )
    }

    func testStatusAndEmptyPresentationsAreDeterministic() {
        MainActor.assertIsolated()

        let stopped = SessionStatusPresentation(status: .stopped)
        let reconnecting = SessionStatusPresentation(status: .interrupted)
        let interrupted = SessionStatusPresentation(
            status: .interrupted,
            failure: .stage(.audioCapture, .interrupted)
        )
        let unavailable = SessionStatusPresentation(
            status: .unavailable,
            unavailableReason: .openAIAPIKeyMissing
        )

        XCTAssertEqual(stopped.title, "Stopped")
        XCTAssertEqual(reconnecting.title, "Reconnecting meeting audio")
        XCTAssertEqual(interrupted.title, "Interrupted")
        XCTAssertEqual(unavailable.title, "Unavailable")
        XCTAssertEqual(
            SessionStatusPresentation(
                status: .unavailable,
                failure: .stage(.speechRecognition, .failed)
            ).detail,
            "Meeting transcription stopped unexpectedly. Start listening again."
        )
        XCTAssertEqual(
            EmptyStatePresentation(status: .stopped, statusDetail: stopped.detail).title,
            "Ready to listen"
        )
        XCTAssertEqual(
            EmptyStatePresentation(status: .interrupted, statusDetail: interrupted.detail).title,
            "Listening was interrupted"
        )
        XCTAssertEqual(
            EmptyStatePresentation(status: .unavailable, statusDetail: unavailable.detail).detail,
            "Resolve the unavailable prerequisite above, then try again."
        )
    }

    func testTranscriptionOverloadExplainsContinuityAndRecovery() {
        let presentation = SessionStatusPresentation(
            status: .unavailable,
            failure: .stage(.speechRecognition, .overloaded)
        )

        XCTAssertTrue(presentation.detail.contains("before skipping meeting audio"))
        XCTAssertTrue(presentation.detail.contains("marked incomplete"))
        XCTAssertTrue(presentation.detail.contains("Start listening again"))
    }

    func testOpenAIPrerequisiteExplainsTheRequiredConfigurationAndPrivacyBoundary() {
        let presentation = PrerequisiteCheckPresentation(
            check: PrerequisiteCheck(
                kind: .openAI,
                reason: .openAIAPIKeyMissing
            )
        )

        XCTAssertEqual(presentation.title, "OpenAI API")
        XCTAssertTrue(presentation.detail.contains("Provider settings"))
        XCTAssertTrue(presentation.detail.contains("temporary meeting text"))
        XCTAssertEqual(presentation.symbolName, "exclamationmark.circle.fill")
    }

    func testBringYourOwnKeyStoresOnlyAConfiguredState() {
        let store = TestOpenAIAPIKeyStore()
        let settings = OpenAIProviderSettings(keyStore: store)

        XCTAssertEqual(settings.providerName, "OpenAI")
        XCTAssertFalse(settings.isConfigured)

        settings.apiKey = " test-key "
        XCTAssertTrue(settings.save())
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(store.storedValue, "test-key")
        XCTAssertTrue(settings.apiKey.isEmpty)

        settings.remove()
        XCTAssertFalse(settings.isConfigured)
        XCTAssertNil(store.storedValue)
    }

    func testRuntimeAPIKeyStorePersistsInTheKeychain() {
        XCTAssertTrue(
            OpenAIAPIKeyStoreFactory.makeRuntimeStore() is KeychainOpenAIAPIKeyStore
        )
    }

    func testKeychainStoreUsesTheDataProtectionKeychain() {
        let query = KeychainOpenAIAPIKeyStore().baseQuery

        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }

    func testVoiceFeedbackShowsLongMeetingProgressWithoutMeetingText() {
        let presentation = VoiceFeedbackPresentation(
            status: .listening,
            feedback: SessionFeedbackSnapshot(
                audioInput: AudioInputSnapshot(
                    level: 0.65,
                    hasReceivedAudio: true,
                    isMuted: false
                ),
                finalizedSpeechSegmentCount: 76,
                latestFinalizedSpeechEndOffset: .seconds(3_620)
            )
        )

        XCTAssertTrue(presentation.detail.contains("Transcription is active"))
        XCTAssertFalse(presentation.detail.contains("message chunks"))
        XCTAssertTrue(presentation.detail.contains("1:00:20"))
        XCTAssertFalse(presentation.detail.contains("meeting text"))
    }

    func testLongTranscriptCanBeNavigatedByTimeAndFilteredWithoutChangingSavedText() {
        let presentation = RecentMeetingDetailPresentation(
            insights: [],
            transcriptSegments: [
                RecentTranscriptSegment(
                    sequenceNumber: 3,
                    startOffset: 3_605,
                    endOffset: 3_635,
                    text: "The billing workspace still returns 403."
                ),
                RecentTranscriptSegment(
                    sequenceNumber: 1,
                    startOffset: 5,
                    endOffset: 35,
                    text: "The customer described the sign-in issue."
                ),
            ]
        )

        XCTAssertEqual(
            presentation.orderedTranscriptSegments.map(\.timestamp),
            ["00:05", "1:00:05"]
        )
        XCTAssertEqual(
            presentation.transcriptSegments(matching: "403").map(\.sequenceNumber),
            [3]
        )
        XCTAssertEqual(presentation.transcriptSegments(matching: "missing"), [])
        XCTAssertEqual(presentation.transcriptText, "The customer described the sign-in issue.\nThe billing workspace still returns 403.")
    }

    func testTerminationCoordinatorCoalescesRepeatedQuitRequests() async {
        let state = TerminationPreparationState()
        let preparationStarted = expectation(description: "preparation started")
        let allowTermination = expectation(description: "termination allowed")
        let coordinator = RioApplicationTerminationCoordinator {
            state.preparationCount += 1
            preparationStarted.fulfill()
            await Task.yield()
            return true
        }

        coordinator.request { allowed in
            XCTAssertTrue(allowed)
            allowTermination.fulfill()
        }
        coordinator.request { _ in
            XCTFail("A repeated quit must join the in-flight preparation")
        }

        await fulfillment(of: [preparationStarted, allowTermination])
        XCTAssertEqual(state.preparationCount, 1)
    }

    func testTerminationCoordinatorRefusesQuitAfterSaveFailureAndAllowsRetry() async {
        let state = TerminationPreparationState()
        let firstReply = expectation(description: "first reply")
        let secondReply = expectation(description: "second reply")
        let coordinator = RioApplicationTerminationCoordinator {
            state.shouldSucceed
        }

        coordinator.request { allowed in
            state.replies.append(allowed)
            firstReply.fulfill()
        }
        await fulfillment(of: [firstReply])

        state.shouldSucceed = true
        coordinator.request { allowed in
            state.replies.append(allowed)
            secondReply.fulfill()
        }
        await fulfillment(of: [secondReply])

        XCTAssertEqual(state.replies, [false, true])
    }

    func testTerminationPreparationStopsSessionBeforeRetryingPendingHistory() async {
        let events = TerminationEventState()
        let session = TestTerminationSession(events: events)
        let history = TestTerminationHistory(events: events, hasPendingRecord: true)
        let preparation = RioTerminationPreparation(session: session, history: history)

        let allowed = await preparation.prepare()

        XCTAssertTrue(allowed)
        XCTAssertEqual(events.values, ["stop", "retry"])
        XCTAssertEqual(history.retryCount, 1)
    }

    func testTerminationPreparationRefusesQuitWhenRetryStillFails() async {
        let events = TerminationEventState()
        let session = TestTerminationSession(events: events)
        let history = TestTerminationHistory(
            events: events,
            hasPendingRecord: true,
            retryFails: true
        )
        let preparation = RioTerminationPreparation(session: session, history: history)

        let allowed = await preparation.prepare()

        XCTAssertFalse(allowed)
        XCTAssertEqual(events.values, ["stop", "retry"])
        XCTAssertTrue(history.hasPendingTerminationRecord)
    }

}

@MainActor
private final class TerminationPreparationState {
    var preparationCount = 0
    var shouldSucceed = false
    var replies: [Bool] = []
}

@MainActor
private final class TerminationEventState {
    var values: [String] = []
}

@MainActor
private final class TestTerminationSession: RioTerminationSessionPreparing {
    private let events: TerminationEventState

    init(events: TerminationEventState) {
        self.events = events
    }

    func prepareForTermination() async {
        events.values.append("stop")
    }
}

@MainActor
private final class TestTerminationHistory: RioTerminationHistoryPreparing {
    private let events: TerminationEventState
    private let retryFails: Bool
    private(set) var hasPendingTerminationRecord: Bool
    private(set) var retryCount = 0

    init(
        events: TerminationEventState,
        hasPendingRecord: Bool,
        retryFails: Bool = false
    ) {
        self.events = events
        hasPendingTerminationRecord = hasPendingRecord
        self.retryFails = retryFails
    }

    func retryPendingTerminationRecord() throws {
        events.values.append("retry")
        retryCount += 1
        if retryFails {
            throw TestFailure.saveFailed
        }
        hasPendingTerminationRecord = false
    }

    private enum TestFailure: Error {
        case saveFailed
    }
}

private final class TestOpenAIAPIKeyStore: OpenAIAPIKeyStore, @unchecked Sendable {
    var storedValue: String?

    func load() throws -> String? { storedValue }
    func save(_ key: String) throws { storedValue = key }
    func remove() throws { storedValue = nil }
}
