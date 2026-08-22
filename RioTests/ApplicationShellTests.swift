import Security
import XCTest

@MainActor
final class ApplicationShellTests: XCTestCase {
    func testPanelRouterSelectsProvider() {
        let router = RioPanelRouter()

        router.showProvider()
        XCTAssertEqual(router.presentedPanel, .provider)

        router.showProfiles()
        XCTAssertEqual(router.presentedPanel, .profiles)
    }

    func testStatusItemUsesNativeMenuRouting() {
        let suiteName = "RioTests.StatusItemMenu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let statusItemController = RioStatusItemController(
            controller: FakeSessionController(),
            providerSettings: OpenAIProviderSettings(keyStore: TestOpenAIAPIKeyStore()),
            meetingProfileSettings: MeetingProfileSettings(defaults: defaults),
            panelRouter: RioPanelRouter()
        )

        XCTAssertTrue(statusItemController.statusItem.menu === statusItemController.menu)
        XCTAssertEqual(statusItemController.statusItem.button?.image?.isTemplate, true)
        XCTAssertEqual(statusItemController.menu.items.map(\.title), [
            "Open Rio",
            "Start Listening",
            "Manage Profiles…",
            "Recent Meetings",
            "Provider & API Key…",
            "",
            "Quit Rio",
        ])
        XCTAssertTrue(statusItemController.menu.items.filter { $0.action != nil }.allSatisfy { $0.target != nil })
    }

    func testLiveCompositionUsesFixedEnglishUSLocale() {
        XCTAssertEqual(RioCompositionRoot.defaultLocaleIdentifier, "en-US")
    }

    func testAPIKeyOnlyWindowUsesCompactHeight() {
        XCTAssertEqual(
            RioMainWindowSizing.minimumContentHeight(
                apiKeyOnly: true,
                needsSetup: true,
                compactReady: false
            ),
            80
        )
        XCTAssertLessThanOrEqual(
            RioMainWindowSizing.windowHeight(
                apiKeyOnly: true,
                needsSetup: true,
                compactReady: false
            ),
            140
        )
    }

    func testReadyWindowUsesCompactHeight() {
        XCTAssertEqual(
            RioMainWindowSizing.minimumContentHeight(
                apiKeyOnly: false,
                needsSetup: false,
                compactReady: true
            ),
            120
        )
        XCTAssertLessThanOrEqual(
            RioMainWindowSizing.windowHeight(
                apiKeyOnly: false,
                needsSetup: false,
                compactReady: true
            ),
            180
        )
        XCTAssertEqual(
            RioMainWindowSizing.windowHeight(
                apiKeyOnly: false,
                needsSetup: false,
                compactReady: false
            ),
            240
        )
    }

    func testListeningCadencePersistsAndExplainsItsTradeoff() {
        let suiteName = "RioTests.ListeningCadence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ListeningCadenceSettings(defaults: defaults)
        XCTAssertEqual(settings.selection, .thirtySeconds)
        XCTAssertEqual(settings.selection.title, "30 seconds")

        settings.selection = .fortyFiveSeconds

        let reloadedSettings = ListeningCadenceSettings(defaults: defaults)
        XCTAssertEqual(reloadedSettings.selection, .fortyFiveSeconds)
        XCTAssertTrue(reloadedSettings.selection.detail.contains("Fewer requests"))
    }

    func testStartListeningAllowsPermissionRequestButRequiresBlockingChecks() {
        let controller = FakeSessionController()

        XCTAssertFalse(controller.isReadyToStartListening)

        controller.inject(
            status: .stopped,
            readiness: SessionReadiness(
                checks: PrerequisiteKind.allCases.map {
                    PrerequisiteCheck(kind: $0, reason: nil)
                }
            )
        )

        XCTAssertTrue(controller.isReadyToStartListening)

        controller.inject(
            status: .stopped,
            readiness: SessionReadiness(
                checks: [
                    PrerequisiteCheck(
                        kind: .meetingAudio,
                        reason: .systemAudioPermissionDenied
                    )
                ]
            )
        )

        XCTAssertTrue(controller.isReadyToStartListening)

        controller.inject(
            status: .stopped,
            readiness: SessionReadiness(
                checks: [
                    PrerequisiteCheck(
                        kind: .openAI,
                        reason: .openAIAPIKeyMissing
                    )
                ]
            )
        )

        XCTAssertFalse(controller.isReadyToStartListening)
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

    func testInsightFailuresExplainActionableRecovery() {
        let rateLimited = SessionStatusPresentation(
            status: .unavailable,
            failure: .stage(.insightGeneration, .rateLimited)
        )
        XCTAssertTrue(rateLimited.detail.contains("rate-limited"))

        let rejected = SessionStatusPresentation(
            status: .unavailable,
            failure: .stage(.insightGeneration, .requestRejected(statusCode: 400))
        )
        XCTAssertTrue(rejected.detail.contains("HTTP 400"))
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
        XCTAssertTrue(presentation.detail.contains("Provider settings"))
        XCTAssertTrue(presentation.detail.contains("temporary meeting text"))
        XCTAssertEqual(presentation.symbolName, "exclamationmark.circle.fill")
    }

    func testMeetingTranscriptionPresentationNamesItsAPIRequirement() {
        let presentation = PrerequisiteCheckPresentation(
            check: PrerequisiteCheck(
                kind: .meetingTranscription,
                reason: .openAIAPIKeyMissing
            )
        )

        XCTAssertEqual(presentation.title, "Meeting transcription")
        XCTAssertTrue(presentation.detail.contains("meeting-audio chunks"))
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

    func testMeetingAudioActionTargetsTheScreenRecordingPrivacyPane() {
        XCTAssertEqual(
            SystemSettingsOpener.systemAudioRecordingURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testSystemAudioPermissionDenialOffersDirectSettingsRecovery() {
        let presentation = SessionStatusPresentation(
            status: .unavailable,
            unavailableReason: .systemAudioPermissionDenied
        )

        XCTAssertEqual(presentation.recoveryAction, .openSystemAudioRecording)
        XCTAssertFalse(presentation.detail.contains("System Settings →"))
    }

    func testSystemAudioCaptureFailureDoesNotClaimPermissionIsMissing() {
        let presentation = SessionStatusPresentation(
            status: .unavailable,
            unavailableReason: .systemAudioCaptureFailed
        )

        XCTAssertTrue(presentation.detail.contains("could not start system audio capture"))
        XCTAssertFalse(presentation.detail.contains("needs System Audio Recording access"))
        XCTAssertEqual(presentation.recoveryAction, .openSystemAudioRecording)
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
        XCTAssertTrue(presentation.detail.contains("Transcription is active"))
        XCTAssertFalse(presentation.detail.contains("chunks collected"))
        XCTAssertFalse(presentation.detail.contains("transcript"))
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

    func testRecentMeetingDetailOffersInsightsAndTranscriptSections() {
        XCTAssertEqual(
            RecentMeetingDetailSection.allCases,
            [.insights, .transcript]
        )
        XCTAssertEqual(RecentMeetingDetailSection.insights.title, "Insights")
        XCTAssertEqual(RecentMeetingDetailSection.transcript.title, "Transcript")
    }

    func testRecentMeetingTranscriptIsPresentedInChronologicalOrder() {
        let presentation = RecentMeetingDetailPresentation(
            insights: [],
            transcriptSegments: [
                RecentTranscriptSegment(sequenceNumber: 2, text: "The later point."),
                RecentTranscriptSegment(sequenceNumber: 1, text: "The opening point."),
            ]
        )

        XCTAssertEqual(
            presentation.transcriptText,
            "The opening point.\nThe later point."
        )
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

}

private final class TestOpenAIAPIKeyStore: OpenAIAPIKeyStore, @unchecked Sendable {
    var storedValue: String?

    func load() throws -> String? { storedValue }
    func save(_ key: String) throws { storedValue = key }
    func remove() throws { storedValue = nil }
}
