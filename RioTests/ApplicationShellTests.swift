import Security
import XCTest

@MainActor
final class ApplicationShellTests: XCTestCase {
    func testRioLaunchesAsAMenuBarOnlyAccessory() {
        XCTAssertEqual(RioLaunchPresentation.activationPolicy, .accessory)
        XCTAssertFalse(RioLaunchPresentation.opensMainWindowOnLaunch)
    }

    func testPanelRouterSelectsProvider() {
        let router = RioPanelRouter()

        router.showProvider()
        XCTAssertEqual(router.presentedPanel, .provider)

        router.showProfiles()
        XCTAssertEqual(router.presentedPanel, .profiles)
    }

    func testMenuWindowRouterCreatesSuppressedWindowsWhenNoneExistYet() {
        var openedWindowIDs: [String] = []
        var activationCount = 0
        let router = RioMenuWindowRouter(
            openWindow: { openedWindowIDs.append($0) },
            activate: { activationCount += 1 }
        )

        router.open(.main)
        router.open(.profiles)
        router.open(.recentMeetings)
        router.open(.diagnostics)

        XCTAssertEqual(
            openedWindowIDs,
            ["main", "profiles", "recent-meetings", "diagnostics"]
        )
        XCTAssertEqual(activationCount, 4)
    }

    func testLiveCompositionUsesFixedEnglishUSLocale() {
        XCTAssertEqual(RioCompositionRoot.defaultLocaleIdentifier, "en-US")
    }

    func testWindowSizingKeepsSetupCompactAndExpandsForInsights() {
        let apiKeyOnlyHeight = RioMainWindowSizing.windowHeight(
            apiKeyOnly: true,
            needsSetup: true,
            compactReady: false
        )
        let readyHeight = RioMainWindowSizing.windowHeight(
            apiKeyOnly: false,
            needsSetup: false,
            compactReady: true
        )
        let idleHeight = RioMainWindowSizing.windowHeight(
            apiKeyOnly: false,
            needsSetup: false,
            compactReady: false
        )
        let activeHeight = RioMainWindowSizing.windowHeight(
            apiKeyOnly: false,
            needsSetup: false,
            compactReady: false,
            hasInsights: true
        )

        XCTAssertLessThan(apiKeyOnlyHeight, idleHeight)
        XCTAssertLessThan(readyHeight, idleHeight)
        XCTAssertGreaterThan(activeHeight, idleHeight)
        XCTAssertGreaterThan(
            RioMainWindowSizing.windowWidth(hasInsights: true),
            RioMainWindowSizing.windowWidth(hasInsights: false)
        )
    }

    func testListeningCadencePersistsAndExplainsItsTradeoff() {
        let suiteName = "RioTests.ListeningCadence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ListeningCadenceSettings(defaults: defaults)
        XCTAssertEqual(settings.selection, .thirtySeconds)
        XCTAssertEqual(settings.selection.title, "30 seconds")

        settings.selection = .ninetySeconds

        let reloadedSettings = ListeningCadenceSettings(defaults: defaults)
        XCTAssertEqual(reloadedSettings.selection, .ninetySeconds)
        XCTAssertTrue(reloadedSettings.selection.detail.contains("Fewest requests"))
        XCTAssertEqual(ListeningCadence.allCases, [.thirtySeconds, .sixtySeconds, .ninetySeconds])
    }

    func testListeningCadenceMigratesLegacyStoredValues() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(ListeningCadence.self, from: Data("15".utf8)),
            .thirtySeconds
        )
        XCTAssertEqual(
            try JSONDecoder().decode(ListeningCadence.self, from: Data("45".utf8)),
            .sixtySeconds
        )
    }

    func testLiveInsightsArePresentedNewestFirst() {
        let cards = [
            InsightCard(
                stableKey: "older",
                category: .risk,
                text: "Older risk",
                explicitOwner: nil,
                state: .new,
                changedAt: Date(timeIntervalSince1970: 100)
            ),
            InsightCard(
                stableKey: "newest",
                category: .decision,
                text: "Newest decision",
                explicitOwner: nil,
                state: .new,
                changedAt: Date(timeIntervalSince1970: 300)
            ),
            InsightCard(
                stableKey: "middle",
                category: .question,
                text: "Middle question",
                explicitOwner: nil,
                state: .updated,
                changedAt: Date(timeIntervalSince1970: 200)
            ),
        ]

        let presentation = LiveInsightPresentation(cards: cards)

        XCTAssertEqual(
            presentation.cards.map(\.stableKey),
            ["newest", "middle", "older"]
        )
    }

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
