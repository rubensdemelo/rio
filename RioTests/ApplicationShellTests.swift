import XCTest

@MainActor
final class ApplicationShellTests: XCTestCase {
    func testLiveCompositionUsesFixedEnglishUSLocale() {
        XCTAssertEqual(RioCompositionRoot.defaultLocaleIdentifier, "en-US")
    }

    func testPrimaryActionStartsAndStopsExactlyOnce() async {
        let card = InsightCard(
            stableKey: "synthetic-card",
            category: .important,
            text: "Synthetic insight",
            explicitOwner: nil,
            state: .new
        )
        let controller = FakeSessionController(cards: [card])

        await controller.performPrimaryAction()

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.stopCount, 0)
        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(controller.primaryActionTitle, "Stop Listening")

        await controller.performPrimaryAction()

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.stopCount, 1)
        XCTAssertEqual(controller.status, .stopped)
        XCTAssertTrue(controller.cards.isEmpty)
        XCTAssertEqual(controller.primaryActionTitle, "Start Listening")
    }

    func testInjectedCardsExposeNewUpdatedAndResolvedStates() {
        let cards = [
            InsightCard(
                stableKey: "synthetic-new",
                category: .important,
                text: "New synthetic insight",
                explicitOwner: nil,
                state: .new
            ),
            InsightCard(
                stableKey: "synthetic-updated",
                category: .decision,
                text: "Updated synthetic insight",
                explicitOwner: nil,
                state: .updated
            ),
            InsightCard(
                stableKey: "synthetic-resolved",
                category: .question,
                text: "Resolved synthetic insight",
                explicitOwner: nil,
                state: .resolved
            ),
        ]
        let controller = FakeSessionController()

        controller.inject(status: .listening, cards: cards)

        XCTAssertEqual(controller.cards, cards)
        XCTAssertEqual(controller.cards.map(\.state), [.new, .updated, .resolved])
        XCTAssertEqual(controller.status, .listening)
    }

    func testInsightAccessibilityDoesNotExposeAnOwner() {
        let card = InsightCard(
            stableKey: "synthetic-owner",
            category: .action,
            text: "Synthetic action",
            explicitOwner: "Alex",
            state: .new
        )

        XCTAssertFalse(card.accessibilityDescription.contains("Owner:"))
        XCTAssertFalse(card.accessibilityDescription.contains("Alex"))
    }

    func testUnavailableOutcomeNeverClaimsToBeListening() async {
        let reason = UnavailableReason.openAIAPIKeyMissing
        let controller = FakeSessionController(startOutcome: .unavailable(reason))

        await controller.performPrimaryAction()

        XCTAssertEqual(controller.status, .unavailable)
        XCTAssertEqual(controller.unavailableReason, reason)
        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.primaryActionTitle, "Start Listening")
    }

    func testInterruptedFailureUpdatesStatusAccurately() async {
        let failure = PipelineFailure.stage(.audioCapture, .interrupted)
        let controller = FakeSessionController(startOutcome: .failure(failure))

        await controller.performPrimaryAction()

        XCTAssertEqual(controller.status, .interrupted)
        XCTAssertEqual(controller.failure, failure)
        XCTAssertNotEqual(controller.status, .listening)
    }

    func testGenericPipelineFailureUpdatesToUnavailable() async {
        let failure = PipelineFailure.stage(.sessionLifecycle, .failed)
        let controller = FakeSessionController(startOutcome: .failure(failure))

        await controller.performPrimaryAction()

        XCTAssertEqual(controller.status, .unavailable)
        XCTAssertEqual(controller.failure, failure)
        XCTAssertNotEqual(controller.status, .listening)
    }

    func testStatusAndEmptyPresentationsAreDeterministic() {
        MainActor.assertIsolated()

        let stopped = SessionStatusPresentation(status: .stopped)
        let interrupted = SessionStatusPresentation(status: .interrupted)
        let unavailable = SessionStatusPresentation(
            status: .unavailable,
            unavailableReason: .openAIAPIKeyMissing
        )

        XCTAssertEqual(stopped.title, "Stopped")
        XCTAssertEqual(interrupted.title, "Interrupted")
        XCTAssertEqual(unavailable.title, "Unavailable")
        XCTAssertEqual(
            SessionStatusPresentation(
                status: .unavailable,
                failure: .stage(.speechRecognition, .failed)
            ).detail,
            "Speech recognition stopped unexpectedly. Start listening again."
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

    func testGenericUnavailableFailureDoesNotClaimSetupIsRequired() {
        let presentation = EmptyStatePresentation(
            status: .unavailable,
            statusDetail: "Rio could not start listening.",
            hasUnavailablePrerequisite: false
        )

        XCTAssertEqual(presentation.title, "Couldn’t restart listening")
        XCTAssertEqual(presentation.detail, "Try Start Listening again.")
    }

    func testOpenAIPrerequisiteExplainsTheRequiredConfigurationAndPrivacyBoundary() {
        let presentation = PrerequisiteCheckPresentation(
            check: PrerequisiteCheck(
                kind: .openAI,
                reason: .openAIAPIKeyMissing
            )
        )

        XCTAssertEqual(presentation.title, "OpenAI API")
        XCTAssertTrue(presentation.detail.contains("OPENAI_API_KEY"))
        XCTAssertTrue(presentation.detail.contains("temporary meeting text"))
        XCTAssertEqual(presentation.symbolName, "exclamationmark.circle.fill")
    }

    func testSpeechAssetsPresentationNamesTheRequiredEnglishAsset() {
        let presentation = PrerequisiteCheckPresentation(
            check: PrerequisiteCheck(
                kind: .speechRecognition,
                reason: .speechAssetsNotReady
            )
        )

        XCTAssertTrue(presentation.detail.contains("English (US)"))
        XCTAssertTrue(presentation.detail.contains("on-device speech-recognition asset"))
        XCTAssertTrue(presentation.detail.contains("nothing to add manually"))
    }

    func testMeetingAudioActionTargetsTheScreenRecordingPrivacyPane() {
        XCTAssertEqual(
            SystemSettingsOpener.screenAndSystemAudioRecordingURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testVoiceFeedbackUsesNonContentSpeechActivityInsteadOfTranscript() {
        let presentation = VoiceFeedbackPresentation(
            status: .listening,
            feedback: SessionFeedbackSnapshot(
                audioInput: AudioInputSnapshot(
                    level: 0.65,
                    hasReceivedAudio: true,
                    isMuted: false
                ),
                finalizedSpeechSegmentCount: 3
            )
        )

        XCTAssertEqual(presentation.condition, .live)
        XCTAssertEqual(presentation.title, "Meeting audio live")
        XCTAssertTrue(presentation.detail.contains("3 message chunks collected"))
        XCTAssertFalse(presentation.detail.contains("transcript"))
    }

    func testVoiceFeedbackDistinguishesMutedAndConnectionErrorStates() {
        let muted = VoiceFeedbackPresentation(
            status: .listening,
            feedback: SessionFeedbackSnapshot(
                audioInput: AudioInputSnapshot(
                    level: 0,
                    hasReceivedAudio: true,
                    isMuted: true
                ),
                finalizedSpeechSegmentCount: 0
            )
        )
        let connectionError = VoiceFeedbackPresentation(
            status: .unavailable,
            feedback: .inactive,
            failure: .stage(.audioCapture, .failed)
        )

        XCTAssertEqual(muted.condition, .muted)
        XCTAssertEqual(connectionError.condition, .connectionError)
        XCTAssertNotEqual(muted.condition, connectionError.condition)
    }

    func testFakeControllerPausesAndResumesWithoutClearingInsights() async {
        let card = InsightCard(
            stableKey: "pause-card",
            category: .decision,
            text: "A decision",
            explicitOwner: nil,
            state: .new
        )
        let controller = FakeSessionController(cards: [card])

        await controller.performPrimaryAction()
        await controller.performPauseAction()

        XCTAssertEqual(controller.status, .paused)
        XCTAssertEqual(controller.cards, [card])
        XCTAssertEqual(controller.pauseActionTitle, "Resume Listening")

        await controller.performPauseAction()
        XCTAssertEqual(controller.status, .listening)
        XCTAssertEqual(controller.cards, [card])
    }

}
