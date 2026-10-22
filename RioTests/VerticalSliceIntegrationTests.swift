import Foundation
import XCTest

@MainActor
final class VerticalSliceIntegrationTests: XCTestCase {
    func testVerticalSliceShowsCardsStopsCleansAndRejectsStaleResults() async throws {
        let capture = TestSessionAudioCapture()
        let speech = TestSessionSpeechRecognizer()
        let generator = TestSessionInsightGenerator(
            delay: .milliseconds(50),
            updates: [],
            updateProvider: { batch in
                let sourceText = batch.segments.first?.text ?? ""
                let cardText = sourceText == "old session" ? "old card" : "new card"
                return [
                    InsightUpdate(
                        stableKey: "decision-1",
                        operation: .add,
                        category: .decision,
                        text: cardText,
                        explicitOwner: nil
                    )
                ]
            },
            ignoresCancellation: true
        )
        let contextFactory = TestMeetingContextFactory()
        let store = InMemoryInsightStore()
        let lifecycle = SessionLifecycleCoordinator(
            localeIdentifier: "en-US",
            capture: capture,
            speechRecognizer: speech,
            contextFactory: contextFactory,
            insightGenerator: generator,
            insightState: store
        )
        let controller = LiveSessionController(
            lifecycle: lifecycle,
            insightStore: store
        )

        await controller.performPrimaryAction()
        XCTAssertEqual(controller.status, SessionStatus.listening)

        let firstSpeechStream = await speech.lastStream()
        firstSpeechStream?.yield(makeSegment(sequence: 1, text: "old session"))
        await waitUntil(description: "first processing") {
            controller.status == SessionStatus.processing || controller.cards.count == 1
        }

        await controller.performPrimaryAction()
        XCTAssertEqual(controller.status, SessionStatus.stopped)
        XCTAssertTrue(controller.cards.isEmpty)

        await waitUntil(description: "first context cleanup") {
            contextFactory.contexts().count == 1
        }
        let firstContext = contextFactory.contexts()[0]
        let firstContextSegments = await firstContext.storedSegments()
        XCTAssertTrue(firstContextSegments.isEmpty)

        await controller.performPrimaryAction()
        XCTAssertEqual(controller.status, SessionStatus.listening)
        let secondSpeechStream = await speech.lastStream()
        secondSpeechStream?.yield(makeSegment(sequence: 1, text: "new session"))

        await waitUntil(description: "new card") {
            controller.cards.count == 1 && controller.cards[0].text == "new card"
        }
        try await Task.sleep(for: .milliseconds(75))
        XCTAssertEqual(controller.cards.map(\.text), ["new card"])

        await controller.performPrimaryAction()
        XCTAssertEqual(controller.status, SessionStatus.stopped)
        XCTAssertTrue(controller.cards.isEmpty)

        let contexts = contextFactory.contexts()
        XCTAssertEqual(contexts.count, 2)
        let secondContextSegments = await contexts[1].storedSegments()
        let captureStarts = await capture.startCount()
        let captureStops = await capture.stopCount()
        let generatorStarts = await generator.startSessionCount()
        let generatorStops = await generator.stopCount()
        XCTAssertTrue(secondContextSegments.isEmpty)
        XCTAssertEqual(captureStarts, 2)
        XCTAssertEqual(captureStops, 2)
        XCTAssertEqual(generatorStarts, 2)
        XCTAssertEqual(generatorStops, 2)
    }

    func testAudioLevelUpdatesDoNotInvalidateTheSessionController() async {
        let capture = TestSessionAudioCapture(inputSnapshot: liveInput(level: 0.2))
        let store = InMemoryInsightStore()
        let lifecycle = SessionLifecycleCoordinator(
            localeIdentifier: "en-US",
            capture: capture,
            speechRecognizer: TestSessionSpeechRecognizer(),
            contextFactory: TestMeetingContextFactory(),
            insightGenerator: TestSessionInsightGenerator(),
            insightState: store
        )
        let controller = LiveSessionController(lifecycle: lifecycle, insightStore: store)
        await controller.performPrimaryAction()
        XCTAssertEqual(controller.status, SessionStatus.listening)
        await waitUntil(description: "initial level") {
            controller.feedback.snapshot.audioInput.level == 0.2
        }

        let sessionViewChanged = expectation(description: "session view state changed")
        sessionViewChanged.isInverted = true
        withObservationTracking {
            _ = controller.status
            _ = controller.cards
            _ = controller.readiness
            _ = controller.unavailableReason
            _ = controller.failure
            _ = controller.isPerformingPrimaryAction
            _ = controller.isPerformingPauseAction
        } onChange: {
            sessionViewChanged.fulfill()
        }
        for level: Float in [0.3, 0.6, 0.4] {
            await capture.setInputSnapshot(liveInput(level: level))
            await waitUntil(description: "level \(level)") {
                controller.feedback.snapshot.audioInput.level == level
            }
        }

        await fulfillment(of: [sessionViewChanged], timeout: 0.1)
        await controller.performPrimaryAction()
    }

    private func liveInput(level: Float) -> AudioInputSnapshot {
        AudioInputSnapshot(level: level, hasReceivedAudio: true, isMuted: false)
    }

    private func waitUntil(
        description: String = "transition",
        timeout: Duration = .seconds(8),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for vertical slice \(description)")
    }

    private func makeSegment(sequence: UInt64, text: String) -> FinalizedSpeechSegment {
        FinalizedSpeechSegment(
            sequenceNumber: sequence,
            text: text,
            startOffset: .zero,
            endOffset: .seconds(1)
        )
    }
}
